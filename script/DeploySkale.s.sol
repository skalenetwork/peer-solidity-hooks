// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import { Script, console } from "forge-std/Script.sol";
import { SkaleReceiver } from "../src/SkaleReceiver.sol";

contract DeploySkale is Script {
    // Mapped USDC on SKALE Base
    address public constant MAPPED_USDC_SEPOLIA = 0x2e08028E3C4c2356572E096d8EF835cD5C6030bD;
    address public constant MAPPED_USDC_MAINNET = 0x0000000000000000000000000000000000000001; // TODO: verify mainnet address

    function run() public {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        string memory network = vm.envString("NETWORK"); // "testnet" or "mainnet"

        vm.startBroadcast(deployerPrivateKey);

        bool isTestnet = keccak256(bytes(network)) == keccak256(bytes("testnet"));
        address mappedUsdc = isTestnet ? MAPPED_USDC_SEPOLIA : MAPPED_USDC_MAINNET;

        // Deploy receiver
        SkaleReceiver receiver = new SkaleReceiver(mappedUsdc);

        console.log("SkaleReceiver deployed on", network, ":", address(receiver));
        console.log("Mapped USDC:", mappedUsdc);
        console.log("Owner:", msg.sender);

        // Output verification info
        console.log("");
        console.log("--- VERIFICATION INFO ---");
        console.log("Contract Address:", address(receiver));
        console.log("Constructor Args:");
        console.log("  - mappedUsdc:", mappedUsdc);
        console.log("------------------------");
        console.log("");
        console.log("IMPORTANT: Register this contract with MessageProxy:");
        console.log("cast send 0xd2AAa00100000000000000000000000000000000 \\");
        console.log('  "grantRole(bytes32,address)" \\');
        console.log("  0x96e3fc3be15159903e053027cff8a23f39a990e0194abcd8ac1cf1b355b8b93c \\");
        console.log(" ", address(receiver));
        console.log("------------------------");

        vm.stopBroadcast();
    }
}
