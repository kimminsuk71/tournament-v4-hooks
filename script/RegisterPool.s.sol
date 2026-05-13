// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Script, console2} from "forge-std/Script.sol";
import {IHooks} from "v4-core/interfaces/IHooks.sol";
import {PoolKey} from "v4-core/types/PoolKey.sol";
import {PoolId} from "v4-core/types/PoolId.sol";
import {Currency} from "v4-core/types/Currency.sol";
import {TournamentHook} from "../src/TournamentHook.sol";

contract RegisterPool is Script {
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
        require(tickSpacingRaw > 0 && tickSpacingRaw <= uint24(type(int24).max), "TICK_SPACING_OUT_OF_RANGE");

        // forge-lint: disable-next-line(unsafe-typecast)
        uint24 lpFee = uint24(lpFeeRaw);
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
