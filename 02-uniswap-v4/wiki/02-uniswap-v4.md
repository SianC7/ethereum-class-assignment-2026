# Uniswap v4

Uniswap v4 is the next iteration of Uniswap’s **AMM** protocol. It keeps the core idea of **swaps against pooled liquidity** and **concentrated liquidity** with a pricing function, but changes **how pools live on-chain** and **how extensions are built**.

## What You Should Understand

- **Concentrated Liquidity**
- **Liquidity Pools**
- **Non Fungible Liquidity**
- **Singleton and `PoolManager`**
- **Hooks**
- **Flash accounting**

### [Concentrated Liquidity](https://blog.uniswap.org/uniswap-v3#concentrated-liquidity)

In Uniswap v2, liquidity is distributed evenly along an `𝑥 ⋅ 𝑦 = 𝑘` price curve, with assets reserved for all prices between 0 and infinity. For most pools, a majority of this liquidity is never put to use. As an example, the v2 DAI/USDC pair reserves just ~0.50% of capital for trading between $0.99 and $1.01 , the price range in which LPs would expect to see the most volume and consequently earn the most fees.

V2 LPs only earn fees on a small portion of their capital, which can fail to appropriately compensate for the price risk, `impermanent loss`, they take by holding large inventories in both tokens. Additionally, traders are often subject to high degrees of `slippage` as liquidity is spread thin across all price ranges.

In Uniswap v3 and V4, LP's can concentrate their capital within custom price ranges, providing greater amounts of liquidity at desired prices. In doing so, LPs construct individualized price curves that reflect their own preferences. Here is an article on [concentrated liquidity](https://www.rareskills.io/post/uniswap-v3-concentrated-liquidity).

### Liquidity Pools

In Uniswap v4, a **liquidity pool** is the on-chain state for one uniquely identified market inside the singleton **`PoolManager`**. You do not deploy a separate pool contract per market in the same way as v2/v3; instead, the manager holds **per-pool** data (for example current price, active liquidity, and fee accounting) addressed by a **pool key**.

**What makes a v4 pool unique**

Every pool is distinguished by **four** fields that must all agree for two calls to target the **same** pool. Change any one field and you are interacting with a **different** pool (separate reserves and price).

| Dimension        | Role                                                                                                                                                                                                                                  |
| ---------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| **Token pair**   | The two assets, in the protocol’s canonical order (`currency0` & `currency1`, typically sorted by address). Same two tokens in the wrong order are not the same key as the canonical pair.                                            |
| **Fee**          | The swap fee tier for that pool (e.g. which fixed fee schedule applies). Different fee ⇒ different pool.                                                                                                                              |
| **Tick spacing** | Which **tick** grid the pool uses for prices and liquidity steps. Spacing is tied to how the pool steps through `sqrtPrice` and which ticks may hold liquidity; different spacing ⇒ different pool.                                   |
| **Hooks**        | The address of the optional **hooks** contract for that pool, or the **zero address** if there are no hooks. Same pair, fee, and tick spacing but a different hooks contract (including `no hooks` vs `some hooks`) ⇒ different pool. |

For a practical explanation of how **price relates to ticks**, see [Introducing ticks in Uniswap V3 (RareSkills)](https://rareskills.io/post/uniswap-v3-ticks).  
For a practical guide on converting a **price into an initializable tick**, see [How to convert a price to a tick that can be initialized (Uniswap Support)](https://support.uniswap.org/hc/en-us/articles/21068898875661-How-to-convert-a-price-to-a-tick-that-can-be-initialized).

Swaps, mints, burns, and donations all pass this **full key** so the `PoolManager` updates the correct pool. LP **positions** (concentrated ranges) are attached to that same pool identity; they are not a substitute for the key—two positions only share liquidity if they sit on the **same** pool key.

### [Non Fungible Liquidity](https://blog.uniswap.org/uniswap-v3#nonfungible-liquidity)

A **liquidity pool** is not a single blob of capital: it is the **sum of many separate liquidity positions** on the same pool key. Each **position** supplies active depth only between its own **`tickLower`** and **`tickUpper`**; at any on-chain price, the pool’s effective depth is the **aggregate** of all positions whose ranges **contain** the current tick. Different LPs (or the same LP) can stack narrow bands, wide bands, or multiple disjoint ranges on one pool.

As a byproduct of per-LP custom price curves, those positions are **not fungible** with each other and are **not** represented as a single shared ERC-20 pool share in the core protocol. Instead, each minted position is tracked as its own record—commonly surfaced to users as an **NFT** (a unique `tokenId`) or an equivalent **position id** from the position manager—so you can modify or burn **your** liquidity without touching someone else’s.

**What makes a liquidity position unique**

Two positions are the **same** on-chain position only if they share the **same** identity the protocol assigns. In practice, a **unique liquidity position** is defined by things like:

| Aspect | Role |
|--------|------|
| **Pool** | The full **pool key** (token pair, fee, tick spacing, hooks). Positions on different pools are always different positions. |
| **Price range** | **`tickLower`** and **`tickUpper`** bound where this position’s liquidity is active. Same pool but a different range ⇒ a different position (when minted as a new position). |
| **Position id** | The protocol’s **unique handle** for that mint—often an **NFT `tokenId`**. A new mint gets a new id; that id is what wallets and contracts use to **increase**, **decrease**, **collect fees**, or **burn** that specific slice of liquidity. |
| **Owner (custody)** | The address holding the position NFT controls that position; ownership can transfer without merging two positions into one. |

So: one **pool** ↔ many **positions**; one **position** ↔ one **range** (per mint) + one **position id** on one **pool**. Wrappers can bundle or fractionalize NFTs into fungible ERC-20 products, but the **core** idea remains: liquidity is **positioned** and **non-fungible** at the protocol level.

Additionally, trading fees are no longer automatically reinvested into the pool on LPs’ behalf; fee accounting is per position. Over time, strategies can combine multiple positions, rebalancing, fee reinvestment, and lending—often still represented to users as one portfolio built from **many** underlying positions.

### Singleton and `PoolManager`

Earlier versions deployed **one pool contract per pair** (and per fee tier in v3). In v4, many pools are managed by a **single** `PoolManager` (singleton) contract. That reduces deployment cost and enables a unified interface for swaps, liquidity changes, and donations across pools.

### Hooks (Not examined)

**Hooks** are optional contracts the pool creator can attach so the pool calls into them at specific lifecycle points (for example before/after swap, modify liquidity, etc.). They allow custom logic—fees, oracles, TWAMM-style behavior, limits—**without** forking the whole exchange, while the core still enforces swap and liquidity invariants.

### Flash accounting (Not examined)

v4 uses **flash accounting**: operations like swaps can **net** debits and credits inside a lock, then settle once at the end of the call. That reduces intermediate token transfers and gas compared to naive step-by-step transfers.

## Further Reading

- [Uniswap v4 overview](https://docs.uniswap.org/contracts/v4/overview)
- [Uniswap v4 whitepaper / technical deep dives](https://uniswap.org/) (see official blog and docs for the latest links)
- [Introducing ticks in Uniswap V3 (RareSkills)](https://rareskills.io/post/uniswap-v3-ticks)
- [How to convert a price to a tick that can be initialized (Uniswap Support)](https://support.uniswap.org/hc/en-us/articles/21068898875661-How-to-convert-a-price-to-a-tick-that-can-be-initialized)
