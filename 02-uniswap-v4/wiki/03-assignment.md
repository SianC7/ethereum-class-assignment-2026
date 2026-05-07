# Assignment

This assignment builds on [Automated Market Makers](./01-automated-market-makers.md) and [Uniswap v4](./02-uniswap-v4.md). Complete the wiki reading first, then work in the `02-uniswap-v4` monorepo so contracts compile and tests pass.

## Overview

This assignment highlights the AMM model as an alternative to the order-book model from the previous assignment. In an order book, price is discovered externally by matching buy and sell orders from traders. In an AMM, price is discovered internally from pool state (reserves/liquidity curve) and updates automatically as swaps and liquidity changes happen.

For reward tokens, this gives a different market design: instead of waiting for counterparties to place matching orders, holders trade directly against pooled liquidity. The goal is to understand how `FNBT` and `PNPT` can be priced and exchanged through the pool mechanism itself.

## Part 1: Install Uniswap v4 Core package

Follow the official guide: [Uniswap v4 Core](https://github.com/Uniswap/v4-core).

### Requirements

- [ ] **TODO:** Add the v4 core dependency to the appropriate workspace package.
- [ ] **TODO:** Install the package using **Yarn**:

```bash
yarn add @uniswap/v4-core
```

### Deliverables

- Updated `package.json` / lockfile showing `@uniswap/v4-core` installed via Yarn.

---

## Part 2: Pool creation with `PoolManager`

Implement a **smart contract** (in `02-uniswap-v4/packages/hardhat/contracts/`) that **creates a Uniswap v4 liquidity pool** using the protocol’s **`PoolManager`**.

**Pool parameters (required for this assignment)**

| Parameter        | Value                                                                                                                                                                                                                |
| ---------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| **Fee tier**     | **0.3%** — use the Uniswap fee encoding your stack expects (commonly **`3000`** in fee units where `3000` denotes a 0.30% swap fee).                                                                                 |
| **Tick spacing** | **`60`** — use tick spacing **60**, which pairs with the usual 0.3% configuration in Uniswap v3-style fee/spacing tables; match your v4 deployment’s allowed `fee` ↔ `tickSpacing` pairs if the chain enforces them. |

Use **`address(0)`** for **hooks**, so the pool key matches a no-hooks pool.

### Requirements

- [ ] **TODO:** Use **`FNBToken`** (`FNBT`) and **`PNPToken`** (`PNPT`) from the [`01-order-book`](../../01-order-book/) assignment as the two pool assets (deploy them in tests or reuse addresses as specified).
- [ ] **Hint:** In your pool-creation contract, pass the required addresses into the **constructor** (at minimum: `PoolManager`, `PNPToken`, and `FNBToken`) and store them for later pool initialization/mint calls.
- [ ] **TODO:** Initialize or register the pool through the v4 **`PoolManager`** flow with **fee tier 0.3%** (e.g. `3000` where applicable), **tick spacing `60`**, canonical **currency ordering**, and **hooks** as above.
- [ ] **TODO:** Emit a dedicated **`event`** when a pool is successfully created or initialized (name it clearly, e.g. `PoolCreated` / `V4PoolInitialized`), including the fields needed to identify the pool (tokens, fee, tick spacing, hooks address, and any `PoolId` / key material your design uses).
- [ ] **Hint:** Method modifiers (for example access-control modifiers like `onlyOwner`) can be used where appropriate; include comments explaining **why** a modifier was used on a method.
- [ ] **TODO:** Add comments for public/external methods and for non-obvious logic inside functions.

### Deliverables

- Solidity source for the pool-creation contract (and deployment or test setup that exercises it).
- Tests or scripts that assert the **pool-creation** event fires with the expected parameters.

---

## Part 3: Mint a liquidity position (same contract as Part 2)

Extend **the same contract** from Part 2 so it also **mints a concentrated liquidity position** in that pool (add liquidity within a chosen tick range).

### Economic assumptions (for tick math)

Use these **notional ZAR values** when choosing prices and ticks:

- **`FNBToken` (`FNBT`)** represents **eBucks**. The eBucks programme describes rewards as **pegged to the rand**, with a published transparent example that **eB10 is worth R1** (see [eBucks press release — How rich is your reward?](https://www.ebucks.com/web/eBucks/aboutus/pressreleases/2009/0409howrich.jsp)). For this assignment, treat **1 `FNBT` = R0.10** in notional terms (i.e. **10 `FNBT` ≡ R1**), aligned with that **eB10 = R1** line in the article.
- **`PNPToken` (`PNPT`)** represents **Pick n Pay Smart Shopper**–style points with **1 `PNPT` = R0.01** in notional terms.

From those assumptions, the **ZAR-equivalent spot notion** is **1 `FNBT` ≡ 10 `PNPT`** (R0.10 vs R0.01 per unit). Your pool may order tokens as `currency0` / `currency1`; convert that ratio into the correct **Uniswap sqrt price / tick** for your pair orientation.

### Requirements

- [ ] **TODO:** In the **same contract** as Part 2, implement a function (or internal flow) that **mints** a v4 **liquidity position** with non-zero liquidity in the pool you created.
- [ ] **TODO:** Emit a dedicated **`event`** when liquidity is minted (name it clearly, e.g. `LiquidityMinted`), including the pool identity, **tick bounds**, **liquidity** amount, and (if applicable) **position id** / owner so a listener can reconstruct what was added.
- [ ] **TODO:** Mint liquidity on the **same pool** as Part 2 (**0.3%** fee, tick spacing **`60`**). Choose **`tickLower`** and **`tickUpper`** (multiples of **`60`**) so the range **includes the tick** implied by the **R0.10-notional `FNBT` vs R0.01-notional `PNPT`** relationship above (i.e. the range must **cover** that relative price, with sensible margin).
- [ ] **TODO:** Document in comments which token you treated as `currency0` / `currency1` and how you mapped ZAR notionals to `sqrtPriceX96` / ticks.
- [ ] **TODO:** Ensure all Part 2 and Part 3 tests pass.
- [ ] **Note:** For any figure that comes from a calculation (for example price ratios, ticks, `sqrtPriceX96`, liquidity amounts, bounds), include a short code/comment note that shows the calculation used.

### Deliverables

- Updated Solidity from Part 2 with minting logic and tests proving pool creation + position mint.
- Tests that assert the **liquidity minting** event fires with the expected parameters.

---

## Running the tests

From the `02-uniswap-v4` folder:

```bash
yarn hardhat:test test/YourTestFile.ts
```

Or from `02-uniswap-v4/packages/hardhat`:

```bash
yarn test test/YourTestFile.ts
```

## Submission checklist

- Pool uses **0.3%** fee tier and tick spacing **`60`** (and ticks aligned to that spacing).
- Part 2 and Part 3 contracts emit **events for pool creation** and **liquidity minting**, and tests (or documented traces) cover them.
- All contracts compile.
- All tests pass.
- Methods include comments explaining purpose and behavior.
- Complex or non-obvious function logic includes brief explanatory comments.
- Any calculated figures include comments showing the calculation used.
- **Hooks and flash accounting** remain out of scope (see [Uniswap v4 wiki](./02-uniswap-v4.md)).
- Assignment requirements for Parts 1–3 are fully covered.
