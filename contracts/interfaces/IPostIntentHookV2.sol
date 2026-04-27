// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

/**
 * @title IPostIntentHookV2
 * @notice Interface for post-intent hooks in Peer.xyz/zkp2p V3
 * @dev Post-intent hooks run during fulfillIntent after verification
 *      Used for custom fund routing (bridging, splitting, swapping)
 */
interface IPostIntentHookV2 {
    struct HookIntentContext {
        address owner;
        address to;
        address escrow;
        uint256 depositId;
        uint256 amount;
        uint256 timestamp;
        bytes32 paymentMethod;
        bytes32 fiatCurrency;
        uint256 conversionRate;
        bytes32 payeeId;
        bytes signalHookData; // from SignalIntentParams.data
    }

    struct HookExecutionContext {
        bytes32 intentHash;
        address token; // deposit token address
        uint256 executableAmount; // amount after all fees
        HookIntentContext intent;
    }

    /**
     * @notice Execute the hook after intent fulfillment
     * @param _ctx Execution context with all intent details
     * @param _fulfillHookData Dynamic data passed at fulfill time
     */
    function execute(HookExecutionContext calldata _ctx, bytes calldata _fulfillHookData) external;
}
