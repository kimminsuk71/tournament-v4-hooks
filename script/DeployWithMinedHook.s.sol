// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Script, console2} from "forge-std/Script.sol";
import {Hooks} from "v4-core/libraries/Hooks.sol";
import {IPoolManager} from "v4-core/interfaces/IPoolManager.sol";
import {HubToken} from "../src/HubToken.sol";
import {BuybackVault} from "../src/BuybackVault.sol";
import {HookDeployer} from "../src/HookDeployer.sol";
import {TournamentHook} from "../src/TournamentHook.sol";
import {TeamTokenFactory} from "../src/TeamTokenFactory.sol";

contract DeployWithMinedHook is Script {
    uint160 internal constant REQUIRED_FLAGS = Hooks.AFTER_SWAP_FLAG | Hooks.AFTER_SWAP_RETURNS_DELTA_FLAG;
    uint160 internal constant ALL_FLAGS = Hooks.ALL_HOOK_MASK;

    function run()
        external
        returns (HubToken hub, BuybackVault vault, HookDeployer deployer, TournamentHook hook, TeamTokenFactory factory)
    {
        uint256 privateKey = vm.envUint("PRIVATE_KEY");
        address broadcaster = vm.addr(privateKey);
        address owner = vm.envOr("OWNER", broadcaster);
        address treasury = vm.envOr("TREASURY", owner);
        address poolManager = vm.envAddress("POOL_MANAGER");
        uint256 feeBipsRaw = vm.envOr("HOOK_FEE_BIPS", uint256(100));
        uint256 saltMaxIterations = vm.envOr("SALT_MAX_ITERATIONS", uint256(250_000));
        require(owner != address(0), "ZERO_OWNER");
        require(treasury != address(0), "ZERO_TREASURY");
        require(poolManager != address(0), "ZERO_POOL_MANAGER");
        require(poolManager.code.length != 0, "POOL_MANAGER_NO_CODE");
        require(owner != poolManager, "OWNER_IS_POOL_MANAGER");
        require(feeBipsRaw <= 2_000, "HOOK_FEE_BIPS_TOO_HIGH");
        require(saltMaxIterations != 0, "SALT_MAX_ITERATIONS_ZERO");
        // forge-lint: disable-next-line(unsafe-typecast)
        uint16 feeBips = uint16(feeBipsRaw);

        vm.startBroadcast(privateKey);
        hub = new HubToken("Tournament Hub", "HUB", owner, 1_000_000_000e18);
        vault = new BuybackVault(address(hub), broadcaster, treasury);
        factory = new TeamTokenFactory(owner);
        deployer = new HookDeployer(broadcaster);

        bytes memory creationCode = abi.encodePacked(
            type(TournamentHook).creationCode, abi.encode(IPoolManager(poolManager), vault, owner, feeBips)
        );
        (bytes32 salt, address predicted) = mineSalt(address(deployer), keccak256(creationCode), saltMaxIterations);
        hook = TournamentHook(deployer.deploy(salt, creationCode));
        require(address(hook) == predicted, "PREDICTION_MISMATCH");
        vault.setHook(address(hook));
        if (owner != broadcaster) vault.transferOwnership(owner);
        vm.stopBroadcast();

        console2.log("HubToken", address(hub));
        console2.log("BuybackVault", address(vault));
        console2.log("HookDeployer", address(deployer));
        console2.log("TournamentHook", address(hook));
        console2.log("TeamTokenFactory", address(factory));
        console2.logBytes32(salt);
    }

    function mineSalt(address deployer, bytes32 initCodeHash, uint256 maxIterations)
        public
        pure
        returns (bytes32 salt, address predicted)
    {
        for (uint256 i = 0; i < maxIterations; i++) {
            salt = bytes32(i);
            predicted =
                address(uint160(uint256(keccak256(abi.encodePacked(bytes1(0xff), deployer, salt, initCodeHash)))));
            if ((uint160(predicted) & ALL_FLAGS) == REQUIRED_FLAGS) return (salt, predicted);
        }
        revert("NO_SALT_FOUND");
    }
}
