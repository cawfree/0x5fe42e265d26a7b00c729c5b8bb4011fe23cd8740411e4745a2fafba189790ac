// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.13;

import {Ownable} from "@openzeppelin-contracts/access/Ownable.sol";
import {ERC20} from "@openzeppelin-contracts/token/ERC20/ERC20.sol";
import {MerkleProof} from "@openzeppelin-contracts/utils/cryptography/MerkleProof.sol";

/**
 * @title Assignment1
 * @author cawfree
 * @notice A phased token sale contract. Assumes `owner` is trusted.
 */
contract Assignment1 is Ownable, ERC20 {

    /**
     * @notice Emitted when ether is sent to this contract asynchronously
     * to the standard functions, allowing accidentally sent tokens to
     * be tracked and potentially recovered by the `owner`.
     * @param sender The address responsible for the lost ether.
     * @param amount The amount sent.
     */
    event AccidentalEther(address indexed sender, uint256 amount);

    /**
     * @notice Emitted when a particpant has successfully increased
     * their deposited position.
     * @param participant The participant who made the deposit.
     * @param round The round the participant deposited to.
     * @param totalAmountDeposited The running total amount deposited by the particpant.
     */
    event Deposit(address indexed participant, uint256 round, uint256 totalAmountDeposited);

    /**
     * @dev Thrown when a user has attempted to participate in
     * the current round but that round is no longer accepting
     * submissions, their contribution is invalid, or they are
     * not in the allowlist.
     */
    error UnableToParticipate();

    /**
     * @dev Called when a caller has attempted to make an invalid
     * deposit, calling with either too low or too high a deposit
     * value.
     */
    error InvalidDeposit();

    /**
     * @dev Thrown when invalid round configuration has been
     * specified, for example, an invalid number of rounds,
     * or a round which does not exist.
     */
    error InvalidRounds();

    /**
     * @dev Thrown when the caller requests to withdraw
     * an amount of ether which exceeds the contract's
     * balance.
     */
    error InvalidWithdrawalAmount();

    /**
     * @dev Thrown when a caller fails to withdraw. We
     * might exceed the gas limit due to insufficient
     * transaction gas, a malicious triggering OOG, or
     * ether transfers might be rejected at the target.
     */
    error FailedToWithdraw();

    /**
     * @dev Thrown when the caller fails to refund a participant
     * for their excess ether.
     */
    error FailedToRefund();

    /**
     * @dev Thrown when the caller has attempted to claim
     * an invalid number of tokens.
     */
    error FailedToClaim();

    /**
     * @notice Defines the properties of a sales round.
     * @param maximum The maximum number of ether which can be
     * contributed in the round.
     * @param minimumIndividual The minimum amount of ether which
     * can be contributed by a participant.
     * @param maximumIndividual The maximum amount of ether which
     * can be contributed by a participant.
     */
    struct Round {
        bytes32 merkleRoot;
        uint256 maximum;
        uint256 minimumIndividual;
        uint256 maximumIndividual;
    }

    /// @dev Defines the configuration for each round.
    Round[] private _rounds;

    /// @dev Controls the current round.
    uint256 private _currentRound;

    /**
     * @dev Running totals for the amount of ether contributed
     * to each round:
     * (roundId => total_amount_deposited)
     */
    mapping(uint256 => uint256) private _totalDepositsPerRound;

    /**
     * @dev Tracks the total deposits made by participants
     * for each round:
     * (roundId => (participant => amount_deposited))
     */
    mapping(uint256 => mapping(address => uint256)) private _totalDepositsPerRoundPerUser;

    /**
     * @dev Tracks the total amount of tokens which have been
     * claimed by participants for each round.
     * (roundId => (participant => amount_of_tokens_claimed))
     */
    mapping(uint256 => mapping(address => uint256)) private _totalClaimsPerRoundPerUser;

    /**
     * @dev Tracks the total amount of ether that has been withdrawn
     * by the owner for a given round. Used to prevent the owner from
     * withdrawing from the contract's ether for balances which correspond
     * to active rounds. This helps prevent contract insolvency - we need
     * to ensure users can refund their tokens for an active round.
     */
    mapping(uint256 => uint256) private _amountWithdrawnFromRoundByOwner;

    /**
     * @param name Token name.
     * @param symbol Token symbol.
     * @param rounds Configuration for token sale rounds.
     * @dev Caller is assigned ownership of the contract. 
     */
    constructor(
        string memory name,
        string memory symbol,
        Round[] memory rounds
    ) ERC20(name, symbol) Ownable(msg.sender) {

        // Ensure there's at least a single round to satisfy
        // iteration logic.
        if (rounds.length == 0) revert InvalidRounds(); 

        // Ensure that each round possesses a non-zero `maximum`,
        // since our logic for validating the existence of a `Round`
        // hinges upon a round possessing a non-zero supply to
        // distribute.
        for (uint256 i; i < rounds.length;) {

            // Fetch the current round.
            Round memory round = rounds[i];

            // Ensure each round has a valid maximum.
            if (round.maximum == 0) revert InvalidRounds();

            // Ensure a valid minimum.
            if (round.minimumIndividual == 0) revert InvalidRounds();

            // Ensure a valid maximum.
            if (round.maximumIndividual > round.maximum) revert InvalidRounds();

            // Ensure the round has realistic minimum and maximum.
            if (round.maximumIndividual < round.minimumIndividual) revert InvalidRounds();

            // Store the round into storage.
            _rounds.push(round);

            unchecked { ++i; }
        }

    }
 
    /**
     * @dev We use the payable fallback to capture all ether
     * sent to the contract, for example, even in cases where
     * contracts are selfdestructed, and force feed ether to
     * this address.
     * @param proof An optional proof used when when calculating
     * whether the `msg.sender` is permitted to interact with the
     * current sales round.
     * @return amountToDeposit The amount of ether that was successfully
     * deposited. This may be less than intended due to restrictions on
     * round supply caps - in this case, exceess ether will be refunded.
     */
    function participate(bytes32[] memory proof) external payable returns (uint256 amountToDeposit) {

        // First, let's fetch the current round.
        Round memory round = _rounds[_currentRound];

        // Ensure the current round actually exists.
        if (round.maximum == 0) revert InvalidRounds();

        // Define the initial amount which the participant is attempting
        // to contribute, based on their `msg.value`.
        amountToDeposit = msg.value;

        // Fetch the callers's deposit amount for the this round.
        uint256 roundCurrentDepositsForUser = _totalDepositsPerRoundPerUser[_currentRound][msg.sender];

        // Determine the amount the caller would have deposited into the round
        // if their contribution was accepted.
        uint256 nextRoundCurrentDepositsForUser = roundCurrentDepositsForUser + amountToDeposit;

        // Ensure the caller would be depositing at least the minimum amount
        // for the current round.
        if (nextRoundCurrentDepositsForUser < round.minimumIndividual)
            revert InvalidDeposit();

        // Else, lets make sure the amount they are depositing does not exceed
        // their maximum allocation for the round.
        if (nextRoundCurrentDepositsForUser > round.maximumIndividual) {

            // If their deposit would go over the maximum, only allow the
            // difference. (Already checked.)
            unchecked {
                amountToDeposit = round.maximumIndividual - roundCurrentDepositsForUser;
            }

        }

        // Determine the global current amount deposited for this round.
        uint256 roundCurrentDeposits = _totalDepositsPerRound[_currentRound];

        // Determine whether the amount being supplied would take us
        // over the maximum amount of deposits for the current round.
        if (roundCurrentDeposits + amountToDeposit > round.maximum) {

            // If the deposit amount takes us over the total supply for
            // the round, let's try to take as much as we can. (Already checked.)
            unchecked {
                amountToDeposit = round.maximum - roundCurrentDeposits;
            }

        }

        // After validation, if the `amountToDeposit` has evaluated to zero,
        // this signifies the round has come to an end.
        if (amountToDeposit == 0) revert UnableToParticipate();

        /**
         * @dev By this point, we have validated that the deposit provided by
         * the user does not exceed the invariant bounds of the round on an individual
         * or global level. However, it is important to emphasise that the round deposit
         * logic is designed optimistically - we try to allow the user to accept as much
         * as possible, even whilst the round draws to a close and the maximum remaining
         * deposits are potentially **less than** the `minimumIndividual` deposit.
         * This is an edge case, as it only applies to the final user who is making a deposit
         * to close out an imbalanced round, but this prevents attackers from undermining
         * the deposit logic by contributing odd amounts of tokens in an effort to prevent
         * the round being closed out normally.
         */
        unchecked {
            _totalDepositsPerRoundPerUser[_currentRound][msg.sender] += amountToDeposit;
            _totalDepositsPerRound[_currentRound] += amountToDeposit; 
        }

        // Determine whether this round requires participants to
        // exist within a merkle tree - this is how we create closed
        // presale rounds.
        if (round.merkleRoot != "") {

            // Here, we use an address allowlist strategy to compute whether
            // an account is permitted to participate in the round.
            bytes32 leaf = keccak256(abi.encode(msg.sender));
            
            // Determine whether ther user exists within the allowlist. If
            // not, they cannot contribute to the current round.
            if (!MerkleProof.verify(proof, round.merkleRoot, leaf))
                revert UnableToParticipate();

        }

        // Emit an event to register that the deposit to the current round was successful.
        emit Deposit(msg.sender, _currentRound, _totalDepositsPerRound[_currentRound]);

        // Determine whether the current round has recieved all of
        // the necessary contributions.
        // If so, we can progress onto the next round. When there is
        // no following round, the token sale has ended.
        if (_totalDepositsPerRound[_currentRound] == round.maximum) {

            // Move to the next phase of sales.
            ++_currentRound;

        }

        // At this stage, we have that verified the participant has made a valid
        // contribution. Crucially, we may have accepted less than the `msg.value`,
        // so we should make sure to refund it.
        if (msg.value > amountToDeposit) {

            // Return the excess ether. (Already checked.)
            unchecked {

                (bool success, ) = payable(msg.sender).call{value: msg.value - amountToDeposit}("");

                if (!success) revert FailedToRefund();

            }

        }

    }

    /**
     * @notice Allows users to claim their tokens, which can be claimed
     * immediately after a contribution has been made to a round.
     * @param round The round the user intends to claim from.
     * @param amount Amount of tokens to claim.
     * @param recipient The address which should receive the claimed tokens.
     */
    function claim(uint256 round, uint256 amount, address recipient) external {

        // Determine the number of tokens claimed so by the user.
        uint256 totalClaimedByUser = _totalClaimsPerRoundPerUser[round][msg.sender];

        // Determine how much the user has deposited so far.
        uint256 totalDepositInRoundByUser = _totalDepositsPerRoundPerUser[round][msg.sender];

        // Ensure that the amount the user is attempting to claim does not
        // exceed the total amount deposited.
        if (totalClaimedByUser + amount > totalDepositInRoundByUser) revert FailedToClaim();

        // Track that the user has claimed some tokens.
        _totalClaimsPerRoundPerUser[round][msg.sender]+= amount;

        /**
         * @notice Mint the tokens to the recipient.
         * @dev Here we enforce a 1-1 relationship between the
         * sale tokens and ether, i.e. both are denominated in
         * wei (10 ** 18).
         */
        _mint(recipient, amount);
    }

    /**
     * @notice Permits participants to refund their deposits
     * if the current round is still active. Recipients may
     * only refund tokens which they have not already claimed.
     * @param recipient The address to refund to.
     */
    function refund(address recipient) external {

        // Determine the number of tokens claimed so by the user.
        uint256 totalClaimedByUser = _totalClaimsPerRoundPerUser[_currentRound][msg.sender];

        // Compute the number of tokens they have deposited so far.
        uint256 totalDepositInRoundByUser = _totalDepositsPerRoundPerUser[_currentRound][msg.sender];

        // Determine how many tokens the user can claim - this is how
        // much they have deposited versus how much they have claimed
        // so far.
        uint256 claimable = totalDepositInRoundByUser - totalClaimedByUser;

        // Check to see if anything can be claimed.
        if (claimable > 0) {

            // Reduce the user's current deposit by the amount they will
            // be refunding from the current round. (Already checked.)
            unchecked {
                _totalDepositsPerRoundPerUser[_currentRound][msg.sender] -= claimable;
                _totalDepositsPerRound[_currentRound] -= claimable;
            }

            // Return the ether.
            (bool success,) = payable(recipient).call{value: claimable}("");

            // If the call failed, revert with an error. The balance is left
            // unclaimed.
            if (!success) revert FailedToRefund();

        } else {

          /// @dev There are no refunds to claim.
          revert FailedToClaim();

        }

    }

    /**
     * @notice Allows the project owner to withdraw ether from a specified round.
     * @dev May only be called by the contract owner for completed rounds to avoid
     * insolvency with refunds.
     * @param round The round to withdraw ether from.
     * @param amount Amount of ether to withdraw.
     * @param recipient Address which will receive funds.
     */
    function withdraw(uint256 round, uint256 amount, address recipient) external onlyOwner {

        // Ensure the round we are withdrawing from is not an active round,
        // otherwise the contract could become insolvent if users wish to
        // have their tokens refunded.
        if (round == _currentRound) revert FailedToWithdraw();

        // Fetch the amount of ether the owner has withdrawn so far.
        uint256 amountOfTokensWithdrawn = _amountWithdrawnFromRoundByOwner[round];

        // Fetch the total amount of ether the owner can withdraw from the round.
        uint256 totalDeposits = _totalDepositsPerRound[round];

        // If the owner attempts to withdraw more balance than is contained
        // by the round, revert.
        if (amountOfTokensWithdrawn + amount > totalDeposits)
            revert InvalidWithdrawalAmount();

        // Track that more tokens have been extracted from the round.
        _amountWithdrawnFromRoundByOwner[round] += amount;

        // Attempt to send round ether to the target `recipient`.
        (bool success,) = recipient.call{value: amount}("");

        if (!success) revert FailedToWithdraw();

    }

    /**
     * @notice Permits the owner to drain the contract after the sales
     * rounds have come to a close. 
     * @param recipient Account to receive drained funds.
     */
    function drain(address recipient) external onlyOwner {

        // Only permit the contract to be drained by the `owner`
        // if the sales rounds have concluded.
        if (_currentRound < _rounds.length) revert FailedToWithdraw();

        // Attempt to send the tokens to the target `recipient`.
        (bool success,) = recipient.call{value: address(this).balance}("");

        if (!success) revert FailedToWithdraw();

    }

    /**
     * @notice Allows the `owner` to directly fund tokens to
     * a specified `recipient`. This happens adjecent to the
     * sales mechanics. Increases the total supply.
     * @param recipient Account to distribute to.
     * @param amount Amount of tokens to mint.
     */
    function distribute(address recipient, uint256 amount) external onlyOwner {
        // Mint tokens directly to the recipient.
        _mint(recipient, amount);
    }

    /**
     * @dev We use a `payable` fallback to capture any
     * ether sent to this contract. Importantly, this
     * does not interfere with the sales calculation
     * logic. Attackers may `selfdestruct` and force
     * feed ether here regardless.
     */
    receive() external payable {

        // Track the accidental ether to aid potential recovery.
        if (msg.value > 0) emit AccidentalEther(msg.sender, msg.value);

    }

}
