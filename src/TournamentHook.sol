// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IHooks} from "v4-core/interfaces/IHooks.sol";
import {IPoolManager} from "v4-core/interfaces/IPoolManager.sol";
import {PoolKey} from "v4-core/types/PoolKey.sol";
import {PoolId, PoolIdLibrary} from "v4-core/types/PoolId.sol";
import {ModifyLiquidityParams, SwapParams} from "v4-core/types/PoolOperation.sol";
import {BalanceDelta} from "v4-core/types/BalanceDelta.sol";
import {BeforeSwapDelta, BeforeSwapDeltaLibrary} from "v4-core/types/BeforeSwapDelta.sol";
import {Currency} from "v4-core/types/Currency.sol";
import {Hooks} from "v4-core/libraries/Hooks.sol";
import {SafeCast} from "v4-core/libraries/SafeCast.sol";
import {BuybackVault} from "./BuybackVault.sol";

contract TournamentHook is IHooks {
    using PoolIdLibrary for PoolKey;
    using SafeCast for uint256;
    using SafeCast for int128;
    using SafeERC20 for IERC20;

    error OnlyPoolManager();
    error OnlyOwner();
    error InvalidBips();
    error InvalidAddress();
    error PoolNotRegistered(PoolId poolId);
    error NativeCurrencyUnsupported();
    error HookMismatch();
    error ExactOutputUnsupported();
    error CurrenciesOutOfOrder();
    error InvalidSwapDelta();

    event PoolRegistered(PoolId indexed poolId, address indexed teamToken, address indexed quoteToken);
    event PoolRegistrationRemoved(PoolId indexed poolId);
    event SwapFeeRouted(
        PoolId indexed poolId,
        address indexed feeToken,
        uint256 feeAmount,
        uint256 buybackAmount,
        uint256 treasuryAmount
    );
    event FeeBipsSet(uint16 feeBips);

    IPoolManager public immutable manager;
    BuybackVault public immutable vault;
    address public owner;
    uint16 public feeBips;

    mapping(PoolId poolId => bool registered) public isRegisteredPool;

    modifier onlyManager() {
        if (msg.sender != address(manager)) revert OnlyPoolManager();
        _;
    }

    modifier onlyOwner() {
        if (msg.sender != owner) revert OnlyOwner();
        _;
    }

    constructor(IPoolManager manager_, BuybackVault vault_, address owner_, uint16 feeBips_) {
        if (address(manager_) == address(0) || address(vault_) == address(0) || owner_ == address(0)) {
            revert InvalidAddress();
        }
        if (feeBips_ > 2_000) revert InvalidBips();

        Hooks.validateHookPermissions(
            IHooks(address(this)),
            Hooks.Permissions({
                beforeInitialize: false,
                afterInitialize: false,
                beforeAddLiquidity: false,
                afterAddLiquidity: false,
                beforeRemoveLiquidity: false,
                afterRemoveLiquidity: false,
                beforeSwap: false,
                afterSwap: true,
                beforeDonate: false,
                afterDonate: false,
                beforeSwapReturnDelta: false,
                afterSwapReturnDelta: true,
                afterAddLiquidityReturnDelta: false,
                afterRemoveLiquidityReturnDelta: false
            })
        );

        manager = manager_;
        vault = vault_;
        owner = owner_;
        feeBips = feeBips_;
    }

    function transferOwnership(address nextOwner) external onlyOwner {
        if (nextOwner == address(0)) revert InvalidAddress();
        owner = nextOwner;
    }

    function setFeeBips(uint16 feeBips_) external onlyOwner {
        if (feeBips_ > 2_000) revert InvalidBips();
        feeBips = feeBips_;
        emit FeeBipsSet(feeBips_);
    }

    function registerPool(PoolKey calldata key) external onlyOwner returns (PoolId poolId) {
        _validatePoolKey(key);
        poolId = key.toId();
        isRegisteredPool[poolId] = true;
        emit PoolRegistered(poolId, Currency.unwrap(key.currency0), Currency.unwrap(key.currency1));
    }

    function removePool(PoolKey calldata key) external onlyOwner returns (PoolId poolId) {
        _validatePoolKey(key);
        poolId = key.toId();
        isRegisteredPool[poolId] = false;
        emit PoolRegistrationRemoved(poolId);
    }

    function afterSwap(address, PoolKey calldata key, SwapParams calldata params, BalanceDelta delta, bytes calldata)
        external
        override
        onlyManager
        returns (bytes4, int128)
    {
        if (params.amountSpecified > 0) revert ExactOutputUnsupported();

        PoolId poolId = key.toId();
        if (!isRegisteredPool[poolId]) revert PoolNotRegistered(poolId);

        (Currency feeCurrency, int128 swapAmount) = _feeCurrencyAndAmount(key, params, delta);
        if (feeCurrency.isAddressZero()) revert NativeCurrencyUnsupported();
        if (swapAmount >= 0) revert InvalidSwapDelta();

        uint256 absAmount = uint256((-swapAmount).toUint128());
        uint256 feeAmount = absAmount * feeBips / 10_000;
        if (feeAmount == 0) return (IHooks.afterSwap.selector, 0);

        manager.take(feeCurrency, address(this), feeAmount);

        address feeToken = Currency.unwrap(feeCurrency);
        uint256 buybackAmount = feeAmount / 2;
        uint256 treasuryAmount = feeAmount - buybackAmount;

        IERC20(feeToken).forceApprove(address(vault), feeAmount);
        vault.depositFee(feeToken, buybackAmount, treasuryAmount);
        IERC20(feeToken).forceApprove(address(vault), 0);

        emit SwapFeeRouted(poolId, feeToken, feeAmount, buybackAmount, treasuryAmount);

        return (IHooks.afterSwap.selector, feeAmount.toInt128());
    }

    function _feeCurrencyAndAmount(PoolKey calldata key, SwapParams calldata params, BalanceDelta delta)
        internal
        pure
        returns (Currency feeCurrency, int128 swapAmount)
    {
        (feeCurrency, swapAmount) =
            params.zeroForOne ? (key.currency1, delta.amount1()) : (key.currency0, delta.amount0());
    }

    function _validatePoolKey(PoolKey calldata key) internal view {
        if (address(key.hooks) != address(this)) revert HookMismatch();
        address currency0 = Currency.unwrap(key.currency0);
        address currency1 = Currency.unwrap(key.currency1);
        if (currency0 == address(0) || currency1 == address(0)) revert NativeCurrencyUnsupported();
        if (currency0 >= currency1) revert CurrenciesOutOfOrder();
    }

    function beforeInitialize(address, PoolKey calldata, uint160) external pure override returns (bytes4) {
        revert("NOT_IMPLEMENTED");
    }

    function afterInitialize(address, PoolKey calldata, uint160, int24) external pure override returns (bytes4) {
        revert("NOT_IMPLEMENTED");
    }

    function beforeAddLiquidity(address, PoolKey calldata, ModifyLiquidityParams calldata, bytes calldata)
        external
        pure
        override
        returns (bytes4)
    {
        revert("NOT_IMPLEMENTED");
    }

    function afterAddLiquidity(
        address,
        PoolKey calldata,
        ModifyLiquidityParams calldata,
        BalanceDelta,
        BalanceDelta,
        bytes calldata
    ) external pure override returns (bytes4, BalanceDelta) {
        revert("NOT_IMPLEMENTED");
    }

    function beforeRemoveLiquidity(address, PoolKey calldata, ModifyLiquidityParams calldata, bytes calldata)
        external
        pure
        override
        returns (bytes4)
    {
        revert("NOT_IMPLEMENTED");
    }

    function afterRemoveLiquidity(
        address,
        PoolKey calldata,
        ModifyLiquidityParams calldata,
        BalanceDelta,
        BalanceDelta,
        bytes calldata
    ) external pure override returns (bytes4, BalanceDelta) {
        revert("NOT_IMPLEMENTED");
    }

    function beforeSwap(address, PoolKey calldata, SwapParams calldata, bytes calldata)
        external
        pure
        override
        returns (bytes4, BeforeSwapDelta, uint24)
    {
        return (IHooks.beforeSwap.selector, BeforeSwapDeltaLibrary.ZERO_DELTA, 0);
    }

    function beforeDonate(address, PoolKey calldata, uint256, uint256, bytes calldata)
        external
        pure
        override
        returns (bytes4)
    {
        revert("NOT_IMPLEMENTED");
    }

    function afterDonate(address, PoolKey calldata, uint256, uint256, bytes calldata)
        external
        pure
        override
        returns (bytes4)
    {
        revert("NOT_IMPLEMENTED");
    }
}
