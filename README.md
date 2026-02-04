# Whitepaper Smart Contracts

This repository contains a Solidity implementation derived from the provided
whitepaper, centered around a capped ERC20 token, vesting, and staking.

## Contracts

- `contracts/WhitepaperToken.sol`
  - `WhitepaperToken`: ERC20 with capped supply, pausable transfers, burn, and
    minter role.
  - `TokenVesting`: linear vesting with cliff and duration.
  - `StakingPool`: stake/withdraw/claim with owner-configured reward schedule.

## Build

Use your preferred Solidity toolchain (Foundry/Hardhat/Truffle). The contracts
target Solidity `^0.8.20`.

## Usage

High-level deployment flow:

1. Deploy `WhitepaperToken` with:
   - token name/symbol
   - max supply (cap)
   - initial recipients + amounts
   - owner address
2. (Optional) Deploy `TokenVesting` for team/advisor allocations, then transfer
   the vesting allocation to the vesting contract.
3. (Optional) Deploy `StakingPool` with the token address, fund it with rewards,
   then call `notifyRewardAmount`.

## Notes

Token name chosen: `All-In`.

Adjust constructor parameters and schedules to match the whitepaper’s exact
tokenomics and vesting timelines.
