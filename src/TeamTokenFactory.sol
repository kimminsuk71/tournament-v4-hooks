// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {TeamToken} from "./TeamToken.sol";

contract TeamTokenFactory is Ownable {
    error TeamAlreadyCreated(bytes32 teamKey);
    error EmptyTeamId();
    error InvalidAddress();
    error InvalidAmount();
    error InvalidTeamId();
    error RenounceOwnershipDisabled();

    event TeamTokenCreated(bytes32 indexed teamKey, string teamId, address indexed token, address indexed owner);

    mapping(bytes32 teamKey => address token) public teamTokenOf;
    address[] public allTeamTokens;

    constructor(address owner_) Ownable(owner_) {}

    function renounceOwnership() public view override onlyOwner {
        revert RenounceOwnershipDisabled();
    }

    function createTeamToken(
        string calldata teamId,
        string calldata name,
        string calldata symbol,
        address tokenOwner,
        uint256 initialSupply
    ) external onlyOwner returns (address token) {
        if (bytes(teamId).length == 0) revert EmptyTeamId();
        if (!_isValidTeamId(teamId)) revert InvalidTeamId();
        if (tokenOwner == address(0)) revert InvalidAddress();
        if (initialSupply == 0) revert InvalidAmount();
        if (bytes(name).length == 0 || bytes(symbol).length == 0) revert InvalidAmount();
        bytes32 key = keccak256(bytes(teamId));
        if (teamTokenOf[key] != address(0)) revert TeamAlreadyCreated(key);

        token = address(new TeamToken(teamId, name, symbol, tokenOwner, initialSupply));
        teamTokenOf[key] = token;
        allTeamTokens.push(token);

        emit TeamTokenCreated(key, teamId, token, tokenOwner);
    }

    function teamTokenCount() external view returns (uint256) {
        return allTeamTokens.length;
    }

    function _isValidTeamId(string calldata teamId) internal pure returns (bool) {
        bytes calldata raw = bytes(teamId);
        for (uint256 i = 0; i < raw.length; i++) {
            bytes1 char = raw[i];
            bool isLowerAlpha = char >= 0x61 && char <= 0x7a;
            bool isDigit = char >= 0x30 && char <= 0x39;
            bool isHyphen = char == 0x2d;
            if (!isLowerAlpha && !isDigit && !isHyphen) return false;
        }
        return true;
    }
}
