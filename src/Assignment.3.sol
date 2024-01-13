// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.13;

import {ERC20} from "@openzeppelin-contracts/token/ERC20/ERC20.sol";
import {IERC20} from "@openzeppelin-contracts/token/ERC20/IERC20.sol";
import {IERC20Metadata} from "@openzeppelin-contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {IERC721} from "@openzeppelin-contracts/token/ERC721/IERC721.sol";
import {SafeERC20} from "@openzeppelin-contracts/token/ERC20/utils/SafeERC20.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";

/**
 * @title Assignment3
 * @author cawfree
 * @notice A naive fixed-rate token swap contract. Note, a fixed
 * exchange rate pool has a couple of downsides versus conventional
 * AMMs. For example, it does not follow the laws of supply and
 * demand, leading to excessive IL. Additionally, this pool can
 * be drained of capital, reducing liveliness, as there is no
 * incentive mechanism for participants to take the opposing side
 * and rebalance the pool. One of the positive attributes of this
 * kind of pool is we don't have to worry about price slippage,
 * which reduces trader exposure to MEV.
 * @dev Fees have not been incorporated here to meet the design
 * spec, however the implementation model is resistant to balance
 * manipulation exploits, and would therefore be compatible with
 * siphoning fees from inbound swaps.
 */
contract Assignment3 is ERC20 {

    /**
     * @dev Emitted when the pool is drained for a given token.
     * Since we are using a linear exchange rate, it is possible
     * to empty the pool entirely. AMMs like UniswapV2 use a
     * curve which never crosses cartesian axes - this ensures the
     * pool may never be totally drained, and instead induces incentives
     * for the pool's balance to be refilled.
     * 
     * Nothing like that here, though!
     */
    event Drained(address token);

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
     * @dev Defines the initial amount of liquidity that must be burned
     * to avoid excessively small amounts of initial token issuance, which
     * can be gamed by attackers through share inflation.
     */
    uint256 private immutable _INITIAL_LIQUIDITY = 1_000;

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
    uint256 private immutable _EXCHANGE_RATE_1_FOR_0 /* in_wei */;

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
        // Wrapped Ether/DAI
        string(abi.encodePacked(IERC20Metadata(token0).name(), "/", IERC20Metadata(token1).name())),
        string(abi.encodePacked(IERC20Metadata(token0).symbol(), "/", IERC20Metadata(token1).symbol()))
    ) {
        _TOKEN_0 = IERC20(token0);
        _TOKEN_1 = IERC20(token1);
        _EXCHANGE_RATE_1_FOR_0 = exchangeRate1For0 /* fixed_linear_exchange_rate */;
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
     * @return mintedLiquidity How much liquidity was minted.
     */
    function mint(uint256 maxToken0, uint256 maxToken1) external returns (uint256 mintedLiquidity) {

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

        /// @dev The initialization phase of any token management is vital.
        if (totalSupply() == 0) {

            /**
             * @dev We want to be resistant to imbalanced initial pool shares,
             * since a greatly imbalanced initial deposit could dilute share
             * value. Using a geometric mean avoids this, since it counteracts
             * extreme differences by giving less weight to extremely high values,
             * and more weight to lower values via reduced sensitivity.
             * 
             * This reduces overall IL for LPs.
             */
            mintedLiquidity =
                Math.sqrt(token0In * token0In + token1In * token1In) - _INITIAL_LIQUIDITY /* checked */;

            /**
             * @dev Lock the initial liquidity. OpenZeppelin's ERC20 library
             * does not permit transfers to the zero address, so for this
             * exercise we'll use the dead address instead. For better gas
             * efficiency and support for transfers to the zero address, we
             * could have used solady. 
             */
            _mint(0x000000000000000000000000000000000000dEaD, _INITIAL_LIQUIDITY);

            // Mint the remaining `mintedLiquidity` to the LP.
            _mint(msg.sender, mintedLiquidity);

        } else {

            uint256 totalSupply = totalSupply();

            /**
             * @dev For non-initial deposits, we can use the lowest of the two
             * amounts to decide how much liquidity to deposit. This avoids
             * incentivising price manipulation through the donation of an
             * inflated asset (relative to the counterparty in the token pair.)
             */
            mintedLiquidity = Math.min(token0In * totalSupply / _reserves0, token1In * totalSupply / _reserves1);

            // Mint the `mintedLiquidity` to the caller.
            _mint(msg.sender, mintedLiquidity);

        }
        
        // Update the token reserves.
        _reserves0 += token0In;
        _reserves1 += token1In;

    }

    /**
     * @dev Swaps `token1` for `token0`. This will try to fulfill the trade
     * to as great an extent as possible using the remaining reserves.
     * @param maxAmountIn The amount of `token1` the user wishes to trade.
     * @return amountOut0 The amount of `token0` received.
     * @return amountIn1 The amount of `token1` deposited into the pool.
     */
    function oneForZero(uint256 maxAmountIn) external returns (uint256 amountOut0, uint256 amountIn1) {

        /**
         * @dev We want to make sure that the amount of token1
         * supplied by the caller can be sustained by the reserves.
         * For the specified `maxAmountIn`, we need to pick
         * the smallest between their desired amount and the maximum
         * amount of token0 we can supply.
         */
        amountOut0 = Math.min(_reserves0, maxAmountIn * _EXCHANGE_RATE_1_FOR_0 / 1e18);

        // If we don't possess sufficient liquidity, revert.
        if (amountOut0 == 0) revert InsufficientLiquidity();

        // Calculate the required amount of `token1` for the given `amountOut0`.
        amountIn1 = amountOut0 * 1e18 / _EXCHANGE_RATE_1_FOR_0;

        // Update token reserves. (Already checked.)
        unchecked {
            _reserves0 -= amountOut0;
            _reserves1 += amountIn1;
        }

        // Accept these tokens from the caller.
        _TOKEN_1.safeTransferFrom(msg.sender, address(this), amountIn1);

        // Emit the tokens.
        _TOKEN_0.safeTransfer(msg.sender, amountOut0); 

        /**
         * @dev If the pool was emptied, emit an event in the hope
         * some byzantine actor will come along and help replenish
         * the pool.
         */
        if (_reserves0 == 0) emit Drained(address(_TOKEN_0));

    }

    /**
     * @dev Swaps an amount of `token0` in exchange for `token1`, following
     * the linear exchange rate.
     * @param maxAmountIn The maximum number of `token0` the caller is wishing
     * to exchange.
     * @return amountIn0 The amount of `token0` which was exchanged.
     * @return amountOut1 The amount of `token1` which was returned.
     */
    function zeroForOne(uint256 maxAmountIn) external returns (uint256 amountIn0, uint256 amountOut1){

        // Compute the amount of token1 we will provide.
        amountOut1 = Math.min(
            _reserves1,
            maxAmountIn * 1e18 / _EXCHANGE_RATE_1_FOR_0
        );

        // If we don't possess sufficient liquidity, revert.
        if (amountOut1 == 0) revert InsufficientLiquidity();

         // Calculate the required amount of `amountIn0` for the given `amountOut1`.
        amountIn0 = amountOut1 * _EXCHANGE_RATE_1_FOR_0 / 1e18;

        /// @dev Update the reserves, (Already checked).
        unchecked {
            _reserves0 += amountIn0;
            _reserves1 -= amountOut1;
        }

        // Accept these tokens from the caller.
        _TOKEN_0.safeTransferFrom(msg.sender, address(this), amountIn0);

        // Emit the tokens.
        _TOKEN_1.safeTransfer(msg.sender, amountOut1);

        /// @dev If reserves are depleted, emit the `Drained` event.
        if (_reserves1 == 0) emit Drained(address(_TOKEN_1));
        
    }

    /**
     * @notice Allows liquidity providers to burn their shares
     * and claim their ownership of the resulting reserves and
     * accumulated fees.
     */
    function burn() external {

        /**
         * @dev The contract will *never* directly burn shares
         * on behalf of users. Instead, the shares must be explicitly
         * transferred here first.
         */
        uint256 shares = balanceOf(address(this));
        uint256 totalSupply = totalSupply();

        // Terminate early if there are no shares to burn.
        if (shares == 0) revert InsufficientLiquidity();

        // Fetch the current token balances.
        uint256 balance0 = _TOKEN_0.balanceOf(address(this));
        uint256 balance1 = _TOKEN_1.balanceOf(address(this));

        /**
         * @dev Determine their deviation from the current reserves.
         * These values would have been accumulated from fees, malicious
         * token donation, etc.
         */
        uint256 amountOut0 = balance0 * shares / totalSupply;
        uint256 amountOut1 = balance1 * shares / totalSupply;

        // Burn the shares provided.
        _burn(address(this), shares);

        /**
         * @dev Reduce the total reserves in the pool independently
         * of the accumulated fees.
         */
        unchecked {
            _reserves0 -= _reserves0 * shares / totalSupply;
            _reserves1 -= _reserves1 * shares / totalSupply;
        }

        // Finally, reward the liquidity provider the proportions
        // of their initial deposits and their fees.
        _TOKEN_0.safeTransfer(msg.sender, amountOut0);
        _TOKEN_1.safeTransfer(msg.sender, amountOut1);

    }

}