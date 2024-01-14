// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.13;

import {console} from "forge-std/console.sol";

import {Assignment1} from "../src/Assignment.1.sol";

import {BaseTest} from "./utils/BaseTest.t.sol";

contract Assignment1Test is BaseTest {

  function test_invalidRounds() public {

    vm.expectRevert(abi.encodeWithSignature("InvalidRounds()"));
      new Assignment1("TokenSale", "TS", new Assignment1.Round[](0));

    vm.expectRevert(abi.encodeWithSignature("InvalidRounds()"));
      new Assignment1("TokenSale", "TS", new Assignment1.Round[](1));

    Assignment1.Round memory round = Assignment1.Round({
      merkleRoot: "",
      maximum: 0,
      minimumIndividual: 0,
      maximumIndividual: 0
    });

    Assignment1.Round[] memory rounds = new Assignment1.Round[](1);
    rounds[0] = round;

    vm.expectRevert(abi.encodeWithSignature("InvalidRounds()"));
      new Assignment1("TokenSale", "TS", rounds);

    round.minimumIndividual = 100;

    vm.expectRevert(abi.encodeWithSignature("InvalidRounds()"));
      new Assignment1("TokenSale", "TS", rounds);

    round.maximumIndividual = 200;

    vm.expectRevert(abi.encodeWithSignature("InvalidRounds()"));
      new Assignment1("TokenSale", "TS", rounds);

    round.maximum = 200;
    new Assignment1("TokenSale", "TS", rounds) /* no_revert */;

  }

  function test_simpleRoundCompletion() public {

    Assignment1.Round memory round = Assignment1.Round({
      merkleRoot: "",
      maximum: 100 ether,
      minimumIndividual: 1 ether,
      maximumIndividual: 2 ether
    });

    Assignment1.Round[] memory rounds = new Assignment1.Round[](1);
    rounds[0] = round;

    Assignment1 tokenSale = new Assignment1("TokenSale", "TS", rounds) /* no_revert */;

    bytes32[] memory proof;

    for (uint256 i = 0; i < 100; i += 1) {

      address addr = address(uint160(i + 1));

      deal(addr, 1 ether);
      vm.prank(addr);
        tokenSale.participate{value: 1 ether}(proof);

    }

    // Round should be completed - no refunds!
    vm.prank(address(1));
      vm.expectRevert(abi.encodeWithSignature("FailedToClaim()"));
      tokenSale.refund(address(1));

  }

  function test_simpleRoundRefunds() public {

    Assignment1.Round memory round = Assignment1.Round({
      merkleRoot: "",
      maximum: 100 ether,
      minimumIndividual: 1 ether,
      maximumIndividual: 2 ether
    });

    Assignment1.Round[] memory rounds = new Assignment1.Round[](1);
    rounds[0] = round;

    Assignment1 tokenSale = new Assignment1("TokenSale", "TS", rounds) /* no_revert */;

    bytes32[] memory proof;

    for (uint256 i = 0; i < 99; i += 1) {

      address addr = address(uint160(i + 100));

      deal(addr, 1 ether);

      vm.prank(addr);
        tokenSale.participate{value: 1 ether}(proof);

    }

    // Round is not yet complete. Try to withdraw funds as the owner.
    vm.expectRevert(abi.encodeWithSignature("FailedToWithdraw()"));
      tokenSale.withdraw(0, address(tokenSale).balance, address(this));

    // No matter what they try.
    vm.expectRevert(abi.encodeWithSignature("FailedToWithdraw()"));
      tokenSale.drain(address(this));

    // Round is not complete, everyone should be refunded.
    for (uint256 i = 0; i < 99; i += 1) {

      address addr = address(uint160(i + 100));

      vm.prank(addr);
        tokenSale.refund(addr);

      assertEq(addr.balance, 1 ether);

    }

    // Cool, everyone got their refund. Let's close out the round.
    for (uint256 i = 0; i < 100; i += 1) {

      address addr = address(uint160(i + 100));

      deal(addr, 1 ether);

      vm.prank(addr);
        tokenSale.participate{value: 1 ether}(proof);

    }

    // Round should be complete. No refunds!
    vm.prank(address(1));
      vm.expectRevert(abi.encodeWithSignature("FailedToClaim()"));
      tokenSale.refund(address(1));

    // Owner should be able to withdraw ether.
    tokenSale.withdraw(0, 50 ether, address(1));
    assertEq(address(1).balance, 50 ether);
    tokenSale.withdraw(0, 50 ether, address(1));
    assertEq(address(1).balance, 100 ether);

    // Owner should also be permitted to drain once the all rounds are over.
    vm.deal(address(tokenSale), 100 ether);
    tokenSale.drain(address(1));
    assertEq(address(1).balance, 200 ether);

  }

  // HACK: Allow ether to be sent to this contract.
  fallback() external payable {}

}
