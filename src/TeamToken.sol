// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract TeamToken is ERC20 {
    error InvalidAddress();
    error InvalidAmount();

    string public teamId;

    constructor(
        string memory teamId_,
        string memory name_,
        string memory symbol_,
        address owner_,
        uint256 initialSupply
    ) ERC20(name_, symbol_) {
        if (owner_ == address(0)) revert InvalidAddress();
        if (initialSupply == 0) revert InvalidAmount();
        teamId = teamId_;
        _mint(owner_, initialSupply);
    }
}
