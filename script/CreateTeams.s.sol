// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Script, console2} from "forge-std/Script.sol";
import {TeamTokenFactory} from "../src/TeamTokenFactory.sol";

contract CreateTeams is Script {
    function run() external {
        uint256 privateKey = vm.envUint("PRIVATE_KEY");
        address factory = vm.envAddress("TEAM_FACTORY");
        address tokenOwner = vm.envOr("TOKEN_OWNER", vm.addr(privateKey));
        uint256 initialSupply = vm.envOr("TEAM_INITIAL_SUPPLY", uint256(1_000_000_000e18));

        require(factory != address(0), "ZERO_FACTORY");
        require(tokenOwner != address(0), "ZERO_TOKEN_OWNER");
        require(initialSupply != 0, "ZERO_INITIAL_SUPPLY");

        string memory idsCsv = vm.envOr("TEAM_IDS", string("alpha,bravo,delta,nova"));
        string memory namesCsv = vm.envOr("TEAM_NAMES", string("Alpha FC,Bravo United,Delta City,Nova Athletic"));
        string memory symbolsCsv = vm.envOr("TEAM_SYMBOLS", string("ALPHA,BRAVO,DELTA,NOVA"));

        string[] memory ids = vm.split(idsCsv, ",");
        string[] memory names = vm.split(namesCsv, ",");
        string[] memory symbols = vm.split(symbolsCsv, ",");
        require(ids.length == names.length && names.length == symbols.length, "TEAM_ARRAY_LENGTH_MISMATCH");

        vm.startBroadcast(privateKey);
        for (uint256 i = 0; i < ids.length; i++) {
            require(_isValidTeamId(ids[i]), "INVALID_TEAM_ID");
            require(bytes(names[i]).length != 0, "EMPTY_TEAM_NAME");
            require(bytes(symbols[i]).length != 0, "EMPTY_TEAM_SYMBOL");
            address token =
                TeamTokenFactory(factory).createTeamToken(ids[i], names[i], symbols[i], tokenOwner, initialSupply);
            console2.log(ids[i], token);
        }
        vm.stopBroadcast();
    }

    function _isValidTeamId(string memory teamId) internal pure returns (bool) {
        bytes memory raw = bytes(teamId);
        if (raw.length == 0) return false;
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
