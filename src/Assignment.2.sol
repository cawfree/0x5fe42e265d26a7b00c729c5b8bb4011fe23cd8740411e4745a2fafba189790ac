// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.13;

import {Ownable} from "@openzeppelin-contracts/access/Ownable.sol";

/**
 * @title Assigment2
 * @author cawfree
 * @notice A naive voting contract.
 */
contract Assignment2 is Ownable {

    /**
     * @dev Defines the status of a voter. By default, all
     * voters are unregistered. Upon registering, their status
     * can move into the `REGISTERED` phase. Finally, registered
     * voters can cast a vote, transitioning them into the
     * `REGISTERED_AND_VOTED` status, which prevents them from
     * voting again.
     */
    enum VoterStatus {
        NOT_REGISTERED,
        REGISTERED,
        REGISTERED_AND_VOTED
    }

    /**
     * @dev Emitted when a new voter has registered. 
     * @param voter The address which registered to vote.
     */
    event VoterRegistered(address indexed voter);

    /**
     * @dev Emitted when a `voter` votes for their choice of `candidate`.
     */
    event Vote(address indexed candidate, address voter);

    /**
     * @dev Emitted when a new candidate is registered.
     */
    event CandidateRegistered(address indexed candidate);

    /**
     * @dev Thrown when `owner` of the contract attempts
     * to register duplicate candidate.
     * @param candidate The duplicative candidate address.
     */
    error CandidateAlreadyRegistered(address candidate);

    /**
     * @dev Thrown when a voter attempts to vote for an invalid
     * candidate.
     */
    error InvalidCandidate();

    /**
     * @dev Thrown when an address has already registered to vote.
     */
    error AlreadyRegisteredToVote();

    /**
     * @dev Thrown when an access-controlled function body encounters
     * an address which has not registered for voting.
     */
    error MustRegisterToVote();

    /**
     * @dev Thrown when a voter attempts to repeat vote.
     */
    error AlreadyVoted();

    /**
     * @notice Only execute function contents for valid candidates.
     * @param candidate Account to verify for candidate status.
     */
    modifier onlyCandidate(address candidate) {

        // Ensure we aren't handling a non-existent candidate.
        if (_candidates[candidate] == 0)
            revert InvalidCandidate();

        _ /* continue */;

    }

    /**
     * @notice Only execute the function contents if `addr`
     * is a registered voter.
     * @param addr Account to verify for voter status.
     */
    modifier onlyVoter(address addr) {

        // If the address has not registered to vote,
        // escape execution.
        if (_registeredVoters[addr] == VoterStatus.NOT_REGISTERED)
            revert MustRegisterToVote();

        _ /* continue */;

    }

    /**
     * @dev Tracks which accounts have registered to vote.
     * (account => VoterStatus)
     */
    mapping (address => VoterStatus) private _registeredVoters;

    /**
     * @dev Tracks which accounts are candidates.
     * (account => number_of_votes + 1)
     */
    mapping (address => uint256) private _candidates;

    /**
     * @dev Contract deployer is assigned ownership of the contract.
     */
    constructor() Ownable(msg.sender) {}

    /**
     * @notice Allows an account to register to vote. Note, this is
     * NOT resistant to sybil attacks. An attacker may create many accounts
     * to register under. Consider using Proof-of-Humanity, Proof-of-Work,
     * Reputation Weighted Voting or at the very least plutocratic economic
     * incentives to minimimize this kind manipulation.
     * @dev Registers the `msg.sender` as a voter.
     */
    function register() external {

        // If the `msg.sender` has already registered,
        // terminate early to avoid duplicatative events
        // which would complicate off-chain indexing.
        if (_registeredVoters[msg.sender] != VoterStatus.NOT_REGISTERED)
            revert AlreadyRegisteredToVote();

        // Register the `msg.sender` as a voter.
        _registeredVoters[msg.sender] = VoterStatus.REGISTERED;

        emit VoterRegistered(msg.sender);

    } 

    /**
     * @notice Register an address as a candidate who
     * may be voted for.
     * @dev For efficiency, we track registered candidates
     * status and their votes using the same value. Accounts
     * which are not registered have zero votes. Registered
     * candidates carry one synthetic vote, and candidates 
     * who have been voted for carry a vote_count + 1.
     * @param candidate The address to modify.
     */
    function addCandidate(address candidate) external onlyOwner {

        // Prevent existing candidates from being re-registered.
        if (_candidates[candidate] > 0)
            revert CandidateAlreadyRegistered(candidate);

        // Register the account as a candidate which may be voted for.
        _candidates[candidate] = 1;

        emit CandidateRegistered(candidate);
    }

    /**
     * @notice Allows the caller to vote on a proposal. Note,
     * elections are contentious issues in the real world! It
     * may not be in the interest of the voting audience to publish
     * a vote on. In future, we could consider using ZKPs to obscure
     * votes, and permit callers to vote in a democratically fair,
     * secure and privacy/safety preserving way. Note, attempts to
     * vote more than once will be rejected.
     * @dev Caller must be a registered voter.
     * @param candidate The candidate to vote for.
     */
    function vote(address candidate) external onlyVoter(msg.sender) onlyCandidate(candidate) {

        // Ensure the voter hasn't cast their vote already.
        if (_registeredVoters[msg.sender] == VoterStatus.REGISTERED_AND_VOTED)
            revert AlreadyVoted();

        // Vote for the preferred candidate.
        ++_candidates[candidate];

        // Ensure the caller cannot vote again in this election.
        _registeredVoters[msg.sender] = VoterStatus.REGISTERED_AND_VOTED;

        // Update off-chain vote count indexers.
        emit Vote(candidate, msg.sender);

    }

    /**
     * @notice Determine the vote count for a `candidate`.
     * @dev Function will revert if we attempt to interact
     * with an invalid candidate.
     * @param candidate The candidate to determine the vote
     * count for.
     */
    function getVoteCount(address candidate) external view onlyCandidate(candidate) returns (uint256) {

        /**
         * @dev Notice here we reduce the running vote count by one
         * since the first vote is synthetic, and used for candidate
         * mapping truthiness.                    
         */
        return _candidates[candidate] - 1;

    }

}
