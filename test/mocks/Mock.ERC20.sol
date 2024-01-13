// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.13;

import {ERC20} from "@openzeppelin-contracts/token/ERC20/ERC20.sol";

/**
 * @title MockERC20
 * @author cawfree
 * @notice An ERC-20 token for playing around with.
 */
contract MockERC20 is ERC20 {

    /**
     * @param symbol A mock token namespace.
     */
    constructor(string memory symbol) ERC20(string(abi.encodePacked("Mock", symbol)), symbol) {}

    /**
     * @dev Mints tokens to a recipient.
     * @param recipient Recipient of the minted amount.
     * @param amount Number of tokens to mint.
     */
    function mint(address recipient, uint256 amount) external {
        _mint(recipient, amount);
    }

}