// SPDX-License-Identifier: LicenseRef-Degensoft-Aqua-Source-1.1

import { ether, deployContract } from '@1inch/solidity-utils';
import { ethers } from 'hardhat';
import { Signer } from 'ethers';

// Import generated types for all contracts
import { TokenMock } from '../typechain-types/@1inch/solidity-utils/contracts/mocks/TokenMock';
import { Aqua } from '../typechain-types/@1inch/aqua/src/Aqua';
import { XYCSwap } from '../typechain-types/contracts/XYCSwap';
import { SwapExecutor } from '../typechain-types/contracts/SwapExecutor';

  // Define initial amounts
  const INITIAL_AMOUNT0 = ether('100');
  const INITIAL_AMOUNT1 = ether('200');
  const FEE_BPS = 30n; // 0.3% fee

async function deployFixture() {
    const [owner, maker, taker]: Signer[] = await ethers.getSigners();

    // Deploy Aqua contract
    const aqua = await deployContract('Aqua') as unknown as Aqua;

    // Deploy XYCSwap contract
    const xycSwap = await deployContract('XYCSwap', [await aqua.getAddress()]) as unknown as XYCSwap;

    // Deploy SwapExecutor contract
    const swapExecutor = await deployContract('SwapExecutor', [await aqua.getAddress()]) as unknown as SwapExecutor;

    // Deploy TokenMock from @1inch/solidity-utils
    const token0 = await deployContract('TokenMock', ['Token0', 'TK0']) as unknown as TokenMock;
    const token1 = await deployContract('TokenMock', ['Token1', 'TK1']) as unknown as TokenMock;

    // Mint tokens to maker
    await token0.mint(await maker.getAddress(), INITIAL_AMOUNT0);
    await token1.mint(await maker.getAddress(), INITIAL_AMOUNT1);

    // Setup approvals from maker to aqua
    await token0.connect(maker).approve(await aqua.getAddress(), ethers.MaxUint256);
    await token1.connect(maker).approve(await aqua.getAddress(), ethers.MaxUint256);

    // Mint tokens to takers for swapping
    await token0.mint(await swapExecutor.getAddress(), ethers.parseEther('100'));
    await token0.mint(await taker.getAddress(), ether('100'));

    // Setup approval from taker to swap
    await token0.connect(taker).approve(await xycSwap.getAddress(), ethers.MaxUint256);

    return {
        contracts: { xycSwap, aqua, token0, token1, swapExecutor },
        addrs: { owner, maker, taker },
        constants: { INITIAL_AMOUNT0, INITIAL_AMOUNT1, FEE_BPS }
    };
}

async function createXYCStrategy(
    app: XYCSwap,
    aqua: Aqua,
    maker: Signer,
    token0: TokenMock,
    token1: TokenMock
) {
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

    return { strategy, strategyHash };
}

// Helper function to calculate expected output amount (constant product formula with fee)
function calculateAmountOut(amountIn: bigint, balanceIn: bigint, balanceOut: bigint, feeBps: bigint) {
    const BPS_BASE = 10000n;
    const amountInWithFee = amountIn * (BPS_BASE - feeBps) / BPS_BASE;
    return amountInWithFee * balanceOut / (balanceIn + amountInWithFee);
}

export { deployFixture, createXYCStrategy, calculateAmountOut };
