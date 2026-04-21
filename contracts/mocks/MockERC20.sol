// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

/**
 * @title IMockERC20
 * @notice Interface for the ERC20 mock used in tests.
 */
interface IMockERC20 {
    /**
     * @notice Mints tokens to a given address.
     * @param to Recipient of the minted tokens.
     * @param amount Amount of tokens to mint.
     */
    function mint(address to, uint256 amount) external;
}

/**
 * @title MockERC20
 * @notice Minimal ERC20 token with a public mint function for testing.
 */
contract MockERC20 is IMockERC20, ERC20 {
    constructor(string memory name, string memory symbol) ERC20(name, symbol) { }

    /// @inheritdoc IMockERC20
    function mint(address to, uint256 amount) external override {
        _mint(to, amount);
    }
}
