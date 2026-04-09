// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import { Script, console } from "forge-std/Script.sol";
import { SkaleBridgeHook } from "../src/SkaleBridgeHook.sol";

contract DeployBase is Script {
    // Peer.xyz OrchestratorV2 on Base
    address public constant ORCHESTRATOR = 0x888888359E981B5225CA48fbCdCeff702FC3b888;

    // USDC on Base
    address public constant USDC_MAINNET = 0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913;
    address public constant USDC_SEPOLIA = 0x03655B2e3C0C3D9a5bB79b5451ea47eFCDbd3AAF;

    // SKALE Base Chain IDs
    uint64 public constant SKALE_BASE_SEPOLIA = 324705682;
    uint64 public constant SKALE_BASE_MAINNET = 1187947933;

    function run() public {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        string memory network = vm.envString("NETWORK"); // "testnet" or "mainnet"

        vm.startBroadcast(deployerPrivateKey);

        bool isTestnet = keccak256(bytes(network)) == keccak256(bytes("testnet"));

        // Select addresses based on network
        address usdc = isTestnet ? USDC_SEPOLIA : USDC_MAINNET;
        uint64 skaleChainId = isTestnet ? SKALE_BASE_SEPOLIA : SKALE_BASE_MAINNET;

        // Placeholder addresses - these need to be set based on actual deployment
        address skaleReceiver = isTestnet
            ? 0x0000000000000000000000000000000000000001 // TODO: replace with actual SKALE receiver address
            : 0x0000000000000000000000000000000000000001; // TODO: replace with actual SKALE receiver address

        // For now, set depositBox and messageProxy to address(0)
        // These need to be verified if they exist on Base
        address depositBox = address(0); // TODO: find actual DepositBox address on Base if exists
        address messageProxy = address(0); // TODO: verify if MessageProxy exists on Base for SKALE communication

        // Deploy hook
        SkaleBridgeHook hook = new SkaleBridgeHook(
            ORCHESTRATOR,
            usdc,
            depositBox,
            messageProxy,
            skaleChainId,
            skaleReceiver
        );

        console.log("SkaleBridgeHook deployed on", network, ":", address(hook));
        console.log("USDC:", usdc);
        console.log("SKALE Chain ID:", skaleChainId);
        console.log("Owner:", msg.sender);

        // Output verification info
        console.log("");
        console.log("--- VERIFICATION INFO ---");
        console.log("Contract Address:", address(hook));
        console.log("Constructor Args:");
        console.log("  - orchestrator:", ORCHESTRATOR);
        console.log("  - usdc:", usdc);
        console.log("  - depositBox:", depositBox);
        console.log("  - messageProxy:", messageProxy);
        console.log("  - skaleChainId:", skaleChainId);
        console.log("  - skaleReceiver:", skaleReceiver);
        console.log("------------------------");

        vm.stopBroadcast();
    }
}
