// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.20;

import {console} from "forge-std/console.sol";

import {IERC20} from "@openzeppelin-contracts/token/ERC20/IERC20.sol";

import {Assignment3} from "../src/Assignment.3.sol";

import {MockERC20} from "./mocks/Mock.ERC20.sol";
import {BaseTest} from "./utils/BaseTest.t.sol";

contract Assignment3Test is BaseTest {

  /// @dev Creates a pool, extracting the most interesting
  /// configuration properties for testing.
  function _createPool(
    uint256 exchangeRate1For0,
    uint256 lockedLiquidity,
    uint256 swapFeeBp
  ) internal returns (MockERC20 token0, MockERC20 token1, Assignment3 pool) {

    token0 = new MockERC20("Token0");
    token1 = new MockERC20("Token1");

    pool = new Assignment3( "TestPoolLiquidityTokens",
      "TPLT",
      token0,
      token1,
      exchangeRate1For0,
      lockedLiquidity,
      swapFeeBp
    );

  }

  function test_shares() public {

    (MockERC20 token0, MockERC20 token1, Assignment3 pool) = _createPool(1e18, 0, 10_000 /* steal all swap fees */);

    token0.mint(address(pool), 1e18);
    token1.mint(address(pool), 1e18);

    vm.prank(address(1));
      pool.mint(address(1), 0);

    token0.mint(address(pool), 5e17);
      pool.swap(address(_DEAD_ADDRESS));

    assertEq(token0.balanceOf(address(pool)), 1.5 ether);
    assertEq(token1.balanceOf(address(pool)), 1.0 ether);

    token0.mint(address(pool), 1e18);
    token1.mint(address(pool), 1e18);

    vm.prank(address(3));
      pool.mint(address(3), 0);

    vm.startPrank(address(1));
      pool.transfer(address(pool), pool.balanceOf(address(1)));
      pool.burn(address(1));
    vm.stopPrank();

    vm.startPrank(address(3));
      pool.transfer(address(pool), pool.balanceOf(address(3)));
      pool.burn(address(3));
    vm.stopPrank();

    assertEq(token0.balanceOf(address(pool)), 0);
    assertEq(token1.balanceOf(address(pool)), 0);

  }

  function test_fees() public {

    // Assume a totally balanced pool with no locked liqudity.
    (MockERC20 token0, MockERC20 token1, Assignment3 pool) = _createPool(1e18, 0, 10_000 /* steal all swap fees */);

    token0.mint(address(pool), 10 ether);
    token1.mint(address(pool), 10 ether);

    // Mint some shares.
    (uint256 liquidity) = pool.mint(address(this), 0);

    // Queue up some `token0` to swap into `token1`, and
    // vice-versa. The pool architecture permits us to do
    // this simultaneously.
    token0.mint(address(pool), 1 ether);
    token1.mint(address(pool), 1 ether);

    (uint256 amount0Out, uint256 amount1Out) = pool.swap(address(this));

    // Ensure 100% fees have stolen everything.
    assertEq(amount0Out, 0);
    assertEq(amount1Out, 0);

    // Transfer liquidity tokens to the pool to burn.
    pool.transfer(address(pool), liquidity);
    pool.burn(address(this));

    // Fees have been accumulated.
    assertEq(token0.balanceOf(address(this)), 11 ether);
    assertEq(token1.balanceOf(address(this)), 11 ether);

  }

  function test_lockedLiquidity() public {

    // Create a pool which demands we lock `1_000` shares
    // of liquidity to protect against inflation attacks.
    (MockERC20 token0, MockERC20 token1, Assignment3 pool) = _createPool(1e18, 1_000, 0);

    token0.mint(address(pool), 1 ether);
    token1.mint(address(pool), 1 ether);
    pool.mint(address(this), 0);

    // Ensure shares were burned to the dead address.
    assertEq(pool.balanceOf(_DEAD_ADDRESS), 1_000);

  }

  function test_initializationParameters() public {

    (IERC20 token0, IERC20 token1,) = _createPool(1e18, 0, 0);

    vm.expectRevert(abi.encodeWithSignature("InvalidTokens()"));
      new Assignment3("", "", IERC20(address(0)), IERC20(address(0)), 1e18, 0, 0);

    vm.expectRevert(abi.encodeWithSignature("InvalidTokens()"));
      new Assignment3("", "", token0, IERC20(address(0)), 1e18, 0, 0);

    vm.expectRevert(abi.encodeWithSignature("InvalidTokens()"));
      new Assignment3("", "", IERC20(address(0)), token1, 1e18, 0, 0);

    vm.expectRevert(abi.encodeWithSignature("InvalidBasisPoints(uint256)", 10_001));
      new Assignment3("", "", token0, token1, 1e18, 0, 10_001);

  }

  function test_oneForZero() public {

    // Exchange rate: 2 * token1 for 1 * token0.
    (MockERC20 token0, MockERC20 token1, Assignment3 pool) = _createPool(5e17, 0, 0);

    token0.mint(address(pool), 1 ether);
    token1.mint(address(pool), 2 ether);

    (uint256 liquidity) = pool.mint(address(this), 0);

    assertTrue(liquidity > 0);

    // Perform a swap that drains all the token1 liquidity.
    // This is expected since we used a fixed exchange rate.
    token1.mint(address(pool), 2 ether);
    vm.expectEmit();
    emit Assignment3.Drained(address(token0));
      pool.swap(_DEAD_ADDRESS);

    // Burn our shares. Without fees, we should receive all
    // liquidity terms of `token0`.
    pool.transfer(address(pool), liquidity);
    pool.burn(address(this));

    assertEq(token0.balanceOf(address(this)), 0);
    assertEq(token1.balanceOf(address(this)), 4 ether);

    assertEq(token0.balanceOf(_DEAD_ADDRESS), 1 ether);

  }

  function test_zeroForOne() public {

    // Exchange rate: 2 * token0 for 1 * token1.
    (MockERC20 token0, MockERC20 token1, Assignment3 pool) = _createPool(2e18, 0, 0);

    token0.mint(address(pool), 2 ether);
    token1.mint(address(pool), 1 ether);

    (uint256 liquidity) = pool.mint(address(this), 0);

    assertTrue(liquidity > 0);

    // Perform a swap that drains all the token1 liquidity.
    // This is expected since we used a fixed exchange rate.
    token0.mint(address(pool), 2 ether);
      vm.expectEmit();
      emit Assignment3.Drained(address(token1));
        pool.swap(_DEAD_ADDRESS);

    // Burn our shares. Without fees, we should receive all
    // liquidity terms of `token1`.
    pool.transfer(address(pool), liquidity);
    pool.burn(address(this));

    assertEq(token0.balanceOf(address(this)), 4 ether);
    assertEq(token1.balanceOf(address(this)), 0);

    assertEq(token1.balanceOf(_DEAD_ADDRESS), 1 ether);

  }

}
