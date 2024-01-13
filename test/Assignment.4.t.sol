// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.13;

import {console} from "forge-std/console.sol";

import {Assignment4} from "../src/Assignment.4.sol";

import {BaseTest} from "./utils/BaseTest.t.sol";

contract Assignment4Test is BaseTest {

    ///* Actor private keys. */
    //uint256 private immutable _PK_ALICE = 1;
    //uint256 private immutable _PK_BOB = 2;
    //uint256 private immutable _PK_CAROL = 3;
    //uint256 private immutable _PK_DAVE = 4;

    /**
     * @dev Runs through a range of pathalogical configurations
     * until settling on valid combinations of owners and thresholds.
     */
    function test_validOwners() public {

        vm.expectRevert(abi.encodeWithSignature("InvalidThreshold()"));
            new Assignment4(new address[](0), 0);

        vm.expectRevert(abi.encodeWithSignature("InvalidThreshold()"));
            new Assignment4(new address[](2), 3);

        vm.expectRevert(abi.encodeWithSignature("InvalidThreshold()"));
            new Assignment4(new address[](0), 1);

        vm.expectRevert(abi.encodeWithSignature("InvalidOwners()"));
            new Assignment4(new address[](1), 1);

        address[] memory owners = new address[](4);

        vm.expectRevert(abi.encodeWithSignature("InvalidOwners()"));
            new Assignment4(owners, 4) /* duplicates */;

        owners[0] = owners[1] = owners[2] = owners[3] = address(1);

        vm.expectRevert(abi.encodeWithSignature("InvalidOwners()"));
            new Assignment4(owners, 4) /* duplicates */;

        owners[2] = address(3);
        owners[3] = address(4);

        vm.expectRevert(abi.encodeWithSignature("InvalidOwners()"));
            new Assignment4(owners, 4) /* duplicates */;

        owners[1] = address(2);
        new Assignment4(owners, 4) /* valid */;

        vm.expectRevert(abi.encodeWithSignature("InvalidThreshold()"));
            new Assignment4(owners, 5);

        new Assignment4(owners, 1);

    }

    function _getMockOwners(uint256 numberOfOwners) internal returns (address[] memory) {

        address[] memory owners = new address[](numberOfOwners);

        for (uint256 i; i < numberOfOwners;) {
            owners[i] = vm.addr(i + 1);
            unchecked { ++i; }
        }

        return owners;

    }

    function _getMockSignatures(uint256 numberOfOwners, bytes32 transactionHash) internal returns (Assignment4.Signature[] memory signatures) {
        signatures = new Assignment4.Signature[](numberOfOwners);

        for (uint256 i; i < numberOfOwners;) {
            signatures[i] = _signTransactionHash(i + 1, transactionHash);
            unchecked { ++i; }
        }

    }

    /**
     * @notice Produces a signature digest to authenticate
     * a transaction with.
     * @param privateKey Key to sign using.
     * @param transactionHash The transaction hash to authenticate.
     */
    function _signTransactionHash(uint256 privateKey, bytes32 transactionHash) internal returns (Assignment4.Signature memory) {
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(privateKey, transactionHash);
        return Assignment4.Signature(v, r, s);
    }

    function test_executeTransaction() public {

        // Here, we'll require *all* owners to agree before allowing
        // a transaction to be executed.
        Assignment4 multisig = new Assignment4(_getMockOwners(4), 4);

        // Give the multisig some ether to play with.
        vm.deal(address(multisig), 10 ether);

        // Let's create a transaction.
        Assignment4.Transaction memory transaction = Assignment4.Transaction(
            _DEAD_ADDRESS /* to */,
            "" /* data */,
            10 ether /* value */,
            0 /* nonce */,
            block.timestamp /* deadline */
        );

        assertEq(_DEAD_ADDRESS.balance, 0);

        /// @dev First, use too few signatures.
        Assignment4.Signature[] memory signatures = _getMockSignatures(3, multisig.hashTransaction(transaction));

        vm.expectRevert(abi.encodeWithSignature("FailedToQuorum()"));
            multisig.execute(transaction, signatures);

        /// @dev Now use the required number of signatures.
        signatures = _getMockSignatures(4, multisig.hashTransaction(transaction));
        multisig.execute(transaction, signatures);

        assertEq(_DEAD_ADDRESS.balance, 10 ether);

    }

}
