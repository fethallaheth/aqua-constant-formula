// SPDX-License-Identifier: LicenseRef-Degensoft-Aqua-Source-1.1
pragma solidity 0.8.30;

import { Math } from "@openzeppelin/contracts/utils/math/Math.sol";
import { SafeERC20, IERC20 } from "@1inch/solidity-utils/contracts/libraries/SafeERC20.sol";
import { AquaApp } from "@1inch/aqua/src/AquaApp.sol";
import { IAqua } from "@1inch/aqua/src/interfaces/IAqua.sol";
import { IXYCSwapCallback } from "@1inch/aqua/examples/apps/interfaces/IXYCSwapCallback.sol";

/// @title StableSwapApp
/// @notice Curve-style StableSwap implementation for Aqua Protocol with proper fixed-point arithmetic
/// @dev Implements the StableSwap invariant: An^n * sum(x_i) + D = ADn^n + D^(n+1)/(n^n * prod(x_i))
contract StableSwapApp is AquaApp {
    using Math for uint256;
    using SafeERC20 for IERC20;

    error InsufficientLiquidity();
    error InsufficientOutputAmount(uint256 amountOut, uint256 amountOutMin);
    error ExcessiveInputAmount(uint256 amountIn, uint256 amountInMax);
    error InvalidAmplificationCoefficient();
    error ConvergenceFailure();

    struct Strategy {
        address maker;      // LP address (must be unique per strategy)
        address token0;     // First token
        address token1;     // Second token
        uint256 feeBps;     // Trading fee in basis points (e.g., 4 = 0.04%)
        uint256 A;          // Amplification coefficient (scaled by A_PRECISION)
        bytes32 salt;       // Uniqueness salt
    }

    // Constants - all public for transparency
    uint256 public constant FEE_DENOMINATOR = 10_000;
    uint256 public constant A_PRECISION = 100;      // A is stored as A * 100
    uint256 public constant PRECISION = 1e18;       // Fixed-point precision
    uint256 public constant MAX_ITERATIONS = 32;    // Reduced for gas efficiency
    uint256 public constant MIN_RESERVE = 1e6;      // Minimum reserve to prevent extreme imbalance
    
    constructor(IAqua aqua_) AquaApp(aqua_) {}

    // ============ PUBLIC VIEW FUNCTIONS ============

    /// @notice Calculate output amount for exact input swap
    function quoteExactIn(
        Strategy calldata strategy,
        bool zeroForOne,
        uint256 amountIn
    ) external view returns (uint256 amountOut) {
        bytes32 strategyHash = keccak256(abi.encode(strategy));
        (,, uint256 balanceIn, uint256 balanceOut) = 
            _getStrategyData(strategy, strategyHash, zeroForOne);
        
        return _quoteExactIn(strategy, balanceIn, balanceOut, amountIn);
    }

    /// @notice Calculate input amount for exact output swap
    function quoteExactOut(
        Strategy calldata strategy,
        bool zeroForOne,
        uint256 amountOut
    ) external view returns (uint256 amountIn) {
        bytes32 strategyHash = keccak256(abi.encode(strategy));
        (,, uint256 balanceIn, uint256 balanceOut) = 
            _getStrategyData(strategy, strategyHash, zeroForOne);
        
        return _quoteExactOut(strategy, balanceIn, balanceOut, amountOut);
    }

    // ============ SWAP EXECUTION ============

    /// @notice Swap exact input amount for minimum output
    function swapExactIn(
        Strategy calldata strategy,
        bool zeroForOne,
        bool takerUseAquaPush,
        uint256 amountIn,
        uint256 amountOutMin,
        address to,
        bytes calldata takerData
    )
        external
        nonReentrantStrategy(keccak256(abi.encode(strategy)))
        returns (uint256 amountOut)
    {
        bytes32 strategyHash = keccak256(abi.encode(strategy));
        
        (address tokenIn, address tokenOut, uint256 balanceIn, uint256 balanceOut) = 
            _getStrategyData(strategy, strategyHash, zeroForOne);
        
        // Calculate output using StableSwap curve
        amountOut = _quoteExactIn(strategy, balanceIn, balanceOut, amountIn);
        require(amountOut >= amountOutMin, InsufficientOutputAmount(amountOut, amountOutMin));

        // Pull output tokens to recipient
        AQUA.pull(strategy.maker, strategyHash, tokenOut, amountOut, to);
        
        if(takerUseAquaPush) {
        // Callback for taker to push input tokens
        IXYCSwapCallback(msg.sender).xycSwapCallback(
            tokenIn, 
            tokenOut, 
            amountIn, 
            amountOut,
            strategy.maker, 
            address(this), 
            strategyHash, 
            takerData
        );
        // Verify input tokens were pushed
        _safeCheckAquaPush(strategy.maker, strategyHash, tokenIn, balanceIn + amountIn);
        } else {
            IERC20(tokenIn).transferFrom(msg.sender, strategy.maker, amountIn);
        }
    }

    /// @notice Swap maximum input for exact output amount
    function swapExactOut(
        Strategy calldata strategy,
        bool zeroForOne,
        bool takerUseAquaPush,
        uint256 amountOut,
        uint256 amountInMax,
        address to,
        bytes calldata takerData
    )
        external
        nonReentrantStrategy(keccak256(abi.encode(strategy)))
        returns (uint256 amountIn)
    {
        bytes32 strategyHash = keccak256(abi.encode(strategy));
        
        (address tokenIn, address tokenOut, uint256 balanceIn, uint256 balanceOut) = 
            _getStrategyData(strategy, strategyHash, zeroForOne);
        
        // Calculate required input using StableSwap curve
        amountIn = _quoteExactOut(strategy, balanceIn, balanceOut, amountOut);
        require(amountIn <= amountInMax, ExcessiveInputAmount(amountIn, amountInMax));

        // Pull exact output tokens to recipient
        AQUA.pull(strategy.maker, strategyHash, tokenOut, amountOut, to);
        if(takerUseAquaPush){
        // Callback for taker to push required input tokens
        IXYCSwapCallback(msg.sender).xycSwapCallback(
            tokenIn, 
            tokenOut, 
            amountIn, 
            amountOut,
            strategy.maker, 
            address(this), 
            strategyHash, 
            takerData
        );
        
        // Verify input tokens were pushed
        _safeCheckAquaPush(strategy.maker, strategyHash, tokenIn, balanceIn + amountIn);
        } else {
            IERC20(tokenIn).safeTransferFrom(msg.sender, strategy.maker, amountIn);
        }
    }

    // ============ INTERNAL VIEW FUNCTIONS ============

    /// @notice Get strategy tokens and balances
    function _getStrategyData(
        Strategy calldata strategy,
        bytes32 strategyHash,
        bool zeroForOne
    )
        private
        view
        returns (
            address tokenIn,
            address tokenOut,
            uint256 balanceIn,
            uint256 balanceOut
        )
    {
        tokenIn = zeroForOne ? strategy.token0 : strategy.token1;
        tokenOut = zeroForOne ? strategy.token1 : strategy.token0;

        (balanceIn, balanceOut) = AQUA.safeBalances(
            strategy.maker,
            address(this),
            strategyHash,
            tokenIn,
            tokenOut
        );

        // Enforce minimum reserves to prevent extreme imbalance
        require(
            balanceIn >= MIN_RESERVE && balanceOut >= MIN_RESERVE,
            InsufficientLiquidity()
        );
    }

    /// @notice Calculate output for exact input using StableSwap invariant
    function _quoteExactIn(
        Strategy calldata strategy,
        uint256 balanceIn,
        uint256 balanceOut,
        uint256 amountIn
    )
        internal
        pure
        returns (uint256 amountOut)
    {
        require(strategy.A > 0 && strategy.A <= 100000, InvalidAmplificationCoefficient());
        
        // Apply trading fee
        uint256 feeAmount = amountIn.mulDiv(strategy.feeBps, FEE_DENOMINATOR);
        uint256 amountInAfterFee = amountIn - feeAmount;
        
        // Scale balances to PRECISION for fixed-point math
        uint256 xp0 = balanceIn * PRECISION;
        uint256 xp1 = balanceOut * PRECISION;
        
        // Calculate new input balance (scaled)
        uint256 newXp0 = xp0 + (amountInAfterFee * PRECISION);
        
        // Get invariant D with current scaled balances
        uint256 D = _getD(xp0, xp1, strategy.A);
        
        // Calculate new output balance that maintains D
        uint256 newXp1 = _getY(newXp0, xp1, D, strategy.A);
        
        // Calculate output (descale)
        uint256 dy = (xp1 - newXp1) / PRECISION;
        
        // Ensure output doesn't exceed available balance
        amountOut = dy > balanceOut ? balanceOut : dy;
    }

    /// @notice Calculate input for exact output using StableSwap invariant
    function _quoteExactOut(
        Strategy calldata strategy,
        uint256 balanceIn,
        uint256 balanceOut,
        uint256 amountOut
    )
        internal
        pure
        returns (uint256 amountIn)
    {
        require(strategy.A > 0 && strategy.A <= 100000, InvalidAmplificationCoefficient());
        require(amountOut < balanceOut, InsufficientLiquidity());
        
        // Scale balances to PRECISION for fixed-point math
        uint256 xp0 = balanceIn * PRECISION;
        uint256 xp1 = balanceOut * PRECISION;
        
        // Calculate new output balance (scaled)
        uint256 newXp1 = xp1 - (amountOut * PRECISION);
        
        // Get invariant D with current scaled balances
        uint256 D = _getD(xp0, xp1, strategy.A);
        
        // Calculate new input balance that maintains D
        uint256 newXp0 = _getY(newXp1, xp0, D, strategy.A);
        
        // Calculate gross input required (descale)
        uint256 dx = (newXp0 - xp0) / PRECISION;
        
        // Calculate input including fees with rounding up
        // amountIn = dx * FEE_DENOMINATOR / (FEE_DENOMINATOR - feeBps)
        uint256 grossAmountIn = dx;
        amountIn = grossAmountIn.mulDiv(
            FEE_DENOMINATOR,
            FEE_DENOMINATOR - strategy.feeBps,
            Math.Rounding.Ceil  // Round up to protect maker
        );
        
        // Safety check: ensure fee calculation covers the gross amount
        uint256 amountInAfterFee = amountIn - amountIn.mulDiv(strategy.feeBps, FEE_DENOMINATOR);
        if (amountInAfterFee < grossAmountIn) {
            amountIn += 1; // Add 1 wei safety margin
        }
        
        require(amountIn > 0, InsufficientLiquidity());
    }

    // ============ STABLESWAP MATH WITH FIXED-POINT ARITHMETIC ============

    /// @notice Calculate the StableSwap invariant D
    /// @dev Solves: An^n * sum(x_i) + D = ADn^n + D^(n+1)/(n^n * prod(x_i))
    /// @dev For n=2: 4A(x+y) + D = 4AD + D^3/(4xy)
    /// @param xp0 First balance (scaled by PRECISION)
    /// @param xp1 Second balance (scaled by PRECISION)
    /// @param A Amplification coefficient (scaled by A_PRECISION)
    function _getD(
        uint256 xp0,
        uint256 xp1,
        uint256 A
    )
        internal
        pure
        returns (uint256 D)
    {
        uint256 sum = xp0 + xp1;
        if (sum == 0) return 0;
        
        // Scale A properly: Ann = 4A * PRECISION / A_PRECISION
        // For n=2: Ann = 4A
        uint256 Ann = (A * 4 * PRECISION) / A_PRECISION;
        
        // Initial guess: D = sum
        D = sum;
        
        // Newton's method iteration
        for (uint256 i = 0; i < MAX_ITERATIONS; i++) {
            // D_P = D^3 / (4 * xp0 * xp1) with overflow protection
            // Break into steps to prevent overflow
            uint256 D_P = D;
            D_P = (D_P * D) / (xp0 * 4);
            D_P = (D_P * D) / xp1;
            
            uint256 D_prev = D;
            
            // D = (Ann * sum / PRECISION + 2 * D_P) * D / ((Ann / PRECISION - PRECISION) * D / PRECISION + 3 * D_P)
            // Simplified: D = (Ann * sum + 2 * D_P * PRECISION) * D / ((Ann - PRECISION) * D + 3 * D_P * PRECISION)
            uint256 numerator = D;
            numerator = numerator * (Ann * sum / PRECISION + 2 * D_P);
            
            uint256 denominator = D;
            denominator = denominator * (Ann / PRECISION - 1) + 3 * D_P;
            
            D = numerator / denominator;
            
            // Check convergence (scaled tolerance)
            if (_withinTolerance(D, D_prev, PRECISION)) {
                return D;
            }
        }
        
        revert ConvergenceFailure();
    }

    /// @notice Calculate y given x and invariant D
    /// @dev Solves for y in: An^n * sum(x_i) + D = ADn^n + D^(n+1)/(n^n * prod(x_i))
    /// @dev For n=2 with known x: y^2 + by = c where b = x + D/(4A), c = D^3/(4Ax)
    /// @param x Known balance (scaled by PRECISION)
    /// @param xOther Other balance hint for convergence (scaled by PRECISION)
    /// @param D Invariant (scaled by PRECISION)
    /// @param A Amplification coefficient (scaled by A_PRECISION)
    function _getY(
        uint256 x,
        uint256 xOther,
        uint256 D,
        uint256 A
    )
        internal
        pure
        returns (uint256 y)
    {
        // x should be less than or equal to D for math to be valid
        require(x <= D, InsufficientLiquidity());
        
        // Scale A properly
        uint256 Ann = (A * 4 * PRECISION) / A_PRECISION;
        
        // c = D^3 / (4 * Ann * x) with overflow protection
        uint256 c = D;
        c = (c * D) / (Ann * 4);
        c = (c * D) / x;
        
        // b = x + D * PRECISION / Ann
        uint256 b = x + (D * PRECISION) / Ann;
        
        // Initial guess: y = xOther (use other balance as starting point)
        y = xOther;
        
        // Newton's method: y = (y^2 + c) / (2y + b - D)
        for (uint256 i = 0; i < MAX_ITERATIONS; i++) {
            uint256 y_prev = y;
            
            // y = (y^2 + c) / (2y + b - D)
            uint256 numerator = (y * y) + c;
            uint256 denominator = (2 * y) + b - D;
            
            // Prevent division by zero
            require(denominator > 0, ConvergenceFailure());
            
            y = numerator / denominator;
            
            // Check convergence (scaled tolerance)
            if (_withinTolerance(y, y_prev, PRECISION)) {
                return y;
            }
        }
        
        revert ConvergenceFailure();
    }

    /// @notice Check if two values are within convergence threshold
    /// @param a First value
    /// @param b Second value
    /// @param precision Scale factor for tolerance (allows 1 unit at scale)
    function _withinTolerance(
        uint256 a,
        uint256 b,
        uint256 precision
    ) 
        internal 
        pure 
        returns (bool) 
    {
        uint256 diff = a > b ? a - b : b - a;
        // Allow 1 unit difference at the given precision scale
        // @note 10e18 is too much diff ? 
        return diff <= precision;
    }
}
