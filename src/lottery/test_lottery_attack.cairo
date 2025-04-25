use ayn_random::lottery::lottery::{ILotteryDispatcher, ILotteryDispatcherTrait};
use ayn_random::utils::helpers;
use openzeppelin_token::erc20::interface::{IERC20Dispatcher, IERC20DispatcherTrait};
use snforge_std::{
    ContractClassTrait, DeclareResultTrait, declare, start_cheat_caller_address,
    stop_cheat_caller_address,
};
use starknet::ContractAddress;

fn deploy_lottery(
    pragma_vrf: ContractAddress, eth: ContractAddress, treasury: ContractAddress,
) -> (ContractAddress, ILotteryDispatcher) {
    let contract_class = declare("Lottery").unwrap().contract_class();
    let mut data_to_constructor = Default::default();
    Serde::serialize(@pragma_vrf, ref data_to_constructor);
    Serde::serialize(@eth, ref data_to_constructor);
    Serde::serialize(@treasury, ref data_to_constructor);
    let (address, _) = contract_class.deploy(@data_to_constructor).unwrap();
    return (address, ILotteryDispatcher { contract_address: address });
}

// Deploying a MOCK pragma VRF contract
// Note: The pragma VRF contract is a mock contract for testing purposes, and not a real VRF
// contract Note: If there are bugs in this contract, they are out of scope of this exercises :)
fn deploy_pragma_mock(eth: ContractAddress) -> ContractAddress {
    let contract_class = declare("VRFMock").unwrap().contract_class();
    let mut data_to_constructor = Default::default();
    Serde::serialize(@eth, ref data_to_constructor);
    let (address, _) = contract_class.deploy(@data_to_constructor).unwrap();
    address
}

#[test]
fn test_randomness_2() {
    // Accounts
    let attacker: ContractAddress = 'attacker'.try_into().unwrap();
    let treasury: ContractAddress = 'treasury'.try_into().unwrap();

    // Deployments
    let (eth_address, eth_dispatcher) = helpers::deploy_eth();
    let pragma_vrf = deploy_pragma_mock(eth_address);
    let (lottery, lottery_dispatcher) = deploy_lottery(pragma_vrf, eth_address, treasury);

    // Mint 1 ETH to the Attacker
    helpers::mint_erc20(eth_address, attacker, helpers::one_ether());

    // 10 Users buy tickets
    let mut i: u256 = 1;
    loop {
        // Condition to break the loop
        if i == 11 {
            break;
        }

        // Create a user and mint 1 ETH
        let felt_of_i: felt252 = i.try_into().unwrap();
        let mut user: ContractAddress = felt_of_i.try_into().unwrap();
        println!("User: {}", felt_of_i);
        helpers::mint_erc20(eth_address, user, helpers::one_ether());

        // The user buys a ticket
        start_cheat_caller_address(eth_address, user);
        eth_dispatcher.approve(lottery, helpers::one_ether());
        stop_cheat_caller_address(eth_address);
        start_cheat_caller_address(lottery, user);
        lottery_dispatcher.buy_ticket();
        stop_cheat_caller_address(lottery);

        i += 1;
    }

    // Attack Start //
    // TODO: Win the lottery and obtain all ETH

    // Attack End //

    // Attacker should win the lottery and obtain all ETH (>= 9 because some ETH is consumed for VRF
    // request)
    let winner: felt252 = lottery_dispatcher.get_last_winner().try_into().unwrap();
    println!("Winner: {}", winner);
    assert(eth_dispatcher.balance_of(attacker) >= helpers::one_ether() * 9, 'Not all ETH');
}
