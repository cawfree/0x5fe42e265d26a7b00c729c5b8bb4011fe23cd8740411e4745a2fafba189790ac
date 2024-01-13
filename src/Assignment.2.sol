// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.13;

import {Ownable} from "@openzeppelin-contracts/access/Ownable.sol";
import {ERC721} from "@openzeppelin-contracts/token/ERC721/ERC721.sol";
import {Base64} from "@openzeppelin-contracts/utils/Base64.sol";
import {Strings} from  "@openzeppelin-contracts/utils/Strings.sol";

/**
 * @title Assigment2
 * @author cawfree
 * @notice A naive voting contract.
 */
contract Assignment2 is Ownable, ERC721 {

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

    /// @dev Running vote count.
    uint256 public voteCount;

    /**
     * @dev Contract deployer is assigned ownership of the contract.
     * @param name Name of the election token.
     * @param symbol Symbols of the election token.
     */
    constructor(string memory name, string memory symbol) Ownable(msg.sender) ERC721(name, symbol) {}

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

        /// @notice Mint the voter a token as a thank you for participation!
        /// @dev We are using safeMint, which implies re-entrancy for ERC-721
        ///      receivers, and a failure to vote for calling contracts which
        ///      do not conform to the standard. I've added this just for
        ///      fun, though this affects who can vote pretty drastically.
        ///      We could just use `mint(address,uint256)` - but I want to
        ///      emphasise I am thinking about re-entrancy throughout.
        _safeMint(msg.sender, voteCount++ /* zero_indexed */);

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

    /**
     * @notice Generates OpenSea-compatible metadata JSON for each minted token.
     * @param tokenId The token identifer.
     */
    function tokenURI(uint256 tokenId) public view override(ERC721) returns (string memory) {
        
        // Not strictly necessary, since all badges render the
        // same and do not rely upon token-specific metadata
        // outside of the identifier, which is freely available.
        _requireOwned(tokenId);

        /// @dev Generates some on chain "art". Heh...
        return string(
            abi.encodePacked(
                "data:application/json;base64,",
                Base64.encode(
                  bytes(
                    abi.encodePacked(
                      '{',
                        '"name":"Vote Badge #', Strings.toString(tokenId), '",',
                        '"description":"I voted in the big election!",',
                        '"image":"data:image/svg+xml;base64,', Base64.encode(
                            abi.encodePacked(
                                unicode'<svg xmlns="http://www.w3.org/2000/svg" width="350" height="350" style="background-color:#ffffff"><text x="50%" y="50%" dominant-baseline="middle" text-anchor="middle" font-size="100px" fill="#000000">🗳️</text></svg>'
                            )
                        ), '"',
                      '}'
                    )
                  )
                )
            )
        );
    }

}
