// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Script, console2} from "forge-std/Script.sol";
import {IHooks} from "v4-core/interfaces/IHooks.sol";
import {PoolKey} from "v4-core/types/PoolKey.sol";
import {PoolId} from "v4-core/types/PoolId.sol";
import {Currency} from "v4-core/types/Currency.sol";
import {LPFeeLibrary} from "v4-core/libraries/LPFeeLibrary.sol";
import {TickMath} from "v4-core/libraries/TickMath.sol";
import {TournamentHook} from "../src/TournamentHook.sol";

contract RegisterPool is Script {
    using LPFeeLibrary for uint24;

    function run() external {
        uint256 privateKey = vm.envUint("PRIVATE_KEY");
        address hookAddress = vm.envAddress("HOOK");
        address tokenA = vm.envAddress("TOKEN_A");
        address tokenB = vm.envAddress("TOKEN_B");
        uint256 lpFeeRaw = vm.envOr("LP_FEE", uint256(3_000));
        uint256 tickSpacingRaw = vm.envOr("TICK_SPACING", uint256(60));

        require(hookAddress != address(0), "ZERO_HOOK");
        require(tokenA != address(0) && tokenB != address(0), "ZERO_TOKEN");
        require(tokenA != tokenB, "IDENTICAL_TOKENS");
        require(lpFeeRaw <= type(uint24).max, "LP_FEE_TOO_HIGH");
        require(tickSpacingRaw >= uint24(TickMath.MIN_TICK_SPACING), "TICK_SPACING_TOO_SMALL");
        require(tickSpacingRaw <= uint24(TickMath.MAX_TICK_SPACING), "TICK_SPACING_TOO_LARGE");

        // forge-lint: disable-next-line(unsafe-typecast)
        uint24 lpFee = uint24(lpFeeRaw);
        require(lpFee.isValid() || lpFee.isDynamicFee(), "INVALID_LP_FEE");
        // forge-lint: disable-next-line(unsafe-typecast)
        int24 tickSpacing = int24(int256(tickSpacingRaw));

        (address currency0, address currency1) = tokenA < tokenB ? (tokenA, tokenB) : (tokenB, tokenA);
        PoolKey memory key = PoolKey({
            currency0: Currency.wrap(currency0),
            currency1: Currency.wrap(currency1),
            fee: lpFee,
            tickSpacing: tickSpacing,
            hooks: IHooks(hookAddress)
        });

        vm.startBroadcast(privateKey);
        PoolId poolId = TournamentHook(hookAddress).registerPool(key);
        vm.stopBroadcast();

        console2.logBytes32(PoolId.unwrap(poolId));
    }
}
