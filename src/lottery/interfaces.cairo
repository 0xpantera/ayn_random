use starknet::ContractAddress;

// VRF Interface
#[starknet::interface]
pub trait IRandomness<TContractState> {
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
