// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

/**
 * @title IMockMessageProxyForMainnet
 * @notice Interface for the MessageProxy mock used in tests.
 */
interface IMockMessageProxyForMainnet {
    /**
     * @notice Sets connectivity status for a SKALE chain name.
     * @param schainName The SKALE chain name.
     * @param isConnected True if the chain should be treated as connected.
     */
    function setConnectedChain(string calldata schainName, bool isConnected) external;

    /**
     * @notice Returns whether a SKALE chain is connected.
     * @param schainName The SKALE chain name.
     * @return connected True if the chain is connected.
     */
    function isConnectedChain(string calldata schainName) external view returns (bool connected);
}

/**
 * @title MockMessageProxyForMainnet
 * @notice Mock implementation of the MessageProxyForMainnet used in tests.
 */
contract MockMessageProxyForMainnet is IMockMessageProxyForMainnet {
    mapping(string chainName => bool connected) private _connectedChains;

    /// @inheritdoc IMockMessageProxyForMainnet
    function setConnectedChain(string calldata schainName, bool isConnected) external override {
        _connectedChains[schainName] = isConnected;
    }

    /// @inheritdoc IMockMessageProxyForMainnet
    function isConnectedChain(string calldata schainName) external view override returns (bool connected) {
        return _connectedChains[schainName];
    }
}
