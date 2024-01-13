// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.13;

import {EIP712} from "@openzeppelin-contracts/utils/cryptography/EIP712.sol";
import {ECDSA} from "@openzeppelin-contracts/utils/cryptography/ECDSA.sol";

/**
 * @title Assignment4
 * @author cawfree
 * @notice A multisignature contract. This is based around the
 * concept of a commit-reveal scheme - multisig owners will
 * vote on a transaction hash and only reveal the contents at
 * execution time.
 */
contract Assignment4 is EIP712 {

    /**
     * @dev A `Decision` defines a multisig owner's
     * vote on a given execution. By default, these
     * are undecided, and the transaction execution
     * threshold may only be decided by `ACCEPTED`
     * decision weights. We also include a `REJECTED`
     * status, to counteract the case where a historical
     * signature containing a valid acceptance for execution
     * may attempt to be used to override an intentional
     * rejection.
     */
    enum Decision {
        UNDECIDED,
        ACCEPTED /* used to explicitly re-activate a previously-cancelled transaction */,
        REJECTED /* used to cancel a vote for transaction */
    }

    /**
     * @notice Defines a transaction object, which configures
     * an action for the multisig to take.
     * @param to Address to target.
     * @param data The transaction data.
     * @param value The amount of ether to send alongside.
     * @param nonce The unique nonce for the transaction.
     * @param deadline The deadline for the transaction to
     * be executed - avoids inefficient execution.
     */
    struct Transaction {
        address to;
        bytes data;
        uint256 value;
        uint256 nonce;
        uint256 deadline;
    }

    /**
     * @dev Thrown to escape access control violations.
     */
    error NotAuthorized();

    /**
     * @dev Thrown when an owner attempts to manually define
     * their decision as UNDECIDED. This is not allowed, as
     * UNDECIDED represents an uninitialized state.
     */
    error ConcreteDecisionRequired();

    /**
     * @dev Thrown when a transaction attempts to reuse a nonce.
     */
    error CannotReplayTransaction();
    
    /**
     * @dev Thrown when a transaction deadline has been missed. 
     */
    error DeadlineMissed();

    /**
     * @dev Thrown when the multisig has failed to reach a
     * sufficient number of votes.
     */
    error FailedToQuorum();

    /**
     * @dev Thrown when an invalid threshold has been specified,
     * i.e. a threshold greater than the number of multisig owners,
     * or a zero threshold, which would dangerously allow any
     * caller to transact on behalf of the multisig.
     */
    error InvalidThreshold();

    /**
     * @dev Thrown when the array of `owners` is invalid.
     */
    error InvalidOwners();

    /**
     * @dev Tracks the registered owners for the multisig.
     * (ownerAddress => isOwner)
     */
    mapping (address => bool) internal _owners;

    /**
     * @dev The voting threshold which must be exceeded in order
     * for a transaction to be executed.
     */
    uint256 private immutable _THRESHOLD;

    /**
     * @dev Contains a mapping between an execution hash
     * and an owner's decision to execute that hash. By default,
     * each transaction for each user is initialized to `UNDECIDED`.
     * (transactionHash => (ownerAddress => decision))
     */
    mapping (bytes32 => mapping (address => Decision)) internal _hashToOwnerDecision;

    /**
     * @dev Contains the number of votes for a given transactionHash.
     * Possesses a direct correlation with owner decisions for the same
     * hash.
     * (bytes32 => number_of_votes)
     */
    mapping (bytes32 => uint256) internal _hashToAcceptanceCount;

    /**
     * @dev Tracks used nonces. Prevents replay attacks.
     */
    mapping(uint256 => bool) internal _usedNonces;

    /**
     * @dev A modifier which ensures function bodies may only
     * be executed if `msg.sender` is an owner of the multisig.
     */
    modifier onlyMultisigOwner() {

        // If `msg.sender` isn't an owner, revert.
        if (!_owners[msg.sender]) revert NotAuthorized();

        _;
    }

    /**
     * @param owners The owners of the multisig.
     * @param threshold The minimum number of votes required
     * to permit a transaction to succeed.
     */
    constructor(address[] memory owners, uint256 threshold) EIP712("MultisigAssignment", "1") {

        /**
         * @dev Ensure the `threshold` is valid. Note, this
         * relies greatly on the array of `owners` also being
         * valid.
         */
        if (threshold == 0 || threshold > owners.length)
            revert InvalidThreshold();

        /// @dev Ensure at least a single owner.
        if (owners.length == 0) revert InvalidOwners();

        /**
         * @dev Here we convert the array of `owners` into a mapping
         * to ease lookups. Additionally, we perform validation of the
         * array to prevent invalid addresses or duplicates from being
         * specified.
         */
        for (uint256 i; i < owners.length;) {

            // Fetch the current `owner` being onboarded.
            address owner = owners[i];

            // Ensure the owner is not the zero address.
            if (owner == address(0)) revert InvalidOwners();

            // Ensure the owner hasn't already been initialized (this
            // would impact the viability of crossing the voting
            // threshold).
            if (_owners[owner]) revert InvalidOwners();

            // Register the `owner`.
            _owners[owner] = true;

            unchecked { ++i; }
        }

        // Finally, assign the execution `_THRESHOLD`.
        _THRESHOLD = threshold;

    }

    /**
     * @notice Defines a consist interface for hashing
     * a transaction bundle as part of EIP712.
     * @param transaction The transaction to hash.
     */
    function hashTransaction(Transaction memory transaction) public view returns (bytes32) {
        /*
         * @notice The `DOMAIN_SEPARATOR` implicitly computed here
         * protects against replay attacks on chain forks.
         */
        return _hashTypedDataV4(
            keccak256(
                abi.encode(
                    keccak256("Transaction(address to,bytes data,uint256 value,uint256 nonce,uint256 deadline)"),
                    transaction.to,
                    transaction.data,
                    transaction.value,
                    transaction.nonce,
                    transaction.deadline
                )
            )
        );
    }

    /**
     * @notice Executes a transaction, provided the threshold is met.
     * @param transaction The transaction to execute.
     * @param signatures Array of signatures to supplement on-chain
     * decisions.
     */
    function execute(
        Transaction memory transaction,
        bytes[] memory signatures
    ) external payable returns (bytes memory) {

        // Ensure the timestamp hasn't exceeded the deadline.
        if (block.timestamp > transaction.deadline) revert DeadlineMissed();

        // Ensure the nonce hasn't already been used.
        if (_usedNonces[transaction.nonce]) revert CannotReplayTransaction();

        // Mark the nonce has used.
        _usedNonces[transaction.nonce] = true;

        // Compute the `transactionHash` that needs to be signed.
        bytes32 transactionHash = hashTransaction(transaction);

        // Loop through the signatures, taking care to
        // account for any additional approvals.
        for (uint256 i; i < signatures.length; i++) {

            // Fetch the address of the signer - make sure
            // it corresponds to a real owner.
            /**
             * @dev We are using the ECDSA library which is not
             * susceptible to signature malleability. Additionally,
             * our use of transations nonces hinder the risk of
             * signature malleability, in addition to ensuring owners
             * may only increase the voting threshold by one.
             */
            address signer = ECDSA.recover(transactionHash, signatures[i]);

            // Skip if we encounter an invalid signature.
            if (signer == address(0)) continue;

            // Skip if the signer is not an owner of the vault.
            if (!_owners[signer]) continue;

            /**
             * @dev Here we fetch the current status of the signer's
             * vote. A signature reflecting acceptance of a transaction
             * may only contribute to the voting weight if the signer's
             * decision is currently `UNDECIDED`, else if these have been
             * manually/asynchronously `APPROVED` or `REJECTED`, the
             * historical signature will yield to that and not be applied
             * here.
             */
            if (_hashToOwnerDecision[transactionHash][signer] != Decision.UNDECIDED) continue;

            // Else, lets approve the transaction for the signer,
            // implicitly incrementing the voting count by using their
            // signature for the transaction to override their `UNDECIDED`
            // vote.
            _updateDecision(transactionHash, signer, Decision.ACCEPTED);

        }

        // Ensure that we have sufficient votes for the transaction,
        // else the multisig owners failed to quorum and we are not
        // permitted to execute.
        if (_hashToAcceptanceCount[transactionHash] < _THRESHOLD)
            revert FailedToQuorum();

        (bool success, bytes memory returnData) =
            transaction.to.call{value: transaction.value}(transaction.data);

        if (!success) revert(_getRevertMsg(returnData));

        return returnData;
    }

    /**
     * @notice Allows a caller to vote for a specific execution outcome
     * for a transactionHash. Most transactions can merely be signed for
     * off-chain, however this is useful for cases where a multisig owner
     * may specifically intend to revoke a previously published signature,
     * so that historical signings submitted manually cannot revoke.
     * @param transactionHash Hash of the transaction.
     * @param decision Vote on whether the transaction should be executed.
     * @dev May only be called by a multisig owner.
     * @dev This is susceptible to frontrunning - an attacker in the mempool
     * could detect the presence of a decision to `REJECT` a transaction,
     * and submit an existing accepted signature at a higher gas value to
     * override it.
     */
    function updateDecision(bytes32 transactionHash, Decision decision) external onlyMultisigOwner {

        // External callers may only specify concrete decisions,
        // since the UNDECIDED state possesses significant semantic
        // importance when coupled with the submission of a historical
        // approval signature.
        if (decision == Decision.UNDECIDED) revert ConcreteDecisionRequired();

        // Defer to the internal method.
        _updateDecision(transactionHash, msg.sender, decision);

    }

    /**
     * @notice Updates a user's decision for a given transactionHash.
     * @param transactionHash The transactionHash being voted on.
     * @param owner The address to update the decision for.
     * @param decision The decision the owner has made for this transaction.
     */
    function _updateDecision(bytes32 transactionHash, address owner, Decision decision) internal {

        /**
         * @dev Determine if the `owner` has already voted
         * positively on this transactionHash. If so, we'll
         * reset their vote count.
         */
        if (_hashToOwnerDecision[transactionHash][owner] == Decision.ACCEPTED) {
            // Decrease the number of votes on the transaction.
            --_hashToAcceptanceCount[transactionHash];
        }

        /**
         * @dev If the decision is to accept the transaction,
         * the vote count must be increased. 
         */
        if (decision == Decision.ACCEPTED) ++_hashToAcceptanceCount[transactionHash];

        /// @dev Finally, update the current decision.
        _hashToOwnerDecision[transactionHash][owner] = decision;

    }

    // https://ethereum.stackexchange.com/a/83577
    function _getRevertMsg(bytes memory _returnData) internal pure returns (string memory) {
        // If the _res length is less than 68, then the transaction failed silently (without a revert message)
        if (_returnData.length < 68) return "";

        assembly {
            // Slice the sighash.
            _returnData := add(_returnData, 0x04)
        }
        return abi.decode(_returnData, (string)); // All that remains is the revert string
    }

    /**
     * @notice This contract accepts ether.
     * @dev Possible extensions - allow this contract
     * to conform to the ERC-721 standard and accept NFTs.
     */
    receive() external payable { /* :) */ }

}