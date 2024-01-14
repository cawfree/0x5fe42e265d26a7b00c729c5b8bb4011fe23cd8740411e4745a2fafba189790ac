// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.13;

import {console} from "forge-std/console.sol";

import {Assignment2} from "../src/Assignment.2.sol";

import {BaseTest} from "./utils/BaseTest.t.sol";

contract Assignment2Test is BaseTest {

  function test_addCandidate() public {

    Assignment2 votingSystem = new Assignment2("Voting System", "VS");

    // Add a candidate. Could be used to inform off-chain
    // indexing like a subgraph.
    vm.expectEmit();
    emit Assignment2.CandidateRegistered(address(1));
      votingSystem.addCandidate(address(1));

    // Cannot re-add a candidate.
    vm.expectRevert(abi.encodeWithSignature("CandidateAlreadyRegistered(address)", address(1)));
      votingSystem.addCandidate(address(1));

    // Non-owner cannot add a candidate.
    vm.prank(address(1));
      vm.expectRevert(abi.encodeWithSignature("OwnableUnauthorizedAccount(address)", address(1)));
      votingSystem.addCandidate(address(2));

    // Get the vote count for the new candidate.
    assertEq(votingSystem.getVoteCount(address(1)), 0);

    // The vote count for a non-existent candidate should revert.
    vm.expectRevert(abi.encodeWithSignature("InvalidCandidate()"));
      votingSystem.getVoteCount(address(2));

  }

  function test_register() public {

    Assignment2 votingSystem = new Assignment2("Voting System", "VS");

    // Register as a voter.
    vm.expectEmit();
    emit Assignment2.VoterRegistered(address(this));
      votingSystem.register();

    // Cannot re-register.
    vm.expectRevert(abi.encodeWithSignature("AlreadyRegisteredToVote()"));
      votingSystem.register();

  }

  function test_vote() public {

    Assignment2 votingSystem = new Assignment2("Voting System", "VS");

    votingSystem.addCandidate(address(1));
    votingSystem.addCandidate(address(2));

    vm.prank(address(1));
      votingSystem.register();

    vm.prank(address(10));
      votingSystem.register();

    vm.prank(address(11));
      votingSystem.register();

    // Should fail to vote for ourselves (we aren't a candidate,
    // a candidate may vote for themselves, though).
    vm.prank(address(10));
      vm.expectRevert(abi.encodeWithSignature("InvalidCandidate()"));
      votingSystem.vote(address(10));

    vm.prank(address(10));
      vm.expectEmit();
      emit Assignment2.Vote(address(1), address(10));
        votingSystem.vote(address(1));

    vm.startPrank(address(1));

      vm.expectEmit();
      emit Assignment2.Vote(address(1), address(1));
        votingSystem.vote(address(1));

      vm.expectRevert(abi.encodeWithSignature("AlreadyVoted()"));
        votingSystem.vote(address(1));

      vm.expectRevert(abi.encodeWithSignature("AlreadyVoted()"));
        votingSystem.vote(address(2));

    vm.stopPrank();

    votingSystem.tokenURI(0);
    votingSystem.tokenURI(1);

    vm.expectRevert(abi.encodeWithSignature("ERC721NonexistentToken(uint256)", 2));
      votingSystem.tokenURI(2);

    assertEq(
      votingSystem.tokenURI(0),
      /// @dev Possible enhancement - parse the returned URI and 
      /// sanitize the JSON Object.
      'data:application/json;base64,eyJuYW1lIjoiVm90ZSBCYWRnZSAjMCIsImltYWdlIjoiZGF0YTppbWFnZS9zdmcreG1sO2Jhc2U2NCxQSE4yWnlCNGJXeHVjejBpYUhSMGNEb3ZMM2QzZHk1M015NXZjbWN2TWpBd01DOXpkbWNpSUhkcFpIUm9QU0l6TlRBaUlHaGxhV2RvZEQwaU16VXdJaUJ6ZEhsc1pUMGlZbUZqYTJkeWIzVnVaQzFqYjJ4dmNqb2pabVptWm1abUlqNDhkR1Y0ZENCNFBTSTFNQ1VpSUhrOUlqVXdKU0lnWkc5dGFXNWhiblF0WW1GelpXeHBibVU5SW0xcFpHUnNaU0lnZEdWNGRDMWhibU5vYjNJOUltMXBaR1JzWlNJZ1ptOXVkQzF6YVhwbFBTSXhNREJ3ZUNJZ1ptbHNiRDBpSXpBd01EQXdNQ0krOEorWHMrKzRqend2ZEdWNGRENDhMM04yWno0PSJ9'
    );

  }

}
