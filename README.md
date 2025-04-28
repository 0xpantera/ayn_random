# AYN Random - Vulnerabilities in Randomness

This project demonstrates two common vulnerabilities in blockchain randomness implementations:

1. **Predictable On-Chain Randomness**: Using block data to generate "random" numbers that can be predicted
2. **Missing Access Control in VRF Callbacks**: Allowing anyone to call VRF callback functions with arbitrary data

## Project Structure

- `guess/`: Contains a simple guessing game with predictable randomness
- `lottery/`: Contains a lottery implementation using VRF with vulnerable callback
- `utils/`: Helper functions and mock contracts for testing

## Vulnerability 1: Predictable On-Chain Randomness

In `SimpleGame.cairo`, the contract uses block data (number and timestamp) as the seed for generating a random number:

```cairo
let random_number: u256 = core::pedersen::pedersen(
    block_number_felt, block_timestamp_felt,
).into();
```

### The Problem

Miners/validators can see or influence block data, making this randomness predictable. In Starknet, users can know the block data in advance by tracking and analyzing the sequencer's behavior.

### The Attack

In `test_game_attack.cairo`, the attacker predicts the random number by using the exact same formula as the contract:

```cairo
let block_num = 1_000;
let block_ts = 1_000;
let guess = core::pedersen::pedersen(block_num, block_ts);
game_dispatcher.play(guess.into());
```

## Vulnerability 2: Missing Access Control in VRF Callbacks

In `lottery.cairo`, the `receive_random_words` function lacks proper access control:

```cairo
fn receive_random_words(
    ref self: ContractState,
    requestor_address: ContractAddress,
    request_id: u64,
    random_words: Span<felt252>,
    calldata: Array<felt252>,
) {
    // @audit-issue Missing access control. Only the VRF contract should be able to call
    // this function
```

### The Problem

Any user can call the callback function directly with arbitrary random words, bypassing the genuine VRF service.

### The Attack

In `test_lottery_attack.cairo`, the attacker calls the callback directly with a chosen random number:

```cairo
let rands: Array<felt252> = array![10];
lottery_dispatcher.receive_random_words(lottery, 0, rands.span(), calldata);
```

This allows the attacker to manipulate the lottery outcome.

## Best Practices for Randomness

1. **Off-chain VRF Services**: Use a trusted VRF service like Pragma or Empiric
2. **Access Control**: Ensure VRF callbacks can only be called by the authorized VRF contract
3. **Commitment Scheme**: Use a commit-reveal pattern when applicable
4. **Multiple Sources**: Combine multiple sources of randomness
5. **Time Delay**: Add time delay between random seed generation and its usage

## Running the Tests

The tests demonstrate both vulnerabilities:

```bash
scarb test
```

Both attacks will succeed, showing that the attacker can:
1. Correctly guess the random number in the guessing game
2. Force a win in the lottery by directly calling the callback function
