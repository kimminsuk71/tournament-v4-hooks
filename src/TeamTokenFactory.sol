// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {TeamToken} from "./TeamToken.sol";

contract TeamTokenFactory is Ownable {
    error TeamAlreadyCreated(bytes32 teamKey);
    error EmptyTeamId();
    error InvalidAddress();
    error InvalidAmount();

    event TeamTokenCreated(bytes32 indexed teamKey, string teamId, address indexed token, address indexed owner);

    mapping(bytes32 teamKey => address token) public teamTokenOf;
    address[] public allTeamTokens;

    constructor(address owner_) Ownable(owner_) {}

    function createTeamToken(
        string calldata teamId,
        string calldata name,
        string calldata symbol,
        address tokenOwner,
        uint256 initialSupply
    ) external onlyOwner returns (address token) {
        if (bytes(teamId).length == 0) revert EmptyTeamId();
        if (tokenOwner == address(0)) revert InvalidAddress();
        if (initialSupply == 0) revert InvalidAmount();
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
}
