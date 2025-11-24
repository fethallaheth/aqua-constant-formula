// SPDX-License-Identifier: LicenseRef-Degensoft-Aqua-Source-1.1

import { loadFixture } from "@nomicfoundation/hardhat-network-helpers";
import { ethers } from 'hardhat';
import { expect, ether } from '@1inch/solidity-utils';
import "@nomicfoundation/hardhat-chai-matchers";

import { deployFixture, createXYCStrategy, calculateAmountOut } from "./utils";

describe("XYCSwap", function () {
  it("should swap token0 for token1 using aqua.push", async function () {
    const {
      contracts: { xycSwap, aqua, token0, token1, swapExecutor },
      addrs: { maker },
      constants: { INITIAL_AMOUNT0, INITIAL_AMOUNT1, FEE_BPS }
      } = await loadFixture(deployFixture);

    const { strategy, strategyHash } = await createXYCStrategy(xycSwap, aqua, maker, token0, token1);

    const amountIn = ether('10');
    const expectedAmountOut = calculateAmountOut(
      amountIn,
      INITIAL_AMOUNT0,
      INITIAL_AMOUNT1,
      FEE_BPS
    );

    const emptyTakerData = ethers.AbiCoder.defaultAbiCoder().encode(["bool"], [true]);

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

    await expect(tx).to.changeTokenBalances(token0, [swapExecutor, maker], [-amountIn, amountIn]);
    await expect(tx).to.changeTokenBalances(token1, [swapExecutor, maker], [expectedAmountOut, -expectedAmountOut]);

    const [newBalance0, ] = await aqua.rawBalances(await maker.getAddress(), await xycSwap.getAddress(), strategyHash, await token0.getAddress());
    const [newBalance1, ] = await aqua.rawBalances(await maker.getAddress(), await xycSwap.getAddress(), strategyHash, await token1.getAddress());

    expect(BigInt(newBalance0.toString())).to.equal(INITIAL_AMOUNT0 + amountIn);
    expect(BigInt(newBalance1.toString())).to.equal(INITIAL_AMOUNT1 - expectedAmountOut);
  });

  it("should swap token0 for token1 with direct transfer", async function () {
    const {
      contracts: { xycSwap, aqua, token0, token1 },
      addrs: { maker, taker },
      constants: { INITIAL_AMOUNT0, INITIAL_AMOUNT1, FEE_BPS }
    } = await loadFixture(deployFixture);

    const { strategy, strategyHash } = await createXYCStrategy(xycSwap, aqua, maker, token0, token1);

    const amountIn = ether('10');
    const expectedAmountOut = calculateAmountOut(
      amountIn,
      INITIAL_AMOUNT0,
      INITIAL_AMOUNT1,
      FEE_BPS
    );

    const emptyTakerData = ethers.AbiCoder.defaultAbiCoder().encode(["bool"], [true]);

    const tx = await xycSwap.connect(taker).swapExactIn(
      strategy,
      true, // zeroForOne
      false, // takerUseAquaPush = false for direct transfer
      amountIn,
      expectedAmountOut,
      await taker.getAddress(), // recipient
      emptyTakerData
    );

    await expect(tx).to.changeTokenBalances(token0, [taker, maker], [-amountIn, amountIn]);
    await expect(tx).to.changeTokenBalances(token1, [taker, maker], [expectedAmountOut, -expectedAmountOut]);

    const [ newBalance0, ] = await aqua.rawBalances(await maker.getAddress(), await xycSwap.getAddress(), strategyHash, await token0.getAddress());
    const [ newBalance1, ] = await aqua.rawBalances(await maker.getAddress(), await xycSwap.getAddress(), strategyHash, await token1.getAddress());

    expect(BigInt(newBalance0.toString())).to.equal(INITIAL_AMOUNT0);
    expect(BigInt(newBalance1.toString())).to.equal(INITIAL_AMOUNT1 - expectedAmountOut);
  });

  it("should prevent filling after dock is called", async function () {
    const {
      contracts: { xycSwap, aqua, token0, token1 },
      addrs: { maker, taker },
      constants: { INITIAL_AMOUNT0, INITIAL_AMOUNT1, FEE_BPS }
    } = await loadFixture(deployFixture);

    // Step 1: Create strategy
    const { strategy, strategyHash } = await createXYCStrategy(xycSwap, aqua, maker, token0, token1);

    // Step 2: Partially fill the strategy
    const firstSwapAmountIn = ether('5');
    const expectedFirstAmountOut = calculateAmountOut(
      firstSwapAmountIn,
      INITIAL_AMOUNT0,
      INITIAL_AMOUNT1,
      FEE_BPS
    );

    const emptyTakerData = ethers.AbiCoder.defaultAbiCoder().encode(["bool"], [true]);

    // Execute first swap (partial fill)
    await xycSwap.connect(taker).swapExactIn(
      strategy,
      true, // zeroForOne
      false, // takerUseAquaPush = false for direct transfer
      firstSwapAmountIn,
      expectedFirstAmountOut,
      await taker.getAddress(), // recipient
      emptyTakerData
    );

    // Verify balances after partial fill
    const [ balance0AfterSwap, ] = await aqua.rawBalances(await maker.getAddress(), await xycSwap.getAddress(), strategyHash, await token0.getAddress());
    const [ balance1AfterSwap, ] = await aqua.rawBalances(await maker.getAddress(), await xycSwap.getAddress(), strategyHash, await token1.getAddress());

    expect(BigInt(balance0AfterSwap.toString())).to.equal(INITIAL_AMOUNT0);
    expect(BigInt(balance1AfterSwap.toString())).to.equal(INITIAL_AMOUNT1 - expectedFirstAmountOut);

    // Step 3: Call dock
    const tokens = [await token0.getAddress(), await token1.getAddress()];
    await aqua.connect(maker).dock(await xycSwap.getAddress(), strategyHash, tokens);

    // Step 4: Try to fill again and expect it to fail
    const secondSwapAmountIn = ether('5');
    const expectedSecondAmountOut = calculateAmountOut(
      secondSwapAmountIn,
      INITIAL_AMOUNT0,
      INITIAL_AMOUNT1 - expectedFirstAmountOut,
      FEE_BPS
    );

    // This should fail because the strategy is docked
    await expect(
      xycSwap.connect(taker).swapExactIn(
        strategy,
        true, // zeroForOne
        false, // takerUseAquaPush = false for direct transfer
        secondSwapAmountIn,
        expectedSecondAmountOut,
        await taker.getAddress(), // recipient
        emptyTakerData
      )
    ).to.be.reverted; // The strategy should not allow further fills after being docked
  });
});
