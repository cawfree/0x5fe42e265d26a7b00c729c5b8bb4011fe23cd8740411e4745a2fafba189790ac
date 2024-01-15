// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.20;

import {console} from "forge-std/console.sol";
import {Merkle} from "@murky/Merkle.sol";

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

  function test_partialRefund() public {

    Assignment1.Round memory round = Assignment1.Round({
      merkleRoot: "",
      maximum: 100 ether,
      minimumIndividual: 1 ether,
      maximumIndividual: 100 ether
    });

    Assignment1.Round[] memory rounds = new Assignment1.Round[](1);
    rounds[0] = round;

    Assignment1 tokenSale = new Assignment1("TokenSale", "TS", rounds) /* no_revert */;

    bytes32[] memory proof;

    address addr = address(1);

    vm.deal(addr, 75 ether);
    vm.prank(addr);
      tokenSale.participate{value: 75 ether}(proof);

    // Awesome, let's claim some tokens!
    vm.prank(addr);
      tokenSale.claim(0, 50 ether, addr);

    // User should now have 50 ether worth of tokens, since these
    // are minted 1-1 with ether.
    assertEq(tokenSale.balanceOf(addr), 50 ether);

    // User hasn't claimed all their tokens, they wish to back out.
    vm.prank(addr);
      tokenSale.refund(addr);

    // User should have received their 25 ether. Their
    // token allocation should remain unchanged.
    assertEq(addr.balance, 25 ether);
    assertEq(tokenSale.balanceOf(addr), 50 ether);

    // User turns malicious and tries to claim their tokens. 
    vm.prank(addr);
      vm.expectRevert(abi.encodeWithSignature("FailedToClaim()"));
      tokenSale.claim(0, 25 ether, addr);

    // User is annoyed. Tries to break the sale by contributing
    // 1 wei less than the completion amount. Sice the minimum contribution
    // is `1 ether`, that has to lock the owners out from their funding, right?

    uint256 maliciousAmount = 50 ether - 1;
    vm.deal(addr, maliciousAmount);

    vm.prank(addr);
      tokenSale.participate{value: maliciousAmount}(proof);

    assertEq(address(tokenSale).balance, 100 ether - 1 wei);

    // Another user comes along, sees it only costs 1 wei to participate.
    addr = address(2);

    vm.deal(addr, 1 wei);

    // Check we indeed force the minimum deposit.
    vm.prank(addr);
      vm.expectRevert(abi.encodeWithSignature("InvalidDeposit()"));
      tokenSale.participate{value: 1 wei}(proof);

    // See if the user can close out the round using the minimum deposit.
    vm.deal(addr, 1 ether);

    vm.prank(addr);
      tokenSale.participate{value: 1 ether}(proof);

    // The round was able to be closed out! Look, the owner can drain:
    tokenSale.drain(_DEAD_ADDRESS);

    // But that seems expensive right? Hopefully they were refunded...
    assertEq(addr.balance, 1 ether - 1 wei);

  }

  function test_multipleRounds() public {

    Assignment1.Round memory round = Assignment1.Round({
      merkleRoot: "",
      maximum: 1 ether,
      minimumIndividual: 1 ether,
      maximumIndividual: 1 ether
    });

    Assignment1.Round[] memory rounds = new Assignment1.Round[](2);
    rounds[0] = round;
    rounds[1] = round;

    Assignment1 tokenSale = new Assignment1("TokenSale", "TS", rounds) /* no_revert */;

    bytes32[] memory proof;

    vm.deal(address(1), 2 ether);

    // Complete the first round.
    vm.startPrank(address(1));
      tokenSale.participate{value: 1 ether}(proof);
      // Assert their tokens can be claimed.
      tokenSale.claim(0, 1 ether, address(1));
    vm.stopPrank();

    // Check the owner cannot drain - there are more rounds to be completed.
    vm.expectRevert(abi.encodeWithSignature("FailedToWithdraw()"));
      tokenSale.drain(address(this));

    // Check they cannot claim for a future round.
    vm.expectRevert(abi.encodeWithSignature("FailedToWithdraw()"));
      tokenSale.withdraw(1, 1 ether, address(this));

    // Check they can claim for the closed out round.
    tokenSale.withdraw(0, 0.5 ether, address(this));
    tokenSale.withdraw(0, 0.5 ether, address(this));

    // Complete the second round.
    vm.startPrank(address(1));

      tokenSale.participate{value: 1 ether}(proof);

      // Try to claim from the first round.
      vm.expectRevert(abi.encodeWithSignature("FailedToClaim()"));
        tokenSale.claim(0, 1 ether, address(1));

      // Try to claim from the current round.
      tokenSale.claim(1, 0.5 ether, address(1));
      tokenSale.claim(1, 0.5 ether, address(1));

    vm.stopPrank();

    // Cool. Finally, allow the owner to pull funds from the completed round.
    tokenSale.withdraw(1, 1 ether, address(this));

  }

  function test_closedRounds() public {

    Merkle m = new Merkle();

    // Initialize the Merkle Tree for a closed round.
    bytes32[] memory data = new bytes32[](4);
    data[0] = keccak256(abi.encode(address(1)));
    data[1] = keccak256(abi.encode(address(2)));
    data[2] = keccak256(abi.encode(address(3)));
    data[3] = keccak256(abi.encode(address(4)));

    Assignment1.Round memory round = Assignment1.Round({
      merkleRoot: m.getRoot(data),
      maximum: 1 ether,
      minimumIndividual: 1 ether,
      maximumIndividual: 1 ether
    });

    Assignment1.Round[] memory rounds = new Assignment1.Round[](1);
    rounds[0] = round;

    Assignment1 tokenSale = new Assignment1("TokenSale", "TS", rounds) /* no_revert */;

    bytes32[] memory proof;

    // Try to participate as an address that is not
    // allowlisted. 
    vm.expectRevert(abi.encodeWithSignature("UnableToParticipate()"));
      tokenSale.participate{value: 1 ether}(proof);

    // Get the proof for address(1).
    proof = m.getProof(data, 0);

    // Try to steal the proof for use with an address
    // which isn't on the allowlist.
    vm.deal(address(5), 1 ether);
    vm.prank(address(5));
      vm.expectRevert(abi.encodeWithSignature("UnableToParticipate()"));
      tokenSale.participate{value: 1 ether}(proof);

    // Attempt to enter the closed round as an
    // allowlisted caller with the correct proof.
    vm.deal(address(1), 1 ether);
    vm.prank(address(1));
      tokenSale.participate{value: 1 ether}(proof);
  
  }

  // HACK: Allow ether to be sent to this contract.
  receive() external payable {}

}
