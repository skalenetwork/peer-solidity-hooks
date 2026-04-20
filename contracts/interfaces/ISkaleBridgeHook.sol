// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import { IPostIntentHookV2 } from "./IPostIntentHookV2.sol";

/// @title Skale Bridge Hook Interface
/// @notice Adds whitelist functionality (optional) for the safe integration with SKALE IMA
interface ISkaleBridgeHook is IPostIntentHookV2 {
    /// @notice Emitted when a bridge is initiated from Base to SKALE
    /// @param intentHash The hash of the fulfilled intent that triggered the bridge
    /// @param recipient The final recipient on SKALE Base
    /// @param amount The amount of tokens to be bridged
    /// @param timestamp The time at which the bridge was initiated
    event BridgeInitiated(
        bytes32 indexed intentHash, address indexed recipient, uint256 indexed amount, uint256 timestamp
    );

    /// @notice Add a token to the whitelist
    /// @param token The address of the token to whitelist
    function addTokenToWhitelist(address token) external;

    /// @notice Remove a token from the whitelist
    /// @param token The address of the token to remove from the whitelist
    function removeTokenFromWhitelist(address token) external;

    /// @notice Returns amount of tokens whitelisted
    /// @return size number of whitelisted tokens
    function getWhitelistedTokensLength() external view returns (uint256 size);

    /// @notice Returns token at index in whitelist
    /// @param index The index in the whitelist to query
    /// @return token The address of the whitelisted token at the index
    function getWhitelistedTokenAt(uint256 index) external view returns (address token);
}
