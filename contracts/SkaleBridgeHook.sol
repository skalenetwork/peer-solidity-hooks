// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";
import { Ownable2Step } from "@openzeppelin/contracts/access/Ownable2Step.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { EnumerableSet } from "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import { IDepositBoxERC20 } from "@skalenetwork/ima-interfaces/mainnet/DepositBoxes/IDepositBoxERC20.sol";
import { IMessageProxyForMainnet } from "@skalenetwork/ima-interfaces/mainnet/IMessageProxyForMainnet.sol";
import { IPostIntentHookV2 } from "./interfaces/IPostIntentHookV2.sol";
import { ISkaleBridgeHook } from "./interfaces/ISkaleBridgeHook.sol";

/**
 * @title SkaleBridgeHook
 * @notice Post-intent hook that bridges ERC20 tokens from Base to SKALE Base
 * @dev Uses SKALE's IMA smart contracts for token bridging
 */
contract SkaleBridgeHook is ISkaleBridgeHook, Ownable2Step {
    using SafeERC20 for IERC20;
    using EnumerableSet for EnumerableSet.AddressSet;

    /// @notice Peer.xyz OrchestratorV2 on Base
    address public immutable ORCHESTRATOR;

    /// @notice DepositBox contract for bridging (if available on Base)
    IDepositBoxERC20 public immutable DEPOSIT_BOX;

    /// @notice The SKALE chain name hash that this hook is associated with
    string public skaleChainName;

    EnumerableSet.AddressSet private _whitelistedTokens;

    /// @notice Emitted when a token is whitelisted for bridging
    /// @param token The address of the token that was whitelisted
    event TokenWhitelisted(address indexed token);

    /// @notice Emitted when a token is removed from the whitelist
    /// @param token The address of the token that was removed from the whitelist
    event TokenRemovedFromWhitelist(address indexed token);

    error OnlyOrchestrator();
    error InvalidAddress(address addr);
    error InvalidSourceChain();
    error TokenNotAllowedForSchain(string schainName, address token);

    modifier onlyOrchestrator() {
        require(msg.sender == ORCHESTRATOR, OnlyOrchestrator());
        _;
    }

    constructor(address _orchestrator, address _depositBox, address _messageProxy, string memory _skaleChainName)
        Ownable(msg.sender)
    {
        require(_orchestrator != address(0), InvalidAddress(_orchestrator));
        require(_messageProxy != address(0), InvalidAddress(_messageProxy));
        require(IMessageProxyForMainnet(_messageProxy).isConnectedChain(_skaleChainName), InvalidSourceChain());
        ORCHESTRATOR = _orchestrator;
        DEPOSIT_BOX = IDepositBoxERC20(_depositBox);
        skaleChainName = _skaleChainName;
    }

    /// @notice Add a token to the whitelist
    /// @param token The address of the token to whitelist
    function addTokenToWhitelist(address token) external override onlyOwner {
        require(token != address(0), InvalidAddress(token));
        if (_whitelistedTokens.add(token)) {
            emit TokenWhitelisted(token);
        }
    }

    /// @notice Remove a token from the whitelist
    /// @param token The address of the token to remove from the whitelist
    function removeTokenFromWhitelist(address token) external override onlyOwner {
        require(token != address(0), InvalidAddress(token));
        if (_whitelistedTokens.remove(token)) {
            emit TokenRemovedFromWhitelist(token);
        }
    }

    /// @inheritdoc IPostIntentHookV2
    function execute(HookExecutionContext calldata ctx, bytes calldata fulfillHookData)
        external
        override
        onlyOrchestrator
    {
        // TODO: We can do more stuff here - support passing chain name, suport taking a fee, etc.
        // Get recipient - allow override via fulfillHookData
        address recipient = ctx.intent.to;
        if (fulfillHookData.length > 31) {
            (address overrideRecipient) = abi.decode(fulfillHookData, (address));
            if (overrideRecipient != address(0)) {
                recipient = overrideRecipient;
            }
        }

        // No logic is based on time
        emit BridgeInitiated(
            ctx.intentHash,
            recipient,
            ctx.executableAmount,
            // solhint-disable-next-line not-rely-on-time
            block.timestamp
        );

        _depositToSkale(recipient, ctx.token, skaleChainName, ctx.executableAmount);
    }

    /// @inheritdoc ISkaleBridgeHook
    function getWhitelistedTokensLength() external view override returns (uint256 size) {
        return _whitelistedTokens.length();
    }

    /// @inheritdoc ISkaleBridgeHook
    function getWhitelistedTokenAt(uint256 index) external view override returns (address token) {
        return _whitelistedTokens.at(index);
    }

    function _depositToSkale(address recipient, address token, string memory chainName, uint256 amount) private {
        // Pull tokens from orchestrator
        IERC20(token).safeTransferFrom(ORCHESTRATOR, address(this), amount);

        /// @dev Force that IMA requires a whitelist or the token is whitelisted on this contract
        require(
            DEPOSIT_BOX.isWhitelisted(chainName) || _whitelistedTokens.contains(token),
            TokenNotAllowedForSchain(chainName, token)
        );

        IERC20(token).forceApprove(address(DEPOSIT_BOX), amount);

        // Call depositERC20Direct
        DEPOSIT_BOX.depositERC20Direct(chainName, token, amount, recipient);
    }
}
