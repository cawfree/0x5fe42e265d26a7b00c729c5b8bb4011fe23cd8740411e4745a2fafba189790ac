// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.13;

import {ERC20} from "@openzeppelin-contracts/token/ERC20/ERC20.sol";
import {IERC20} from "@openzeppelin-contracts/token/ERC20/IERC20.sol";
import {IERC20Metadata} from "@openzeppelin-contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {IERC721} from "@openzeppelin-contracts/token/ERC721/IERC721.sol";
import {SafeERC20} from "@openzeppelin-contracts/token/ERC20/utils/SafeERC20.sol";

/**
 * @title Assignment3
 * @author cawfree
 * @notice A naive fixed-rate token swap contract.
 */
contract Assignment3 is ERC20 {

    /**
     * @dev Thrown when a fee on transfer token is detected.
     */
    error FeeOnTransferTokensUnsupported();

    /**
     * @dev Thrown when a liquidity provider is unable to provide
     * sufficient liquidity.
     */
    error InsufficientLiquidity();

    /**
     * @dev We use `SafeERC20` for `IERC20`s to ensure
     * that our transactions with ERC20s are normalized,
     * so we can ensure wide compatibility and implement
     * a consistent interface for error handling.
     */
    using SafeERC20 for IERC20;

    IERC20 private immutable _TOKEN_0;
    IERC20 private immutable _TOKEN_1;

    /**
     * @dev Defines the fixed exchange rate - how much of token0
     * one should receive for an input amount of token1.
     */
    uint256 private immutable _EXCHANGE_RATE_1_FOR_0;

    /**
     * @dev Token reserves. To ensure swap logic cannot
     * be manipulated through donation, we track the known reserves
     * manually.
     */
    uint256 private _reserves0;
    uint256 private _reserves1;

    /**
     * @param token0 The base token.
     * @param token1 The quote token.
     * @param exchangeRate1For0 How much token1 is required for token0.
     */
    constructor(address token0, address token1, uint256 exchangeRate1For0) ERC20(
        string(abi.encodePacked(IERC20Metadata(token0).name(), "/", IERC20Metadata(token1).name())),
        string(abi.encodePacked(IERC20Metadata(token0).symbol(), "/", IERC20Metadata(token1).symbol()))
    ) {
        _TOKEN_0 = IERC20(token0);
        _TOKEN_1 = IERC20(token1);
        _EXCHANGE_RATE_1_FOR_0 = exchangeRate1For0;
    }

    /**
     * @notice Enables liquidity provision to the pool, which
     * is represented using pool shares, which may be burned
     * to redeem fees.
     * @dev Callers must approve the pool to spend both `_TOKEN_0`
     * and `_TOKEN_1`.
     * @param maxToken0 The maximum amount of token0 the
     * caller wishes to provide.
     * @param maxToken1 The maximum amount of token1 the
     * caller wishes to provide.
     */
    function deposit(uint256 maxToken0, uint256 maxToken1) external {

        // For the specified amount of maxToken1, determine
        // how much token0 would be required from the caller.
        uint256 inferredToken0 = maxToken1 * _EXCHANGE_RATE_1_FOR_0 / 1e18;

        // Given the constraints, determine how much `token0In`
        // and `token1In` should be pulled in from the caller.
        uint256 token0In = maxToken0 < inferredToken0
            ? maxToken0
            : inferredToken0;

        uint256 token1In = token0In * 1e18 / _EXCHANGE_RATE_1_FOR_0;

        /**
         * @dev To avoid rounding errors, ensure that both `token0In` and `token1In`
         * are nonzero - this will guarantee we have received liquidity in the proper
         * proportions.
         */
        if (token0In == 0 || token1In == 0) revert InsufficientLiquidity();

        uint256 token0BalanceBefore = _TOKEN_0.balanceOf(address(this));
        uint256 token1BalanceBefore = _TOKEN_1.balanceOf(address(this));

        // Transfer the tokens in.
        _TOKEN_0.safeTransferFrom(msg.sender, address(this), token0In);
        _TOKEN_1.safeTransferFrom(msg.sender, address(this), token1In);

        // Prevent `_TOKEN_0` from being a fee on transfer token.
        if (_TOKEN_0.balanceOf(address(this)) - token0BalanceBefore != token0In)
            revert FeeOnTransferTokensUnsupported();

        // Prevent `_TOKEN_1` from being a fee on transfer token.
        if (_TOKEN_1.balanceOf(address(this)) - token1BalanceBefore != token1In)
            revert FeeOnTransferTokensUnsupported();

        // Update the token reserves.
        _reserves0 += token0In;
        _reserves1 += token1In;

        // Finally, we denominate liquidity provider shares in
        // terms of the base token.
        _mint(msg.sender, token0In);

    }

    /**
     * @param shares The number of pool shares to liquidate.
     */
    function liquidate(uint256 shares) external {
        /**
         * @dev The contract will not burn shares on the callers behalf,
         * instead, the shares must be approved and transferred here first.
         */
        IERC20(this).safeTransferFrom(msg.sender, address(this), shares);

        // Burn the shares provided.
        _burn(address(this), shares);

    }

}