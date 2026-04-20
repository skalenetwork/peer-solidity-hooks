// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import { Script } from "forge-std/Script.sol";
import { SkaleBridgeHook } from "../contracts/SkaleBridgeHook.sol";

/**
 * @title DeploySkaleBridgeHook
 * @notice Foundry deployment script for the SkaleBridgeHook post-intent hook.
 *
 * Required environment variables:
 *   - ORCHESTRATOR      : Peer.xyz OrchestratorV2 address on the target network
 *   - DEPOSIT_BOX       : SKALE IMA DepositBoxERC20 address on the target network
 *   - MESSAGE_PROXY     : SKALE IMA MessageProxyForMainnet address on the target network
 *   - SKALE_CHAIN_NAME  : Destination SKALE chain name (e.g. "elated-tan-skat")
 *
 * Optional environment variables:
 *   - OWNER             : If set, ownership is transferred (2-step) to this address
 *
 * Usage:
 *   forge script script/DeploySkaleBridgeHook.s.sol:DeploySkaleBridgeHook \
 *       --rpc-url $ENDPOINT \
 *       --private-key $PRIVATE_KEY \
 *       --broadcast \
 *       -vvvv
 */
contract DeploySkaleBridgeHook is Script {
    function run() external returns (SkaleBridgeHook hook) {
        address orchestrator = vm.envAddress("ORCHESTRATOR");
        address depositBox = vm.envAddress("DEPOSIT_BOX");
        address messageProxy = vm.envAddress("MESSAGE_PROXY");
        string memory skaleChainName = vm.envString("SKALE_CHAIN_NAME");

        vm.startBroadcast();

        hook = new SkaleBridgeHook(orchestrator, depositBox, messageProxy, skaleChainName);

        address newOwner = vm.envOr("OWNER", address(0));
        if (newOwner != address(0)) {
            hook.transferOwnership(newOwner);
        }

        vm.stopBroadcast();
    }
}
