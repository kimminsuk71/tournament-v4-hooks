// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {ERC20Burnable} from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Burnable.sol";

contract HubToken is ERC20, ERC20Burnable {
    error InvalidAddress();
    error InvalidAmount();
    error MintingDisabled();

    constructor(string memory name_, string memory symbol_, address owner_, uint256 initialSupply)
        ERC20(name_, symbol_)
    {
        if (owner_ == address(0)) revert InvalidAddress();
        if (initialSupply == 0) revert InvalidAmount();
        if (bytes(name_).length == 0 || bytes(symbol_).length == 0) revert InvalidAmount();
        _mint(owner_, initialSupply);
    }

    function mint(address, uint256) external pure {
        revert MintingDisabled();
    }
}
