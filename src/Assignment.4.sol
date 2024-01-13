// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.13;

/**
 * @title Assignment4
 * @author cawfree
 * @notice A multisignature contract. This is based around the
 * concept of a commit-reveal scheme - multisig owners will
 * vote on a transaction hash and only reveal the contents at
 * execution time.
 */
contract Assignment4 {

    /**
     * @dev Thrown when a duplicate owner is supplied.
     */
    error DuplicateOwner();

    /**
     * @dev Thrown when an invalid owner is supplied.
     */
    error InvalidOwner();

    /**
     * @dev Thrown when an invalid threshold is specified.
     */
    error InvalidThreshold();

    /**
     * @dev Thrown when a caller attempts to use an invalid
     * nonce.
     */
    error InvalidNonce();

    /**
     * @dev Thrown when a transaction's deadline has passed.
     */
    error DeadlineMissed();

    /**
     * @dev Thrown when a caller attempts to execute a transaction
     * whose number of votes does not exceed the threshold.
     */
    error ThresholdNotMet();

    /**
     * @dev Thrown when a caller is not authorized.
     */
    error NotAuthorized();

    /**
     * @dev The execution threshold for signature-based votes.
     */
    uint256 public immutable THRESHOLD;

    /**
     * @dev Mapping of owner addresses.
     * (address => isOwner)
     */
    mapping (address => bool) private _owners;

    /**
     * @dev Mapping of used nonces.
     * (nonceId => isUsed)
     */
    mapping (uint256 => bool) private _usedNonces;

    /**
     * @dev Mapping of owners to transaction hash votes.
     * (owner => (transactionHash => isAccepted))
     */
    mapping(address => mapping(bytes32 => bool)) _ownerToTransactionHashAccepted;

    /**
     * @dev Mapping of transaction hashes to number of votes.
     * (transactionHash => numberOfVotes)
     */
    mapping(bytes32 => uint256) private _votes;
 
    /**
     * @param owners The owners of the wallet.
     * @param threshold The number of signatures required.
     * @dev Note, this doesn't ensure that all of the addresses
     * in `owners` correspond to valid EOAs - we just rely
     * on the voting phase to filter such addresses out, since contracts
     * cannot directly sign transaction data (although EIP-1271
     * style support could be implemented). Additionally, we are
     * neglecting to check if there is nonzero code length at a
     * specified address, since this can equally be subverted via
     * the contract constructor.
     * 
     * All this to say - this is a naive implementation which
     * can result in an array of owners populated with entities incapable
     * of signing to an extent that would exceed the `threshold`.
     */
    constructor(address[] memory owners, uint256 threshold) {

        /// @dev Ensure a realistic threshold for the array provided.
        if (owners.length == 0 || threshold == 0 || threshold > owners.length)
            revert InvalidThreshold();

        THRESHOLD = threshold;

        /// @dev Iteratively include and validate the `owners`.
        for (uint256 i; i < owners.length;) {

            // Fetch the next `owner`.
            address owner = owners[i];

            /// @dev Ensure that a duplicate address cannot
            /// artificially hinder the threshold.
            if (_owners[owner]) revert DuplicateOwner();

            // Assert the current address as an owner.
            _owners[owner] = true;

            unchecked { ++i; }
        }

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
     * @notice Allows a vault owner to vote on a transaction
     * they wish to execute.
     * @param transactionHash The hash of the transaction
     * to be executed.
     */
    function accept(bytes32 transactionHash) external {

        /// @dev First, ensure the caller is an owner of the vault.
        if (!_owners[msg.sender]) revert NotAuthorized();

        /// @dev Be sure to revert if they have already accepted
        /// this transaction hash. If so, we can revert silently.
        if (_ownerToTransactionHashAccepted[msg.sender][transactionHash]) return;

        /// @dev Else, mark the transaction as accepted by the user.
        _ownerToTransactionHashAccepted[msg.sender][transactionHash] = true;

        /// @dev Increase the number of votes for this hash.
        ++_votes[transactionHash];

    }

    /**
     * @notice Enables an owner to reject a transaction. 
     * @param transactionHash The hash of the transaction to execute.
     */
    function reject(bytes32 transactionHash) external {

        /// @dev First, ensure the caller is an owner of the vault.
        if (!_owners[msg.sender]) revert NotAuthorized();

        /// @dev Check to see if the owner has accepted this transaction.
        if (_ownerToTransactionHashAccepted[msg.sender][transactionHash]) {

            /// @dev Else, mark the transaction as rejected by the user.
            _ownerToTransactionHashAccepted[msg.sender][transactionHash] = false;

            /// @dev Decrease the number of votes for this hash.
            --_votes[transactionHash];
        }

    }

    /**
     * @notice Allows a transaction with a sufficient votes
     * threshold to be executed by the vault.
     */
    function execute(
        address to,
        bytes calldata data,
        uint256 value,
        uint256 nonce,
        uint256 chainId,
        uint256 deadline
    ) external payable returns (bytes memory) {

        /// @dev Compute the keccak256 hash of the transaction.
        bytes32 executeHash = keccak256(abi.encode(to, data, value, nonce, chainId, deadline));

        /// @dev Ensure the number of votes for this transaction
        /// exceeds the threshold.
        if (_votes[executeHash] < THRESHOLD) revert ThresholdNotMet();

        // If the block timestamp exceeds the deadline,
        // we cannot execute this transaction.
        if (block.timestamp > deadline) revert DeadlineMissed();

        // Ensure this message was signed for the correct chain
        // (avoid replay transactions).
        require(chainId == block.chainid);

        // Ensure the nonce hasn't yet been used.
        if (_usedNonces[nonce]) revert InvalidNonce();

        // Mark the nonce as used - ensure this transaction
        // cannot be repeated, for example through malicious
        // re-entrancy or via replay transactions.
        _usedNonces[nonce] = true;

        // Make the call.
        (bool success, bytes memory returnData) = to.call{value: value}(data);

        /// @dev If the call fails, bubble up the revert message.
        if (!success) revert(_getRevertMsg(returnData));

        return returnData;

    }

    /**
     * @notice This contract accepts ether.
     */
    receive() external payable { /* :) */ }

}