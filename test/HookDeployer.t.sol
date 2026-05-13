// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Test} from "forge-std/Test.sol";
import {IPoolManager} from "v4-core/interfaces/IPoolManager.sol";
import {Hooks} from "v4-core/libraries/Hooks.sol";
import {HubToken} from "../src/HubToken.sol";
import {BuybackVault} from "../src/BuybackVault.sol";
import {HookDeployer} from "../src/HookDeployer.sol";
import {TournamentHook} from "../src/TournamentHook.sol";

contract HookDeployerTest is Test {
    uint160 internal constant REQUIRED_FLAGS = Hooks.AFTER_SWAP_FLAG | Hooks.AFTER_SWAP_RETURNS_DELTA_FLAG;

    function testMinesAndDeploysHookWithAfterSwapReturnDeltaFlags() public {
        address owner = address(this);
        HubToken hub = new HubToken("Tournament Hub", "HUB", owner, 1_000_000e18);
        BuybackVault vault = new BuybackVault(address(hub), owner, owner);
        HookDeployer deployer = new HookDeployer(owner);

        bytes memory creationCode = abi.encodePacked(
            type(TournamentHook).creationCode, abi.encode(IPoolManager(address(deployer)), vault, owner, uint16(100))
        );
        bytes32 initCodeHash = keccak256(creationCode);
        (bytes32 salt, address predicted) = _mineSalt(address(deployer), initCodeHash, 250_000);

        assertEq(uint160(predicted) & Hooks.ALL_HOOK_MASK, REQUIRED_FLAGS);
        assertEq(deployer.computeAddress(salt, initCodeHash), predicted);

        address deployed = deployer.deploy(salt, creationCode);
        assertEq(deployed, predicted);
    }

    function testOnlyOwnerCanDeploy() public {
        HookDeployer deployer = new HookDeployer(address(this));

        vm.prank(address(0xB0B));
        vm.expectRevert(HookDeployer.OnlyOwner.selector);
        deployer.deploy(bytes32(0), hex"00");
    }

    function testRejectsInitCodeThatDeploysNoRuntime() public {
        HookDeployer deployer = new HookDeployer(address(this));

        vm.expectRevert(HookDeployer.EmptyCode.selector);
        deployer.deploy(bytes32(0), hex"00");
    }

    function _mineSalt(address deployer, bytes32 initCodeHash, uint256 maxIterations)
        internal
        pure
        returns (bytes32 salt, address predicted)
    {
        for (uint256 i = 0; i < maxIterations; i++) {
            salt = bytes32(i);
            predicted =
                address(uint160(uint256(keccak256(abi.encodePacked(bytes1(0xff), deployer, salt, initCodeHash)))));
            if ((uint160(predicted) & Hooks.ALL_HOOK_MASK) == REQUIRED_FLAGS) return (salt, predicted);
        }
        revert("NO_SALT_FOUND");
    }
}
