// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { IPostIntentHookV2 } from "./interfaces/IPostIntentHookV2.sol";

/**
 * @title SkaleBridgeHook
 * @notice Post-intent hook that bridges USDC from Base to SKALE Base
 * @dev Uses IMA for messaging notification while handling token bridging
 */
contract SkaleBridgeHook is IPostIntentHookV2 {
    using SafeERC20 for IERC20;

    /// @notice Peer.xyz OrchestratorV2 on Base
    address public immutable ORCHESTRATOR;

    /// @notice USDC token on Base
    /// Base Mainnet: 0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913
    /// Base Sepolia: 0x03655B2e3c0C3D9A5bB79b5451EA47eFcDbd3aaF
    address public immutable USDC;

    /// @notice DepositBox contract for bridging (if available on Base)
    address public immutable depositBox;

    /// @notice Message proxy for cross-chain communication (on Base, if exists)
    address public immutable messageProxy;

    /// @notice SKALE Base chain ID
    uint64 public immutable SKALE_BASE_CHAIN_ID;

    /// @notice Receiver contract on SKALE Base
    address public immutable skaleReceiver;

    /// @notice Contract owner for admin functions
    address public immutable owner;

    error OnlyOrchestrator();
    error OnlyOwner();
    error InvalidToken();
    error BridgeFailed();

    event BridgeInitiated(
        bytes32 indexed intentHash,
        address indexed recipient,
        uint256 amount,
        uint256 timestamp
    );

    event MessageSentToSkale(
        bytes32 indexed intentHash,
        address skaleReceiver,
        bytes data
    );

    event TokensLocked(
        bytes32 indexed intentHash,
        address indexed recipient,
        uint256 amount
    );

    constructor(
        address _orchestrator,
        address _usdc,
        address _depositBox,
        address _messageProxy,
        uint64 _skaleBaseChainId,
        address _skaleReceiver
    ) {
        ORCHESTRATOR = _orchestrator;
        USDC = _usdc;
        depositBox = _depositBox;
        messageProxy = _messageProxy;
        SKALE_BASE_CHAIN_ID = _skaleBaseChainId;
        skaleReceiver = _skaleReceiver;
        owner = msg.sender;
    }

    modifier onlyOrchestrator() {
        if (msg.sender != ORCHESTRATOR) revert OnlyOrchestrator();
        _;
    }

    modifier onlyOwner() {
        if (msg.sender != owner) revert OnlyOwner();
        _;
    }

    /**
     * @notice Execute hook after intent fulfillment
     * @param _ctx Execution context from Orchestrator
     * @param _fulfillHookData Optional data (can override recipient address)
     */
    function execute(
        HookExecutionContext calldata _ctx,
        bytes calldata _fulfillHookData
    ) external override onlyOrchestrator {
        // Only handle USDC
        if (_ctx.token != USDC) revert InvalidToken();

        // Get recipient - allow override via fulfillHookData
        address recipient = _ctx.intent.to;
        if (_fulfillHookData.length >= 32) {
            (address overrideRecipient) = abi.decode(_fulfillHookData, (address));
            if (overrideRecipient != address(0)) {
                recipient = overrideRecipient;
            }
        }

        // Pull tokens from orchestrator
        IERC20(USDC).safeTransferFrom(
            msg.sender,
            address(this),
            _ctx.executableAmount
        );

        // Option 1: If DepositBox exists on Base, use it directly
        if (depositBox != address(0)) {
            _depositToSkale(recipient, _ctx.executableAmount);
        } else {
            // Lock tokens in contract for liquidity-based bridging
            emit TokensLocked(_ctx.intentHash, recipient, _ctx.executableAmount);
        }

        // Option 2: Send IMA message to notify SKALE Base
        if (messageProxy != address(0) && skaleReceiver != address(0)) {
            _sendNotificationToSkale(_ctx.intentHash, recipient, _ctx.executableAmount);
        }

        emit BridgeInitiated(
            _ctx.intentHash,
            recipient,
            _ctx.executableAmount,
            block.timestamp
        );
    }

    /**
     * @notice Deposit USDC to SKALE via DepositBox (if available)
     */
    function _depositToSkale(address _recipient, uint256 _amount) internal {
        // Approve DepositBox (use forceApprove for safety)
        IERC20(USDC).forceApprove(depositBox, _amount);

        // Call depositERC20
        (bool success, ) = depositBox.call(
            abi.encodeWithSignature(
                "depositERC20(address,uint256,address)",
                USDC,
                _amount,
                _recipient
            )
        );

        if (!success) {
            revert BridgeFailed();
        }
    }

    /**
     * @notice Send notification message to SKALE Base via IMA
     */
    function _sendNotificationToSkale(
        bytes32 _intentHash,
        address _recipient,
        uint256 _amount
    ) internal {
        bytes memory messageData = abi.encode(
            _intentHash,
            _recipient,
            USDC,
            _amount
        );

        (bool success, ) = messageProxy.call(
            abi.encodeWithSignature(
                "postOutgoingMessage(bytes32,address,bytes)",
                keccak256(abi.encodePacked("SKALE", SKALE_BASE_CHAIN_ID)),
                skaleReceiver,
                messageData
            )
        );

        if (success) {
            emit MessageSentToSkale(_intentHash, skaleReceiver, messageData);
        }
    }

    /**
     * @notice View locked USDC balance
     */
    function lockedBalance() external view returns (uint256) {
        return IERC20(USDC).balanceOf(address(this));
    }

    /**
     * @notice Recover stuck tokens (emergency only)
     */
    function recoverToken(
        address _token,
        address _to,
        uint256 _amount
    ) external onlyOwner {
        IERC20(_token).safeTransfer(_to, _amount);
    }
}
