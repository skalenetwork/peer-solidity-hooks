// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

/**
 * @title IMockDepositBoxERC20
 * @notice Interface for the DepositBox ERC20 mock used in tests.
 */
interface IMockDepositBoxERC20 {
    /**
     * @notice Emitted when a token deposit flow is considered ready in the mock.
     * @param token The mainnet ERC20 token address.
     * @param amount The deposited token amount.
     */
    event ERC20TokenReady(address indexed token, uint256 indexed amount);

    /**
     * @notice Sets a token mapping between mainnet and a specific SKALE chain.
     * @param erc20OnMainnet The mainnet ERC20 token address.
     * @param schainName The target SKALE chain name.
     * @param erc20OnSchain The corresponding token address on the SKALE chain.
     */
    function setTokenMapping(address erc20OnMainnet, string calldata schainName, address erc20OnSchain) external;

    /**
     * @notice Enables or disables whitelist mode for a specific SKALE chain.
     * @param schainName The target SKALE chain name.
     * @param enabled True to enable whitelist mode, false to disable it.
     */
    function setWhitelistEnabled(string calldata schainName, bool enabled) external;

    /**
     * @notice Simulates a direct ERC20 deposit into the DepositBox.
     * @param schainName The target SKALE chain name.
     * @param erc20OnMainnet The mainnet ERC20 token address.
     * @param amount The token amount to deposit.
     * @param receiver The target receiver address on the destination chain.
     */
    function depositERC20Direct(
        string calldata schainName,
        address erc20OnMainnet,
        uint256 amount,
        address receiver
    )
        external;

    /**
     * @notice Returns whether whitelist mode is enabled for the chain.
     * @param schainName The SKALE chain name.
     * @return whitelisted True when whitelist mode is enabled.
     */
    function isWhitelisted(string memory schainName) external view returns (bool whitelisted);
}

/**
 * @title MockDepositBoxERC20
 * @notice Mock implementation of the IMA DepositBoxERC20 used in tests.
 */
contract MockDepositBoxERC20 is IMockDepositBoxERC20 {
    using SafeERC20 for IERC20;

    /// @notice Mapping of mainnet token to SKALE chain to token on SKALE chain
    mapping(address token => mapping(bytes32 schainName => address tokenOnSchain)) public tokenMappings;

    /// @notice Mapping to track whether whitelist mode is enabled for a given SKALE chain
    mapping(bytes32 schainHash => bool enabled) private _whitelistEnabled;

    error WhitelistEnabled(string schainName);

    /// @inheritdoc IMockDepositBoxERC20
    function setTokenMapping(
        address erc20OnMainnet,
        string calldata schainName,
        address erc20OnSchain
    )
        external
        override
    {
        tokenMappings[erc20OnMainnet][keccak256(abi.encodePacked(schainName))] = erc20OnSchain;
    }

    /// @inheritdoc IMockDepositBoxERC20
    function setWhitelistEnabled(string calldata schainName, bool enabled) external override {
        _whitelistEnabled[keccak256(abi.encodePacked(schainName))] = enabled;
    }

    /// @inheritdoc IMockDepositBoxERC20
    function depositERC20Direct(
        string calldata schainName,
        address erc20OnMainnet,
        uint256 amount,
        address
    )
        external
        override
    {
        // Mocks real functionality of depositBockERC20Direct
        if (tokenMappings[erc20OnMainnet][keccak256(abi.encodePacked(schainName))] == address(0)) {
            require(!isWhitelisted(schainName), WhitelistEnabled(schainName));

            // If we hit this line, a new token may be created on the destination chain
            // We should not allow it - should be impossible to hit this line
            assert(false);
        } else {
            IERC20(erc20OnMainnet).safeTransferFrom(msg.sender, address(this), amount);
        }
        emit ERC20TokenReady(erc20OnMainnet, amount);
    }

    /// @inheritdoc IMockDepositBoxERC20
    function isWhitelisted(string memory schainName) public view override returns (bool whitelisted) {
        return _whitelistEnabled[keccak256(abi.encodePacked(schainName))];
    }
}
