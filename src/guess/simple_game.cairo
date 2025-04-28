#[starknet::interface]
pub trait ISimpleGame<TContractState> {
    fn play(self: @TContractState, guess: u256);
}

#[starknet::contract]
mod SimpleGame {
    use alexandria_merkle_tree::merkle_tree::pedersen::PedersenHasherImpl;
    use ayn_random::utils::helpers;
    use openzeppelin_token::erc20::interface::{IERC20Dispatcher, IERC20DispatcherTrait};
    use starknet::storage::{StoragePointerReadAccess, StoragePointerWriteAccess};
    use starknet::{
        ContractAddress, get_block_number, get_block_timestamp, get_caller_address,
        get_contract_address,
    };

    #[storage]
    struct Storage {
        eth: IERC20Dispatcher
    }

    #[constructor]
    fn constructor(ref self: ContractState, eth: ContractAddress) {
        self.eth.write(IERC20Dispatcher { contract_address: eth });
    }

    #[abi(embed_v0)]
    impl SimpleGameImpl of super::ISimpleGame<ContractState> {
        // Play the game by submitting a guess
        fn play(self: @ContractState, guess: u256) {
            // Playing the game costs 1 ETH
            self
                .eth
                .read()
                .transfer_from(get_caller_address(), get_contract_address(), helpers::one_ether());

            let block_number_felt: felt252 = get_block_number().try_into().unwrap();
            let block_timestamp_felt: felt252 = get_block_timestamp().try_into().unwrap();
            let random_number: u256 = core::pedersen::pedersen(
                block_number_felt, block_timestamp_felt,
            )
                .into();

            // If the guess is correct, transfer the balance to the player
            if guess == random_number {
                let balance = self.eth.read().balance_of(get_contract_address());
                self.eth.read().transfer(get_caller_address(), balance);
            }
        }
    }
}
