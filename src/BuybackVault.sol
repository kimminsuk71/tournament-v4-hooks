// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {IBuybackExecutor} from "./interfaces/IBuybackExecutor.sol";
import {HubToken} from "./HubToken.sol";

contract BuybackVault is Ownable {
    using SafeERC20 for IERC20;

    error InvalidAddress();
    error InvalidAmount();
    error NothingReceived();

    event HookSet(address indexed hook);
    event TreasurySet(address indexed treasury);
    event FeeDeposited(address indexed feeToken, uint256 buybackAmount, uint256 treasuryAmount);
    event BuybackBurned(
        address indexed feeToken, address indexed executor, uint256 feeAmountIn, uint256 hubAmountBurned
    );

    address public immutable hubToken;
    address public hook;
    address public treasury;

    mapping(address feeToken => uint256 amount) public pendingBuyback;
    mapping(address feeToken => uint256 amount) public totalTreasuryRouted;
    uint256 public totalHubBurned;

    modifier onlyHook() {
        if (msg.sender != hook) revert InvalidAddress();
        _;
    }

    constructor(address hubToken_, address owner_, address treasury_) Ownable(owner_) {
        if (hubToken_ == address(0) || owner_ == address(0) || treasury_ == address(0)) revert InvalidAddress();
        hubToken = hubToken_;
        treasury = treasury_;
    }

    function setHook(address hook_) external onlyOwner {
        if (hook_ == address(0)) revert InvalidAddress();
        hook = hook_;
        emit HookSet(hook_);
    }

    function setTreasury(address treasury_) external onlyOwner {
        if (treasury_ == address(0)) revert InvalidAddress();
        treasury = treasury_;
        emit TreasurySet(treasury_);
    }

    function depositFee(address feeToken, uint256 buybackAmount, uint256 treasuryAmount) external onlyHook {
        if (feeToken == address(0)) revert InvalidAddress();

        if (buybackAmount != 0) {
            IERC20(feeToken).safeTransferFrom(msg.sender, address(this), buybackAmount);
            pendingBuyback[feeToken] += buybackAmount;
        }

        if (treasuryAmount != 0) {
            IERC20(feeToken).safeTransferFrom(msg.sender, treasury, treasuryAmount);
            totalTreasuryRouted[feeToken] += treasuryAmount;
        }

        emit FeeDeposited(feeToken, buybackAmount, treasuryAmount);
    }

    function executeBuybackAndBurn(address feeToken, address executor, uint256 amountIn, uint256 minHubAmountOut)
        external
        onlyOwner
        returns (uint256 hubAmountOut)
    {
        if (feeToken == address(0) || executor == address(0)) revert InvalidAddress();
        if (amountIn == 0 || amountIn > pendingBuyback[feeToken]) revert InvalidAmount();

        pendingBuyback[feeToken] -= amountIn;
        IERC20(feeToken).forceApprove(executor, amountIn);
        hubAmountOut = IBuybackExecutor(executor).executeBuyback(feeToken, amountIn, hubToken, address(this));
        IERC20(feeToken).forceApprove(executor, 0);

        if (hubAmountOut < minHubAmountOut || hubAmountOut == 0) revert NothingReceived();
        HubToken(hubToken).burn(hubAmountOut);
        totalHubBurned += hubAmountOut;

        emit BuybackBurned(feeToken, executor, amountIn, hubAmountOut);
    }
}
