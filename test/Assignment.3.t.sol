// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.13;

import {console} from "forge-std/console.sol";
import {Math} from "@openzeppelin-contracts/utils/math/Math.sol";

import {MockERC20} from "./mocks/Mock.ERC20.sol";

import {BaseTest} from "./utils/BaseTest.t.sol";

import {Assignment3} from "../src/Assignment.3.sol";

contract Assignment3Test is BaseTest {

    /**
     * @dev Sanity checks for liquidity provider position
     * mint/burn mechanics. Uses simple equal positions.
     */
    function test_simpleMintAndBurn() public {

        MockERC20 token0 = new MockERC20("Token0");
        MockERC20 token1 = new MockERC20("Token1");

        Assignment3 pool = new Assignment3(
            address(token0),
            address(token1),
            1e18 /* 1-for-1 */
        );

        token0.mint(address(this), 1 ether);
        token1.mint(address(this), 1 ether);

        token0.approve(address(pool), type(uint256).max);
        token1.approve(address(pool), type(uint256).max);

        uint256 mintedLiquidity = pool.mint(1 ether, 1 ether);

        assertEq(token0.balanceOf(address(this)), 0);
        assertEq(token1.balanceOf(address(this)), 0);

        assertEq(token0.balanceOf(address(pool)), 1 ether);
        assertEq(token1.balanceOf(address(pool)), 1 ether);

        assertEq(pool.balanceOf(address(this)), mintedLiquidity);
        assertEq(pool.balanceOf(_DEAD_ADDRESS), 1_000);

        vm.expectRevert(abi.encodeWithSignature("InsufficientLiquidity()"));
            pool.burn();

        pool.transfer(address(pool), mintedLiquidity);
        pool.burn();

        // Tokens should be redeemed back in equal portions.
        assertEq(token0.balanceOf(address(this)), token1.balanceOf(address(this)));

        // Some liquidity should remain locked.
        assertTrue(token0.balanceOf(address(pool)) > 0);
        assertTrue(token1.balanceOf(address(pool)) > 0);

        // By pranking as the dead address, we can assure the liquidity
        // can be burned completely.
        vm.startPrank(_DEAD_ADDRESS);
            pool.transfer(address(pool), 1_000);
            pool.burn();
        vm.stopPrank();

        // Ensure all liquidity has been burned.
        assertTrue(token0.balanceOf(address(pool)) == 0);
        assertTrue(token1.balanceOf(address(pool)) == 0);

        // Ensure the sum of all returned balances is expected.
        assertEq(token0.balanceOf(_DEAD_ADDRESS) + token0.balanceOf(address(this)), 1 ether);
        assertEq(token1.balanceOf(_DEAD_ADDRESS) + token1.balanceOf(address(this)), 1 ether);

    }

    /**
     * @dev Tests swaps from `token1` to `token0`. We'll use
     * an exchange rate that `token1` is worth half of `token0`.
     */
    function test_zeroForOne() public {

        MockERC20 token0 = new MockERC20("Token0");
        MockERC20 token1 = new MockERC20("Token1");

        Assignment3 pool = new Assignment3(
            address(token0),
            address(token1),
            5e17 /* 2-for-1 */
        );

        // We'll start off with some tokens which represent
        // the desired token balance ratio exactly.
        token0.mint(address(this), 100 ether);
        token1.mint(address(this), 200 ether);

        // Approve the pool.
        token0.approve(address(pool), type(uint256).max);
        token1.approve(address(pool), type(uint256).max);

        // Mint a balanced initial supply.
        pool.mint(100 ether, 200 ether);

        // Okay, let's try to swap some tokens!
        // For 50 of token1, we should expect 25 token0.
        token1.mint(address(this), 50 ether);

        // Swap 50 ether of `token1`. We should receive 25 `token0`.
        pool.oneForZero(50 ether);

        assertEq(token1.balanceOf(address(this)), 0);
        assertEq(token0.balanceOf(address(this)), 25 ether);

        // At this stage, the pool should have `75` ether of
        // `token0` and `250` ether of `token1`.
        assertEq(token0.balanceOf(address(pool)), 75 ether);
        assertEq(token1.balanceOf(address(pool)), 250 ether);

        // Let's test we can drain the pool in its entirety,
        // which our naive AMM allows:
        token1.mint(address(this), 150 ether);

        // We have drained the pool!
        vm.expectEmit();
            emit Assignment3.Drained(address(token0));
            pool.oneForZero(150 ether);

        // Let's try to perform another swap.
        token1.mint(address(this), 1);

        vm.expectRevert(abi.encodeWithSignature("InsufficientLiquidity()"));
            pool.oneForZero(1);

    }

    /**
     * @dev Tests inverse token swaps from `token0` to `token1`.
     * In this example, `token0` is worth half of `token1`.
     */
    function test_oneForZero() public {

        MockERC20 token0 = new MockERC20("Token0");
        MockERC20 token1 = new MockERC20("Token1");

        Assignment3 pool = new Assignment3(
            address(token0),
            address(token1),
            2e18 /* 1-for-2 */
        );

        // We'll start off with some tokens which represent
        // the desired token balance ratio exactly.
        token0.mint(address(this), 200 ether);
        token1.mint(address(this), 100 ether);

        // Approve the pool.
        token0.approve(address(pool), type(uint256).max);
        token1.approve(address(pool), type(uint256).max);

        // Mint a balanced initial supply.
        pool.mint(200 ether, 100 ether);

        // Okay, let's try to swap some tokens!
        // For 50 of token0, we should expect 25 token1.
        token0.mint(address(this), 50 ether);

        // Swap 50 ether of `token0`. We should receive 25 `token0`.
        pool.zeroForOne(50 ether);

        assertEq(token1.balanceOf(address(this)), 25 ether);
        assertEq(token0.balanceOf(address(this)), 0);

        // At this stage, the pool should have `75` ether of
        // `token1` and `250` ether of `token0`.
        assertEq(token0.balanceOf(address(pool)), 250 ether);
        assertEq(token1.balanceOf(address(pool)), 75 ether);

        // Let's test we can drain the pool in its entirety,
        // which our naive AMM allows:
        token0.mint(address(this), 150 ether);

        // We have drained the pool!
        vm.expectEmit();
            emit Assignment3.Drained(address(token1));
            pool.zeroForOne(150 ether);

        // Let's try to perform another swap.
        token0.mint(address(this), 1);

        vm.expectRevert(abi.encodeWithSignature("InsufficientLiquidity()"));
            pool.zeroForOne(1);

    }

}
