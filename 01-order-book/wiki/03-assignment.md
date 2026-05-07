# Assignment

This assignment has two parts. Complete Part 1 first, then use those tokens in Part 2.

## Overview

Today, many reward tokens are trapped inside a single store ecosystem, which limits how useful they are to holders. This assignment explores how a decentralized exchange-style order book can improve that by creating a market between reward tokens.

In this project, `PNPToken` (`PNPT`) represents Pick n Pay points and `FNBToken` (`FNBT`) represents eBucks. By building a token market, holders of Pick n Pay tokens can exchange into eBucks when market prices are favorable, instead of being forced to spend rewards in only one place.

## Part 1: Create 2 ERC20 Smart Contracts

Build two ERC20 token contracts that will be traded in your order book.

### Requirements

- [ ] **TODO:** Create two separate ERC20 tokens: `PNPToken` (`PNPT`) and `FNBToken` (`FNBT`).
- [ ] **TODO:** Ensure all Part 1 tests pass.
- [ ] **TODO:** Add comments for all functions and logic in functions.

### Deliverables

- Two smart contract files for the ERC20 tokens.

## Part 2: Create an Order Book for Trading ERC20 Tokens

Build a smart contract that allows users to place and match orders between `PNPToken` (`PNPT`) and `FNBToken` (`FNBT`).

### Requirements

- [ ] **TODO:** Support placing buy and sell orders.
- [ ] **TODO:** Implement order matching logic.
- [ ] **TODO:** Emit events for order creation, matching, fill updates, and cancellation.
- [ ] **TODO:** Ensure all Part 2 tests pass.
- [ ] **TODO:** Add comments for all functions and logic in functions.

### Deliverables

- Order book smart contract file(s).

## Running the Tests

After navigating to the `01-order-book` folder, run:

`yarn test test/AssignmentSolition.ts`

## Submission Checklist

- All contracts compile.
- All tests pass.
- Events are emitted for key actions.
- Methods include comments explaining purpose/behavior.
- Complex or non-obvious function logic includes brief explanatory comments.
- Code is organized and readable.
- Assignment requirements for both parts are fully covered.
