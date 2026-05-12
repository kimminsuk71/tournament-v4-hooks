// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Test} from "forge-std/Test.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IHooks} from "v4-core/interfaces/IHooks.sol";
import {IPoolManager} from "v4-core/interfaces/IPoolManager.sol";
import {PoolKey} from "v4-core/types/PoolKey.sol";
import {SwapParams} from "v4-core/types/PoolOperation.sol";
import {BalanceDelta, toBalanceDelta} from "v4-core/types/BalanceDelta.sol";
import {Currency} from "v4-core/types/Currency.sol";
import {Hooks} from "v4-core/libraries/Hooks.sol";
import {HubToken} from "../src/HubToken.sol";
import {TeamToken} from "../src/TeamToken.sol";
import {TeamTokenFactory} from "../src/TeamTokenFactory.sol";
import {BuybackVault} from "../src/BuybackVault.sol";
import {HookDeployer} from "../src/HookDeployer.sol";
import {TournamentHook} from "../src/TournamentHook.sol";
import {IBuybackExecutor} from "../src/interfaces/IBuybackExecutor.sol";

contract MockPoolManager {
    using SafeERC20 for IERC20;

    function take(Currency currency, address to, uint256 amount) external {
        IERC20(Currency.unwrap(currency)).safeTransfer(to, amount);
    }

    function callAfterSwap(TournamentHook hook, PoolKey calldata key, SwapParams calldata params, BalanceDelta delta)
        external
        returns (bytes4 selector, int128 hookDelta)
    {
        return hook.afterSwap(address(this), key, params, delta, "");
    }
}

contract MockBuybackExecutor is IBuybackExecutor {
    using SafeERC20 for IERC20;

    uint256 public immutable hubOutPerFeeToken;

    constructor(uint256 hubOutPerFeeToken_) {
        hubOutPerFeeToken = hubOutPerFeeToken_;
    }

    function executeBuyback(address feeToken, uint256 amountIn, address hubToken, address recipient)
        external
        returns (uint256 hubAmountOut)
    {
        IERC20(feeToken).safeTransferFrom(msg.sender, address(this), amountIn);
        hubAmountOut = amountIn * hubOutPerFeeToken / 1e18;
        IERC20(hubToken).safeTransfer(recipient, hubAmountOut);
    }
}

contract UnderpayingBuybackExecutor is IBuybackExecutor {
    using SafeERC20 for IERC20;

    function executeBuyback(address feeToken, uint256 amountIn, address hubToken, address recipient)
        external
        returns (uint256 hubAmountOut)
    {
        IERC20(feeToken).safeTransferFrom(msg.sender, address(this), amountIn - 1);
        hubAmountOut = amountIn;
        IERC20(hubToken).safeTransfer(recipient, hubAmountOut);
    }
}

contract TournamentHookTest is Test {
    uint160 internal constant REQUIRED_FLAGS = Hooks.AFTER_SWAP_FLAG | Hooks.AFTER_SWAP_RETURNS_DELTA_FLAG;

    HubToken internal hub;
    TeamToken internal team;
    TeamToken internal quote;
    BuybackVault internal vault;
    TournamentHook internal hook;
    MockPoolManager internal manager;

    address internal owner = address(0xA11CE);
    address internal treasury = address(0xB0B);

    function setUp() public {
        hub = new HubToken("Tournament Hub", "HUB", address(this), 1_000_000e18);
        team = new TeamToken("alpha", "Alpha FC", "ALPHA", address(this), 1_000_000e18);
        quote = new TeamToken("usd", "Mock USD", "mUSD", address(this), 1_000_000e18);
        vault = new BuybackVault(address(hub), owner, treasury);
        manager = new MockPoolManager();
        hook = _deployHook(vault);

        vm.prank(owner);
        vault.setHook(address(hook));
    }

    function testFactoryCreatesTeamToken() public {
        TeamTokenFactory factory = new TeamTokenFactory(owner);

        vm.prank(owner);
        address token = factory.createTeamToken("usa", "United States", "USA", address(this), 100e18);

        assertEq(factory.teamTokenOf(keccak256(bytes("usa"))), token);
        assertEq(factory.teamTokenCount(), 1);
        assertEq(TeamToken(token).balanceOf(address(this)), 100e18);

        vm.prank(owner);
        vm.expectRevert(abi.encodeWithSelector(TeamTokenFactory.TeamAlreadyCreated.selector, keccak256(bytes("usa"))));
        factory.createTeamToken("usa", "United States 2", "USA2", address(this), 100e18);
    }

    function testAfterSwapRoutesFeeHalfToBuybackHalfToTreasury() public {
        (PoolKey memory key, SwapParams memory params, BalanceDelta delta, address feeToken) =
            _registeredExactInPoolWithFeeCurrency(address(quote), 1_000e18);

        assertTrue(quote.transfer(address(manager), 20e18));

        (bytes4 selector, int128 hookDelta) = manager.callAfterSwap(hook, key, params, delta);

        assertEq(selector, IHooks.afterSwap.selector);
        assertEq(hookDelta, int128(uint128(10e18)));
        assertEq(vault.pendingBuyback(feeToken), 5e18);
        assertEq(quote.balanceOf(treasury), 5e18);
        assertEq(quote.balanceOf(address(manager)), 10e18);
    }

    function testExecuteBuybackBurnsHub() public {
        (PoolKey memory key, SwapParams memory params, BalanceDelta delta, address feeToken) =
            _registeredExactInPoolWithFeeCurrency(address(quote), 1_000e18);

        assertTrue(quote.transfer(address(manager), 20e18));
        manager.callAfterSwap(hook, key, params, delta);

        MockBuybackExecutor executor = new MockBuybackExecutor(2e18);
        assertTrue(hub.transfer(address(executor), 20e18));

        uint256 supplyBefore = hub.totalSupply();

        vm.prank(owner);
        uint256 burned = vault.executeBuybackAndBurn(feeToken, address(executor), 5e18, 10e18);

        assertEq(burned, 10e18);
        assertEq(vault.pendingBuyback(feeToken), 0);
        assertEq(vault.totalHubBurned(), 10e18);
        assertEq(hub.totalSupply(), supplyBefore - 10e18);
        assertEq(quote.balanceOf(address(executor)), 5e18);
    }

    function testExactOutputSwapReverts() public {
        (Currency currency0, Currency currency1) = _sort(address(team), address(quote));
        PoolKey memory key = PoolKey({
            currency0: currency0, currency1: currency1, fee: 3_000, tickSpacing: 60, hooks: IHooks(address(hook))
        });

        vm.prank(owner);
        hook.registerPool(key);

        SwapParams memory params = SwapParams({zeroForOne: true, amountSpecified: int256(100e18), sqrtPriceLimitX96: 0});
        BalanceDelta delta = toBalanceDelta(_toInt128(102e18), -_toInt128(100e18));

        vm.expectRevert(TournamentHook.ExactOutputUnsupported.selector);
        manager.callAfterSwap(hook, key, params, delta);
    }

    function testRegisterPoolRejectsDifferentHookAddress() public {
        (Currency currency0, Currency currency1) = _sort(address(team), address(quote));
        PoolKey memory key = PoolKey({
            currency0: currency0, currency1: currency1, fee: 3_000, tickSpacing: 60, hooks: IHooks(address(0x44))
        });

        vm.prank(owner);
        vm.expectRevert(TournamentHook.HookMismatch.selector);
        hook.registerPool(key);
    }

    function testConstructorRejectsNonPermissionedHookAddress() public {
        vm.expectRevert();
        new TournamentHook(IPoolManager(address(manager)), vault, owner, 100);
    }

    function testBuybackRevertsIfExecutorDoesNotSpendFullFeeAmount() public {
        (PoolKey memory key, SwapParams memory params, BalanceDelta delta, address feeToken) =
            _registeredExactInPoolWithFeeCurrency(address(quote), 1_000e18);

        assertTrue(quote.transfer(address(manager), 20e18));
        manager.callAfterSwap(hook, key, params, delta);

        UnderpayingBuybackExecutor executor = new UnderpayingBuybackExecutor();
        assertTrue(hub.transfer(address(executor), 20e18));

        vm.prank(owner);
        vm.expectRevert(BuybackVault.FeeTokenNotSpent.selector);
        vault.executeBuybackAndBurn(feeToken, address(executor), 5e18, 5e18);

        assertEq(vault.pendingBuyback(feeToken), 5e18);
    }

    function testBurnPendingHubDirectly() public {
        address feeToken = address(hub);
        assertTrue(hub.transfer(address(hook), 20e18));

        vm.prank(address(hook));
        hub.approve(address(vault), 12e18);

        vm.prank(address(hook));
        vault.depositFee(feeToken, 10e18, 2e18);

        uint256 supplyBefore = hub.totalSupply();

        vm.prank(owner);
        vault.burnPendingHub(10e18);

        assertEq(vault.pendingBuyback(feeToken), 0);
        assertEq(vault.totalHubBurned(), 10e18);
        assertEq(hub.totalSupply(), supplyBefore - 10e18);
        assertEq(hub.balanceOf(treasury), 2e18);
    }

    function _registeredExactInPoolWithFeeCurrency(address desiredFeeToken, uint128 outputAmount)
        internal
        returns (PoolKey memory key, SwapParams memory params, BalanceDelta delta, address feeToken)
    {
        (Currency currency0, Currency currency1) = _sort(address(team), address(quote));
        key = PoolKey({
            currency0: currency0, currency1: currency1, fee: 3_000, tickSpacing: 60, hooks: IHooks(address(hook))
        });

        vm.prank(owner);
        hook.registerPool(key);

        if (Currency.unwrap(currency1) == desiredFeeToken) {
            params =
                SwapParams({zeroForOne: true, amountSpecified: -int256(uint256(outputAmount)), sqrtPriceLimitX96: 0});
            delta = toBalanceDelta(0, -_toInt128(outputAmount));
            feeToken = Currency.unwrap(currency1);
        } else {
            params =
                SwapParams({zeroForOne: false, amountSpecified: -int256(uint256(outputAmount)), sqrtPriceLimitX96: 0});
            delta = toBalanceDelta(-_toInt128(outputAmount), 0);
            feeToken = Currency.unwrap(currency0);
        }
    }

    function _toInt128(uint128 value) internal pure returns (int128) {
        require(value <= uint128(type(int128).max), "INT128_OVERFLOW");
        // forge-lint: disable-next-line(unsafe-typecast)
        return int128(value);
    }

    function _deployHook(BuybackVault vault_) internal returns (TournamentHook deployedHook) {
        HookDeployer deployer = new HookDeployer();
        bytes memory creationCode = abi.encodePacked(
            type(TournamentHook).creationCode, abi.encode(IPoolManager(address(manager)), vault_, owner, uint16(100))
        );
        bytes32 initCodeHash = keccak256(creationCode);

        for (uint256 i = 0; i < 250_000; i++) {
            bytes32 salt = bytes32(i);
            address predicted =
                address(uint160(uint256(keccak256(abi.encodePacked(bytes1(0xff), deployer, salt, initCodeHash)))));
            if ((uint160(predicted) & Hooks.ALL_HOOK_MASK) == REQUIRED_FLAGS) {
                return TournamentHook(deployer.deploy(salt, creationCode));
            }
        }
        revert("NO_SALT_FOUND");
    }

    function _sort(address a, address b) internal pure returns (Currency currency0, Currency currency1) {
        (address token0, address token1) = a < b ? (a, b) : (b, a);
        currency0 = Currency.wrap(token0);
        currency1 = Currency.wrap(token1);
    }
}
