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

        string memory idsCsv = vm.envOr("TEAM_IDS", string("alpha,bravo,delta,nova"));
        string memory namesCsv = vm.envOr("TEAM_NAMES", string("Alpha FC,Bravo United,Delta City,Nova Athletic"));
        string memory symbolsCsv = vm.envOr("TEAM_SYMBOLS", string("ALPHA,BRAVO,DELTA,NOVA"));

        string[] memory ids = vm.split(idsCsv, ",");
        string[] memory names = vm.split(namesCsv, ",");
        string[] memory symbols = vm.split(symbolsCsv, ",");
        require(ids.length == names.length && names.length == symbols.length, "TEAM_ARRAY_LENGTH_MISMATCH");

        vm.startBroadcast(privateKey);
        for (uint256 i = 0; i < ids.length; i++) {
            address token =
                TeamTokenFactory(factory).createTeamToken(ids[i], names[i], symbols[i], tokenOwner, initialSupply);
            console2.log(ids[i], token);
        }
        vm.stopBroadcast();
    }
}
