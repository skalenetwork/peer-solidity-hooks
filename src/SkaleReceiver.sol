// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

/**
 * @title SkaleReceiver
 * @notice Receives IMA messages from Base post-intent hook
 * @dev Must be registered with MessageProxy EXTRA_CONTRACT_REGISTRAR_ROLE
 */
contract SkaleReceiver {
    using SafeERC20 for IERC20;

    /// @notice MessageProxy on SKALE Base (standard address)
    address public constant MESSAGE_PROXY =
        0xd2AAa00100000000000000000000000000000000;

    /// @notice Mapped USDC on SKALE Base
    /// SKALE Base Sepolia: 0x2e08028E3C4c2356572E096d8EF835cD5C6030bD
    address public immutable mappedUsdc;

    /// @notice Contract owner
    address public immutable owner;

    /// @notice Track pending releases for security
    mapping(bytes32 => bool) public processedMessages;

    event BridgeNotificationReceived(
        bytes32 indexed intentHash,
        address indexed recipient,
        address token,
        uint256 amount,
        uint256 timestamp
    );

    event TokensReleased(
        bytes32 indexed intentHash,
        address indexed recipient,
        uint256 amount
    );

    event ContractFunded(
        address indexed funder,
        uint256 amount
    );

    error OnlyMessageProxy();
    error OnlyOwner();
    error MessageAlreadyProcessed();
    error InsufficientBalance();

    modifier onlyMessageProxy() {
        if (msg.sender != MESSAGE_PROXY) revert OnlyMessageProxy();
        _;
    }

    modifier onlyOwner() {
        if (msg.sender != owner) revert OnlyOwner();
        _;
    }

    constructor(address _mappedUsdc) {
        mappedUsdc = _mappedUsdc;
        owner = msg.sender;
    }

    /**
     * @notice Called by IMA Agent when message arrives from Base
     * @param id Message ID
     * @param sender Contract address on source chain
     * @param data Encoded message data
     */
    function postMessage(
        bytes32 id,
        address sender,
        bytes calldata data
    ) external onlyMessageProxy returns (address) {
        // Prevent replay attacks
        if (processedMessages[id]) revert MessageAlreadyProcessed();
        processedMessages[id] = true;

        // Decode: (bytes32 intentHash, address recipient, address token, uint256 amount)
        (
            bytes32 intentHash,
            address recipient,
            address token,
            uint256 amount
        ) = abi.decode(data, (bytes32, address, address, uint256));

        emit BridgeNotificationReceived(
            intentHash,
            recipient,
            token,
            amount,
            block.timestamp
        );

        // Process the bridge notification
        _processBridgeNotification(intentHash, recipient, amount);

        return address(this);
    }

    /**
     * @notice Process incoming bridge notification
     * @dev This is where tokens would be released to the recipient
     */
    function _processBridgeNotification(
        bytes32 _intentHash,
        address _recipient,
        uint256 _amount
    ) internal {
        // Check if contract has enough balance
        uint256 balance = IERC20(mappedUsdc).balanceOf(address(this));
        if (balance < _amount) {
            // Insufficient balance - emit event for manual processing
            // In production, this could trigger an oracle/relayer to refill
            return;
        }

        // Release tokens to recipient
        IERC20(mappedUsdc).safeTransfer(_recipient, _amount);

        emit TokensReleased(_intentHash, _recipient, _amount);
    }

    /**
     * @notice Admin function to fund contract with mapped USDC
     */
    function fund() external payable {
        // Accept native tokens if needed for gas
        emit ContractFunded(msg.sender, msg.value);
    }

    /**
     * @notice Admin function to fund with mapped USDC
     */
    function fundUsdc(uint256 _amount) external {
        IERC20(mappedUsdc).safeTransferFrom(msg.sender, address(this), _amount);
        emit ContractFunded(msg.sender, _amount);
    }

    /**
     * @notice Admin function to manually release tokens to recipient
     * @dev Use this for manual processing if automated release fails
     */
    function releaseTokens(
        address _recipient,
        uint256 _amount
    ) external onlyOwner {
        IERC20(mappedUsdc).safeTransfer(_recipient, _amount);
    }

    /**
     * @notice View available USDC balance
     */
    function availableBalance() external view returns (uint256) {
        return IERC20(mappedUsdc).balanceOf(address(this));
    }

    /**
     * @notice Allow contract to receive mapped USDC
     */
    receive() external payable {}
}
