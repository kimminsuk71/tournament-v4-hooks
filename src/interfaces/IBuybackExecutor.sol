// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

interface IBuybackExecutor {
    function executeBuyback(address feeToken, uint256 amountIn, address hubToken, address recipient)
        external
        returns (uint256 hubAmountOut);
}
