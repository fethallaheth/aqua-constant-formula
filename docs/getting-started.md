# Getting Started with Aqua

## Introduction

1inch Aqua is shared liquidity layer for DeFi applications. It enables developers to build Aqua Apps and Strategies that access Maker liquidity on-demand without locking funds in contracts.

The protocol leverages token allowances rather than requiring token deposits in contract balances, maximizing capital efficiency for liquidity providers. This architecture fundamentally differs from traditional AMM designs that lock liquidity.

This guide demonstrates building with Aqua using the examples in [aqua-app-template](https://github.com/1inch/aqua-app-template.git) repository. You'll learn how to implement strategies that utilize shared liquidity and manage Maker token interactions through the protocol's core primitives.

## Aqua Strategy Lifecycle

The following sections detail an Aqua strategy lifecycle using XYCSwap, a constant product AMM implementation similar to Uniswap V2.

### Strategy Creation

Strategy creation begins with [`ship()`](https://github.com/1inch/aqua/blob/a19c99e308cdb9e7d3607e5754e879d293753542/src/Aqua.sol#L44), which registers the strategy on-chain:

* **App and Strategy Hash Registration:** Records the app address (strategy implementation) and `strategyHash` (encoded parameters defining the strategy configuration)
* **Aqua Balance Initialization:** Sets virtual token reserves for the strategy without transferring actual tokens

The `ship()` operation creates no token transfers or locks. Strategies can declare any reserve amounts, but swaps fail if the Maker lacks sufficient token balance at execution time.
### Strategy Execution
Takers interact with deployed strategies to execute token swaps:

* **Token Transfers:** Direct transfers occur between Maker and Taker wallets during swap execution
* **Reserve Updates:** Strategy reserves update via Aqua balances, managed through `pull()` and `push()` primitives

### Strategy Termination
Makers terminate strategies via `dock()`:

* **Balance Reset:** Zeroes the strategy's Aqua balances
* **Access Revocation:** Prevents further token access by the strategy


### The Unlocked Liquidity Paradigm
Aqua enables Makers to dynamically manage multiple strategies via continuous `ship()` and `dock()` operations in response to market conditions.

Maker funds remain unlocked—transfers occur only during swap execution. This architecture maximizes capital efficiency by allowing simultaneous strategy deployment without fund segregation.

### Installation
Standard Hardhat project setup:

```bash
git clone https://github.com/1inch/aqua-app-template.git
cd aqua-app-template
yarn install
yarn build
yarn test
```

### Test Examples
The test suite demonstrates a Uniswap V2-style constant product AMM implementation. Reference: [XYCSwap.test](https://github.com/1inch/aqua-app-template/blob/d290169caafbba71ae495c46ca8201a419918b94/test/XYCSwap.test.ts#L10).

#### Step 1: Deploy Core Contracts

Three essential contracts are deployed:

```typescript
// Deploy Aqua contract
const aqua = await deployContract('Aqua') as unknown as Aqua;

// Deploy XYCSwap contract
const xycSwap = await deployContract('XYCSwap', [await aqua.getAddress()]) as unknown as XYCSwap;

// Deploy SwapExecutor contract
const swapExecutor =
    await deployContract('SwapExecutor', [await aqua.getAddress()]) as unknown as SwapExecutor;
```

**Aqua Contract:** Core protocol contract providing `ship()`, `dock()`, `push()`, and `pull()` primitives. Deployed locally for testing; exists on all production EVM networks.

**XYCSwap Contract:** The strategy implementation application executing constant product (`x * y = k`) swaps. Critical distinction: reads reserves from Aqua balances rather than contract `balanceOf()`.

**SwapExecutor Contract:** Handles swap callbacks analogous to Uniswap V2's pattern. Replaces `transferFrom()` with `aqua.push()` to update Maker's Aqua balances during Taker token transfers.


#### Step 2: Creating and Shipping a Strategy
Strategy parameters encode into a unique `strategyHash` that identifies the strategy on-chain:

```javascript
    const strategy = {
        maker: await maker.getAddress(),
        token0: await token0.getAddress(),
        token1: await token1.getAddress(),
        feeBps: FEE_BPS,
        salt: ethers.ZeroHash
    };

    // Encode the strategy
    const encodedStrategy = ethers.AbiCoder.defaultAbiCoder().encode(
        ['tuple(address,address,address,uint256,bytes32)'],
        [[strategy.maker, strategy.token0, strategy.token1, strategy.feeBps, strategy.salt]]
    );
    const strategyHash = ethers.keccak256(encodedStrategy);
```

The `aqua.ship()` call registers the strategy with:

* App implementation address (XYCSwap contract)
* Hashed strategy configuration
* Token addresses and virtual reserve amounts

```javascript
    // Create dynamic arrays for tokens and amounts
    const tokens = [await token0.getAddress(), await token1.getAddress()];
    const amounts = [INITIAL_AMOUNT0, INITIAL_AMOUNT1];

    // Call aqua.ship() from maker account
    await aqua.connect(maker).ship(
        await app.getAddress(),
        encodedStrategy,
        tokens,
        amounts
    );
```

The `ship()` operation performs minimal on-chain state changes—no deployments or token transfers occur, only strategy parameter registration. This lightweight approach enables efficient liquidity reuse across multiple strategies without fund movement.

#### Step 3: Test #1 - Swap with Aqua Push
This test demonstrates swap execution using `aqua.push()` for Taker token transfers via callback mechanism:

```javascript
const swapExactInData = xycSwap.interface.encodeFunctionData('swapExactIn', [
    strategy,
    true, // zeroForOne
    true, // takerUseAquaPush
    amountIn,
    expectedAmountOut,
    await swapExecutor.getAddress(), // recipient
    emptyTakerData
]);

const tx = await swapExecutor.arbitraryCall(
    await xycSwap.getAddress(),
    swapExactInData
);
```

**Swap execution flow:**

1. `swapExactIn()` reads pool reserves from Maker's Aqua balances and calculates `amountOut`
2. `aqua.pull()` transfers output tokens from Maker to Taker, updating Aqua balances
3. SwapExecutor callback executes, taking input tokens from Taker
4. `aqua.push()` credits input tokens to Maker's Aqua balance

The critical insight: Aqua balance changes mirror actual token balance changes while maintaining reserve accounting. This enables composable strategies—liquidity can be reused, compounded, or incentivized through Aqua balance mechanics without touching underlying Maker funds.

#### Step 4: Test #2 - Swap with Direct Transfer
Simplified swap flow without callbacks:

```javascript
const tx = await xycSwap.connect(taker).swapExactIn(
  strategy,
  true, // zeroForOne
  false, // takerUseAquaPush = false for direct transfer
  amountIn,
  expectedAmountOut,
  await taker.getAddress(), // recipient
  emptyTakerData
);
```

Without `aqua.push()`, the pool executes standard token transfers. Maker reserves still derive from Aqua balances, maintaining the unlocked liquidity model.

#### Step 5: Test #3 - Dock Strategy
Strategy termination test: creates strategy, calls `dock()`, verifies Aqua balances are zeroed and strategy access is revoked.

## Conclusion

This guide demonstrates Aqua's core mechanics through a single strategy implementation. The template provides a foundation for complex scenarios where Makers deploy multiple strategies simultaneously.

The separation of app logic from strategy parameters enables "strategy packs"—collections of configurations sharing the same implementation. Market forces select optimal strategies while Makers maintain maximum capital efficiency with perpetually unlocked funds.

For advanced use cases, 1inch's SwapVM provides compact, serializable strategy construction using composable financial logic primitives. Future articles will cover SwapVM integration patterns.
