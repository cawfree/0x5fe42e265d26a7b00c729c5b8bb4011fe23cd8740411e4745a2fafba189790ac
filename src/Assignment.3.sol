// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.20;

import {ERC20} from "@openzeppelin-contracts/token/ERC20/ERC20.sol";
import {IERC20} from "@openzeppelin-contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin-contracts/token/ERC20/utils/SafeERC20.sol";
import {Math} from "@openzeppelin-contracts/utils/math/Math.sol";
import {ReentrancyGuard} from "@openzeppelin-contracts/utils/ReentrancyGuard.sol";

/**
 * @title Assignment3
 * @author cawfree
 * @notice A fixed exchange rate token swap pool. Due to the
 * fixed exchange rate, this kind of pool can be completely
 * drained in leiu of any incentive mechanism to promote
 * rebalancing.
 * 
 * Compared to my first attempt, this contains the following
 * improvements:
 * 1. Fee accrual in exchange for LP smart contract risk. In
 *    particular, the fees will be correctly reflected in share
 *    value, as opposed to the previous implementation which
 *    would allow new LPs to siphon fees from existing LPs.
 * 2. Removal of required approvals for LPs/Swappers, reducing 
 *    total smart contract risk and increasing robustness
 *    in the face of imbalanced reserves.
 * 3. Compatibility with for FEE_ON_TRANSFER tokens.
 */
contract Assignment3 is ReentrancyGuard, ERC20 {

    using SafeERC20 for IERC20;

    /**
     * Emitted when a pool is drained.
     * @param token The token which is no longer available.
     */
    event Drained(address token);

    /**
     * @dev Thrown when invalid tokens are specified
     * when allocating a pool.
     */
    error InvalidTokens();

    /**
     * @dev Thrown when an invalid unit is specified
     * for basis points, which are permitted to be
     * between 0 and 10_000, inclusive.
     * @param bp The invalid unit specified.
     */
    error InvalidBasisPoints(uint256 bp);

    /**
     * @dev Thrown when a mint, burn or swap
     * operation fails to complete due to
     * insufficient assets.
     */
    error InsufficientLiquidity();

    /**
     * @notice For transparency, we'll allow users to
     * introspect the pool variables and ensure they
     * agree to the terms of the swap.
     */
    IERC20  public immutable _TOKEN_0;
    IERC20  public immutable _TOKEN_1;
    uint256 public immutable _EXCHANGE_RATE_1_FOR_0 /* wei */;
    uint256 public immutable _LOCKED_LIQUIDITY;
    uint256 public immutable _SWAP_FEE_BP;

    /**
     * @dev Internal accounting to track known liquidity, ensuring
     * the value of shares cannot be diluted through malicious
     * token donation. In curve-based AMMs, this would also prevent
     * price manipulation, however we are using a fixed exchange rate
     * with zero implied price slippage, so this is not a concern.
     */
    uint256 internal _reserves0;
    uint256 internal _reserves1;

    /**
     * @param name Name of the liquidity tokens.
     * @param symbol Symbol of the liquidity tokens.
     * @param token0 Base token.
     * @param token1 Quote token.
     * @param exchangeRate1For0 The linear exchange
     * rate - how much token1 you exchange for token0. 
     * @param lockedLiquidity - How many liquidity
     * shares to mint on initialization to prevent
     * inflation attacks or excessive pricing.
     * @param swapFeeBp The swap fee to take on
     * inbound tokens during swaps, in basis points.
     */
    constructor(
        string memory name,
        string memory symbol,
        IERC20 token0,
        IERC20 token1,
        uint256 exchangeRate1For0,
        uint256 lockedLiquidity,
        uint256 swapFeeBp
    ) ERC20(name, symbol) {

        /// @dev Prevent zero addresses.
        if (address(token0) == address(0)) revert InvalidTokens();
        if (address(token1) == address(0)) revert InvalidTokens();

        /**
         * @dev Ensure we are swapping between different
         * tokens.
         */
        if (address(token0) == address(token1)) revert InvalidTokens();

        _TOKEN_0 = token0;
        _TOKEN_1 = token1;
        _LOCKED_LIQUIDITY = lockedLiquidity;

        // @dev Similarly to malicious fees, this pool permits
        // malicious exchange rates.
        _EXCHANGE_RATE_1_FOR_0 = exchangeRate1For0;

        /**
         * @dev The `swapFeeBp` decides how much capital from
         * inbound swaps is set aside for LPs.
         * 
         * Warning! This pool enables both totally altrustic
         * (`0`) and totally malicious (`10_000`) fee settings.
         * 
         * A common value to use would be around `30` ~0.3%.
         * 
         */
        if (swapFeeBp > 10_000) revert InvalidBasisPoints(swapFeeBp);

        _SWAP_FEE_BP = swapFeeBp;
    }

    /**
     * @param recipient Account who receives the minted liquidity tokens.
     * @param minLiquidity The minimum amount of liquidity the `recipient`
     * should be minted. Helps counteract griefing through token donation.
     */
    // slither-disable-next-line incorrect-equality
    function mint(address recipient, uint256 minLiquidity) external nonReentrant returns (uint256 liquidity) {

        /**
         * @dev Fetch the current balance. Our expectation here is
         * the caller has populated the pool with the liquidity they
         * intend to provide. We can also account for malicious token
         * donations too - malicious donations will get locked into
         * the reserves, and we will only mint shares in proportion
         * to the smallest amount.
         */
        uint256 balance0 = _TOKEN_0.balanceOf(address(this));
        uint256 balance1 = _TOKEN_1.balanceOf(address(this));

        uint256 amount0In = balance0 - _reserves0;
        uint256 amount1In = balance1 - _reserves1;

        /// @dev Ensure a non-zero deposit has been allocated.
        if (amount0In == 0 || amount1In == 0) revert InsufficientLiquidity();

        // Fetch the current number of shares minted.
        uint256 _totalSupply = totalSupply();

        /**
         * @dev The initialization phase is important. To prevent
         * an attacker from controlling a significant portion of
         * illiquid shares, upon initialization, we must lock
         * some of the underlying liquidity to prevent inflation
         * attacks or outpricing new entrants to the pool.
         */
        if (_totalSupply == 0) {

            /**
             * @dev This is inspired by Uniswap. Here, we use
             * the geometric mean to reduce the impact of wildly
             * imbalanced initial liquidity deposits.
             */
            liquidity = Math.sqrt(amount0In * amount0In + amount1In * amount1In) - _LOCKED_LIQUIDITY;

            /// @dev Lock the initial liquidity to the dead address.
            _mint(0x000000000000000000000000000000000000dEaD, _LOCKED_LIQUIDITY);

        } else {

            /**
             * @dev Again, inspiration from Uniswap. To incentivise
             * against the donation of imbalanced liquidity, we'll
             * only mint the smallest number of shares for either
             * asset. Imbalanced liquidity will drive an increase in
             * the value of existing shares at an attacker's expense.
             * Importantly, without explicit approvals from the LP
             * we can't pull in the exact token ratios required, but
             * our pool logic needs to be resistant to such kinds of
             * imbalances anyway.
             */
            liquidity = Math.min(
                amount0In * _totalSupply / _reserves0,
                amount1In * _totalSupply / _reserves1
            );

        }

        // If insufficient shares could be minted, revert.
        if (liquidity < minLiquidity) revert InsufficientLiquidity();

        /// @dev Mint the recipient their share of the liquidity.
        _mint(recipient, liquidity);

        /// @dev Update the reserves to track *known* liquidity.
        _updateReserves(balance0, balance1);

    }

    /**
     * @notice Performs a token swap. Tokens are swapped according to
     * a fixed exchange rate, and are subject to pool-specific fees
     * for liquidity providers.
     * @param recipient Receiving account for the swap.
     */
    // slither-disable-next-line divide-before-multiply
    function swap(address recipient) external nonReentrant returns (uint256 amount0Out, uint256 amount1Out) {

        /**
         * @dev Fetch our current token balances. The caller
         * is expected to have deposited the assets needed
         * to execute the swap first.
         */
        uint256 balance0 = _TOKEN_0.balanceOf(address(this));
        uint256 balance1 = _TOKEN_1.balanceOf(address(this));

        /**
         * @dev Determine the number of tokens that have been deposited
         * over the reserves - this will define how much to swap. We also
         * diminish the input amounts by the `_SWAP_FEE_BP` to accumulate
         * rewards for liquidity providers.
         */
        uint256 amount0In = (balance0 - _reserves0) * (10_000 - _SWAP_FEE_BP) / 10_000;
        uint256 amount1In = (balance1 - _reserves1) * (10_000 - _SWAP_FEE_BP) / 10_000;

        /**
         * @dev Calculate the required output tokens for the specified input amounts.
         */
        amount0Out = amount1In * _EXCHANGE_RATE_1_FOR_0 / 1e18;
        amount1Out = amount0In * 1e18 / _EXCHANGE_RATE_1_FOR_0;

        /**
         * @dev Revert if the pool cannot fulfill the obligations of
         * the fixed exchange rate.
         */
        if (amount0Out > _reserves0 || amount1Out > _reserves1)
          revert InsufficientLiquidity();

        /// @dev Return token0 in exchange for token1.
        if (amount0Out > 0) _TOKEN_0.safeTransfer(recipient, amount0Out);

        /// @dev Return token1 in exchange for token0.
        if (amount1Out > 0) _TOKEN_1.safeTransfer(recipient, amount1Out);

        /**
         * Finally, update reserves. We'll measure the
         * exact balance to ensure our accounting isn't
         * broken with respect to FEE_ON_TRANSFER tokens.
         */
        _updateReserves(_TOKEN_0.balanceOf(address(this)), _TOKEN_1.balanceOf(address(this)));

    }

    /**
     * @param recipient Address to transfer liquidity to.
     */
    // slither-disable-next-line incorrect-equality
    function burn(address recipient) external nonReentrant returns (uint256 amount0Out, uint256 amount1Out) {

        /**
         * @dev Fetch the number of shares that have been deposited
         * into the contract. We take care not to merely burn shares
         * on a caller's behalf, they must be intentionally placed
         * here. I took inspiration for this from the UniswapV2 book.
         */
        uint256 shares = balanceOf(address(this));

        // Fetch the total number of shares.
        uint256 _totalSupply = totalSupply();

        // If no shares have been provided, revert.
        if (shares == 0) revert InsufficientLiquidity();

        /// @dev Remove the shares from distribution.
        _burn(address(this), shares); 

        // Fetch our current balance.
        uint256 balance0 = _TOKEN_0.balanceOf(address(this));
        uint256 balance1 = _TOKEN_1.balanceOf(address(this));

        /**
         * @dev Calculate the ownership of the total
         * underlying liquidity, including fees.
         */
        unchecked {
            amount0Out = (balance0 * shares) / _totalSupply;
            amount1Out = (balance1 * shares) / _totalSupply;
        }

        // Transfer redeemable `token0`.
        if (amount0Out > 0) _TOKEN_0.safeTransfer(recipient, amount0Out);

        // Transfer redeemable `token1`.
        if (amount1Out > 0) _TOKEN_1.safeTransfer(recipient, amount1Out);

        /**
         * @dev In the case of FEE_ON_TRANSFER tokens,
         * we'll update the current balance to avoid
         * incorrect accounting after the transfer
         * has taken place.
         */
        _updateReserves(_TOKEN_0.balanceOf(address(this)), _TOKEN_1.balanceOf(address(this)));

    }

    /** @dev Updates the pool to track the known reserves. */
    // slither-disable-next-line incorrect-equality
    function _updateReserves(uint256 balance0, uint256 balance1) internal {
        _reserves0 = balance0;
        _reserves1 = balance1;

        if (_reserves0 == 0) emit Drained(address(_TOKEN_0));

        if (_reserves1 == 0) emit Drained(address(_TOKEN_1));

    }

}
