use starknet::ContractAddress;

#[starknet::interface]
pub trait ILottery<TContractState> {
    fn get_last_winner(self: @TContractState) -> ContractAddress;
    fn request_winner(
        ref self: TContractState,
        seed: u64,
        callback_address: ContractAddress,
        callback_fee_limit: u128,
        publish_delay: u64,
        num_words: u64,
        calldata: Array<felt252>,
    );
    fn receive_random_words(
        ref self: TContractState,
        requestor_address: ContractAddress,
        request_id: u64,
        random_words: Span<felt252>,
        calldata: Array<felt252>,
    );
    fn buy_ticket(ref self: TContractState) -> u256;
    fn reset_lottery(ref self: TContractState);
}

#[starknet::contract]
mod Lottery {
    // VRF interface
    use ayn_random::lottery::interfaces::{IRandomnessDispatcher, IRandomnessDispatcherTrait};
    use ayn_random::utils::helpers;
    use openzeppelin_token::erc20::interface::{IERC20Dispatcher, IERC20DispatcherTrait};
    use starknet::storage::{
        Map, StorageMapReadAccess, StorageMapWriteAccess, StoragePathEntry,
        StoragePointerReadAccess, StoragePointerWriteAccess,
    };
    use starknet::{ContractAddress, get_block_number, get_caller_address, get_contract_address};

    #[storage]
    struct Storage {
        treasury: ContractAddress, // The treasury of the lottery, 10% of the pot goes there
        randomness_contract_address: ContractAddress, // VRF contract address
        min_block_number_storage: u64, // Minimum block number for the request
        last_winner: ContractAddress, // Last winner of the lottery
        tickets: u256, // Number of tickets bought in the current round (also represents the ticket IDs assigned - first ticket ID is 0)
        participants: Map<
            u256, ContractAddress,
        >, // Participants in the lottery current round (ticket ID -> address)
        currency: IERC20Dispatcher, // The currency to be used for the lottery (ETH)
        is_lottery_ended: bool, // Flag to check if the current round of the lottery ended
        is_request_active: bool // Flag to check if the request was made
    }

    #[constructor]
    fn constructor(
        ref self: ContractState,
        randomness_contract_address: ContractAddress,
        eth_address: ContractAddress,
        treasury: ContractAddress,
    ) {
        self.randomness_contract_address.write(randomness_contract_address);
        self.currency.write(IERC20Dispatcher { contract_address: eth_address });
        self.treasury.write(treasury);
    }

    #[abi(embed_v0)]
    impl ILotteryImpl of super::ILottery<ContractState> {
        // Get last winner of the lottery
        // @return ContractAddress of the last winner
        fn get_last_winner(self: @ContractState) -> ContractAddress {
            let last_winner = self.last_winner.read();
            return last_winner;
        }

        // Reset the lottery, can be called only when a round is finished
        fn reset_lottery(ref self: ContractState) {
            assert(self.is_lottery_ended.read(), 'Lottery is still running');

            // Reset the participants and tickets
            let mut i: u256 = 0;
            while i <= self.tickets.read() {
                self.participants.write(i, 0.try_into().unwrap());
                i += 1;
            }
            self.tickets.write(0);
            // Reset the flags
            self.is_lottery_ended.write(false);
            self.is_request_active.write(false);
        }

        // Buy a ticket for the lottery current round, first ticket ID is 0 and the last one is 999
        // A ticket costs 1 ETH, the user should approve spending for this contract prior to calling
        // this function @return u256: Ticket ID
        fn buy_ticket(ref self: ContractState) -> u256 {
            let caller = get_caller_address();
            let ticket_id = self.tickets.read();

            // Maximum 1000 participants per round (last ticket ID is 999)
            assert(ticket_id < 1000, 'Max tickets reached');

            // Add the participant to the current round
            self.participants.write(ticket_id, caller);
            // Increase the number of tickets purchased
            self.tickets.write(ticket_id + 1);

            // Particiation costs 1 ETH
            self
                .currency
                .read()
                .transfer_from(caller, get_contract_address(), helpers::one_ether());

            return ticket_id;
        }

        // Request the winner of the lottery only when at least 10 tickets were bought
        // @param seed: Seed for the randomness
        // @param callback_address: Address that will receive the callback from the randomness
        // contract @param callback_fee_limit: Fee limit for the randomness request
        // @param publish_delay: Delay for the randomness
        // @param num_words: Number of words to be requested for the randomness
        // @param calldata: Calldata for the randomness request
        fn request_winner(
            ref self: ContractState,
            seed: u64,
            callback_address: ContractAddress,
            callback_fee_limit: u128,
            publish_delay: u64,
            num_words: u64,
            calldata: Array<felt252>,
        ) {
            // Lottery should be ended, have at least 10 participants, and request should not be
            // made
            assert(!self.is_lottery_ended.read(), 'Lottery ended');
            assert(self.tickets.read() >= 9, 'Not enough participants');
            assert(!self.is_request_active.read(), 'Request already made');

            // Get the randomness contract
            let randomness_contract_address = self.randomness_contract_address.read();
            let randomness_dispatcher = IRandomnessDispatcher {
                contract_address: randomness_contract_address,
            };
            // Compute the fee for the randomness request
            let caller = get_caller_address();
            let compute_fees = randomness_dispatcher.compute_premium_fee(caller);

            // Approve the randomness contract to transfer the callback fee
            // FYI: We need to send some ETH to this contract first to cover the fees
            // Ticket price should cover the callback fee
            self
                .currency
                .read()
                .approve(
                    randomness_contract_address,
                    (callback_fee_limit + compute_fees + callback_fee_limit / 5).into(),
                );

            // Request the randomness
            let _request_id = randomness_dispatcher
                .request_random(
                    seed, callback_address, callback_fee_limit, publish_delay, num_words, calldata,
                );

            // Safeguard for the randomness request fullfillment
            let current_block_number = get_block_number();
            self.min_block_number_storage.write(current_block_number + publish_delay);
            self.is_request_active.write(true);
        }


        // Receive the random words from the randomness contract
        // @param requestor_address: Address that requested the randomness
        // @param request_id: ID of the request
        // @param random_words: Random words received
        // @param calldata: Calldata that was passed with the request
        fn receive_random_words(
            ref self: ContractState,
            requestor_address: ContractAddress,
            request_id: u64,
            random_words: Span<felt252>,
            calldata: Array<felt252>,
        ) {
            // @audit-issue Missing access control. Only the VRF contract should be able to call
            // this function

            // Only if request was made we can receive the random words
            assert(self.is_request_active.read(), 'No request made');

            // The current block should be within `publish_delay` of the request block
            let current_block_number = get_block_number();
            let min_block_number = self.min_block_number_storage.read();
            assert(min_block_number <= current_block_number, 'Not enough delay');

            // We use only 1 word for the randomness, and cast it to u256
            let random_word = *random_words.at(0);
            let num: u256 = random_word.into();

            // Get the winner
            // For example: if we have 20 participants, we have 20 tickets.
            // The last ticket ID is 19, because the first ticket ID is 0.
            // Winner Ticket ID == random number % number of tickets - everyone has an equal chance
            // to win For instance, if there are 20 participants, and the random number is 75
            // The winner ID is 75 % 19 = 18 (Ticket ID 18)
            let winner = self.participants.read(num % (self.tickets.read()));
            self.last_winner.write(winner);

            // End the lottery
            self.is_lottery_ended.write(true);

            // Transfer the funds to the winner (90% of the lottery pot to the winner, 10% goes to
            // the Treasury)
            let contract_balance = self.currency.read().balance_of(get_contract_address());
            let to_winner = contract_balance / 10 * 9;
            let to_treasuary = contract_balance / 10;
            self.currency.read().transfer(winner, to_winner);
            self.currency.read().transfer(self.treasury.read(), to_treasuary);
        }
    }
}
