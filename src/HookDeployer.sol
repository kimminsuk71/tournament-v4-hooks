// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

contract HookDeployer {
    error OnlyOwner();
    error InvalidAddress();
    error EmptyCode();
    error DeploymentFailed();

    event Deployed(address indexed addr, bytes32 indexed salt);

    address public immutable owner;

    constructor(address owner_) {
        if (owner_ == address(0)) revert InvalidAddress();
        owner = owner_;
    }

    function deploy(bytes32 salt, bytes calldata creationCode) external returns (address addr) {
        if (msg.sender != owner) revert OnlyOwner();
        if (creationCode.length == 0) revert EmptyCode();

        bytes memory code = creationCode;
        assembly ("memory-safe") {
            addr := create2(0, add(code, 0x20), mload(code), salt)
        }
        if (addr == address(0)) revert DeploymentFailed();
        if (addr.code.length == 0) revert EmptyCode();

        emit Deployed(addr, salt);
    }

    function computeAddress(bytes32 salt, bytes32 initCodeHash) external view returns (address) {
        return address(uint160(uint256(keccak256(abi.encodePacked(bytes1(0xff), address(this), salt, initCodeHash)))));
    }
}
