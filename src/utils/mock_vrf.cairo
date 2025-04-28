use starknet::ContractAddress;


#[starknet::interface]
trait IRandomness<TContractState> {
    fn request_random(
        ref self: TContractState,
        seed: u64,
        callback_address: ContractAddress,
        callback_fee_limit: u128,
        publish_delay: u64,
        num_words: u64,
        calldata: Array<felt252>,
    ) -> u64;
    fn submit_random(
        ref self: TContractState,
        request_id: u64,
        requestor_address: ContractAddress,
        seed: u64,
        minimum_block_number: u64,
        callback_address: ContractAddress,
        callback_fee_limit: u128,
        callback_fee: u128,
        random_words: Span<felt252>,
        proof: Span<felt252>,
        calldata: Array<felt252>,
    );
    fn compute_premium_fee(self: @TContractState, caller_address: ContractAddress) -> u128;
}
#[starknet::interface]
trait IExampleRandomness<TContractState> {
    fn receive_random_words(
        ref self: TContractState,
        requestor_address: ContractAddress,
        request_id: u64,
        random_words: Span<felt252>,
        calldata: Array<felt252>,
    );
}

#[starknet::contract]
mod VRFMock {
    //use array::{ArrayTrait, SpanTrait};
    use openzeppelin_token::erc20::interface::{IERC20Dispatcher, IERC20DispatcherTrait};
    use starknet::storage::{StoragePointerReadAccess, StoragePointerWriteAccess};
    //use starknet::info::get_block_number;
    use starknet::{get_caller_address, get_contract_address};
    //use traits::{Into, TryInto};
    use super::{
        ContractAddress, IExampleRandomnessDispatcher, IExampleRandomnessDispatcherTrait,
        IRandomness,
    };


    #[storage]
    struct Storage {
        payment_token: ContractAddress,
    }


    #[constructor]
    fn constructor(ref self: ContractState, payment_token_address: ContractAddress) {
        self.payment_token.write(payment_token_address);
        return ();
    }

    #[abi(embed_v0)]
    impl IRandomnessImpl of IRandomness<ContractState> {
        fn request_random(
            ref self: ContractState,
            seed: u64,
            callback_address: ContractAddress,
            callback_fee_limit: u128, //the max amount the user can pay for the callback
            publish_delay: u64,
            num_words: u64,
            calldata: Array<felt252>,
        ) -> u64 {
            // Caller
            let caller_address = get_caller_address();
            // Contract
            let contract_address = get_contract_address();

            // get the current number of requests for the caller
            // get the contract dispatcher
            let token_address = self.payment_token.read();
            let token_dispatcher = IERC20Dispatcher { contract_address: token_address };
            // get the balance of the caller
            let total_fee = 100000;
            assert(
                token_dispatcher.allowance(caller_address, contract_address) >= total_fee,
                'no allowance',
            );
            token_dispatcher.transfer_from(caller_address, contract_address, total_fee);

            return (1_u64);
        }


        fn submit_random(
            ref self: ContractState,
            request_id: u64,
            requestor_address: ContractAddress,
            seed: u64,
            minimum_block_number: u64,
            callback_address: ContractAddress,
            callback_fee_limit: u128,
            callback_fee: u128, //the actual fee estimated off chain
            random_words: Span<felt252>,
            proof: Span<felt252>,
            calldata: Array<felt252>,
        ) {
            let example_randomness_dispatcher = IExampleRandomnessDispatcher {
                contract_address: callback_address,
            };
            example_randomness_dispatcher
                .receive_random_words(
                    requestor_address, request_id, random_words, calldata.clone(),
                );
        }
        fn compute_premium_fee(self: @ContractState, caller_address: ContractAddress) -> u128 {
            return 100000;
        }
    }
}
