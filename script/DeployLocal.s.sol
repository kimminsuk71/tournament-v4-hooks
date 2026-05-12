// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Script} from "forge-std/Script.sol";
import {IPoolManager} from "v4-core/interfaces/IPoolManager.sol";
import {HubToken} from "../src/HubToken.sol";
import {BuybackVault} from "../src/BuybackVault.sol";
import {TournamentHook} from "../src/TournamentHook.sol";
import {TeamTokenFactory} from "../src/TeamTokenFactory.sol";

contract DeployLocal is Script {
    function run() external returns (HubToken hub, BuybackVault vault, TournamentHook hook, TeamTokenFactory factory) {
        address owner = vm.envOr("OWNER", msg.sender);
        address treasury = vm.envOr("TREASURY", owner);
        address poolManager = vm.envOr("POOL_MANAGER", address(0));

        vm.startBroadcast();
        hub = new HubToken("Tournament Hub", "HUB", owner, 1_000_000_000e18);
        vault = new BuybackVault(address(hub), owner, treasury);
        factory = new TeamTokenFactory(owner);

        if (poolManager != address(0)) {
            hook = new TournamentHook(IPoolManager(poolManager), vault, owner, 100);
            vault.setHook(address(hook));
        }
        vm.stopBroadcast();
    }
}
