// SPDX-License-Identifier: LicenseRef-Degensoft-Aqua-Source-1.1
pragma solidity 0.8.30;

/// @custom:license-url https://github.com/1inch/aqua-app-template/blob/main/LICENSES/Aqua-Source-1.1.txt
/// @custom:copyright © 2025 Degensoft Ltd

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import { IAqua } from "@1inch/aqua/src/interfaces/IAqua.sol";
import { IXYCSwapCallback } from "@1inch/aqua/examples/apps/interfaces/IXYCSwapCallback.sol";
import { RevertReasonForwarder } from "@1inch/solidity-utils/contracts/libraries/RevertReasonForwarder.sol";

contract SwapExecutor is IXYCSwapCallback {

    IAqua public immutable aqua;
    constructor(IAqua aqua_)  { aqua = aqua_; }

    function arbitraryCall(address target, bytes calldata arguments) external {
        (bool success,) = target.call(arguments);
        if (!success) RevertReasonForwarder.reRevert();
    }

    function xycSwapCallback(address tokenIn, address /* tokenOut */, uint256 amountIn, uint256 /* amountOut */, address maker, address implementation, bytes32 strategyHash, bytes calldata /* takerData */) external override {
        IERC20(tokenIn).approve(address(aqua), amountIn);
        aqua.push(maker, implementation, strategyHash, tokenIn, amountIn);
    }
}
