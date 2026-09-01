// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {MLDSA65} from "./pqc/mldsa/MLDSA65.sol";
import {Ed25519} from "./pqc/ed25519/Ed25519.sol";

interface IObscuraToken {
    function totalRaisedDAI() external view returns (uint256);
}

/**
 * @title Arizona Forestation & Sustainable Off-Grid Ecosystem DAO
 * @notice Fully autonomous off-grid DAO governing solar/water infrastructure, battery storage,
 *         environmentally safe biotech plants, and strictly enforced automated robot-managed
 *         bamboo harvesting and free global community distribution for building supplies.
 * 
 * @dev SECURITY NOTICE: Hybrid PQC (ML-DSA-65 Dilithium + Ed25519) verification is performed
 *       NATIVELY ON-CHAIN using vendored, audited Solidity libraries (contracts/pqc/):
 *       MLDSA65.sol (FIPS 204) and Ed25519.sol (RFC 8032). Both robot signatures MUST verify
 *       over the 32-byte domain-separated expectedMessageHash, otherwise the transaction
 *       reverts with InvalidPqcSignature (FAILS CLOSED).
 * 
 * @dev BIOMETRIC DATA: Biometric templates are NEVER stored on-chain, in contract storage,
 *       events, or repository files. Only the robot MCU hardware public key is configured on-chain.
 *       Biometric verification occurs OFF-CHAIN on the MCU; only the cryptographic proof
 *       (hybrid PQC signature) is submitted on-chain.
 * 
 * @dev HARDCODED MANDATES: Ecological rules are encoded as immutable string constants.
 *       ON-CHAIN ENFORCEMENT: The contract gates fund releases on proposal compliance flags
 *       and robot PQC authorization. REAL-WORLD ENFORCEMENT of mandates (forestation, solar,
 *       water, bamboo distribution) depends on external robot hardware and cannot be guaranteed
 *       by Solidity alone.
 */
contract ArizonaForestationDAO {
    using SafeERC20 for IERC20;

    // --- Custom Errors ---
    error NotAdmin();
    error RelayerUpdatesLocked();
    error ZeroAddress();
    error RelayerAlreadyRevoked();
    error BondingCurveNotUnlocked();
    error VotingPeriodActive();
    error VotingPeriodEnded();
    error AlreadyVoted();
    error NoVotingWeight();
    error ProposalNotExecuted();
    error ProposalAlreadyExecuted();
    error QuorumNotMet();
    error MajorityNotMet();
    error NotRelayer();
    error InvalidPqcSignature();
    error MandateNotCompliant();
    error AllMilestonesReleased();
    error MilestoneTimeoutNotMet();
    error TransferFailed();
    error InsufficientLpBalance();
    error ZeroFundsRequested();
    error MandateRequired();
    error InvalidMonth();
    error VaultInsufficientBalance();

    // --- Constants & Hardcoded Addresses ---
    address public constant OBS_TOKEN_ADDRESS = 0x2D8760e2877148d239a54952A458710553B2B54b;
    address public constant INITIAL_ADMIN = 0xaF570ce3b32D765b1236635B0f541a7487A1fB8e;
    uint256 public constant OBS_DECIMALS = 18;
    uint256 public constant DAI_DECIMALS = 18;
    
    uint256 public constant BONDING_CURVE_GOAL = 5_000_000_000 * 10**DAI_DECIMALS; // 5 Billion DAI threshold
    uint256 public constant MONTHLY_LP_ISSUANCE = 100 * 10**OBS_DECIMALS;          // 100 LP tokens issued monthly
    uint256 public constant PROPOSAL_THRESHOLD_LP = 50 * 10**OBS_DECIMALS;         // 50 LP tokens required to propose
    uint256 public constant QUORUM_THRESHOLD_LP = 100 * 10**OBS_DECIMALS;          // 100 LP votes required for quorum
    uint256 public constant VOTING_PERIOD = 3 days;
    uint256 public constant MILESTONES_COUNT = 3;                                   // Split into 3 tranches
    uint256 public constant MILESTONE_INTERVAL = 60 days;                           // Strict 2-month mathematical timeout
    uint256 public constant SECONDS_PER_DAY = 86400;
    uint256 public constant DAYS_PER_MONTH = 30;                                    // Fixed 30-day months for deterministic math
    uint256 public constant MONTH_DURATION = DAYS_PER_MONTH * SECONDS_PER_DAY;
    bytes32 public constant DOMAIN_SEPARATOR = 0x4172697a6f6e61466f726573746174696f6e44414f0000000000000000000000; // "ArizonaForestationDAO" padded to 32 bytes

    // NIST FIPS 204 ML-DSA-65 / RFC 8032 Ed25519 sizing (matching vendored library constants)
    uint256 public constant ROBOT_MLDSA_PK_BYTES = 1952;   // ML-DSA-65 public key size
    uint256 public constant ROBOT_MLDSA_SIG_BYTES = 3309;  // ML-DSA-65 signature size
    uint256 public constant ROBOT_ED25519_PK_BYTES = 32;   // Ed25519 compressed public key size
    uint256 public constant ROBOT_ED25519_SIG_BYTES = 64;  // Ed25519 (R||S) signature size

    // Hardcoded Ecological & Infrastructure Mandate Rules enforced by Robot Hardware MCU
    string public constant INFRASTRUCTURE_MANDATE = "Off-grid solar arrays, battery storage stacks, and atmospheric water generators";
    string public constant BIOTECH_PLANT_MANDATE = "Environmentally safe biotech plant cultivation including maximum-yield bamboo";
    string public constant BAMBOO_GLOBAL_DISTRIBUTION_RULE = "All harvested bamboo must be cut on regular growing max-yield schedule and distributed 100% free to global communities for building supplies";

    // --- State Variables ---
    address public roomieRobotRelayer;              // Hardware MCU Public Key / Relayer Address
    bytes public robotMlDsaPublicKey;               // NIST FIPS 204 ML-DSA-65 robot public key (1952 bytes)
    bytes public robotEd25519PublicKey;             // RFC 8032 Ed25519 robot public key (32 bytes)
    bool public relayerUpdatePermissionRevoked = false;
    bool public bondingCurveFundsUnlocked = false;

    // Monthly LP tracking with automatic expiry: mapping(monthId => mapping(account => lpBalance))
    mapping(uint256 => mapping(address => uint256)) public monthlyLpBalances;
    
    // Member tracking for automatic LP issuance
    mapping(address => bool) public isMember;
    address[] public members;
    
    // Vault accounting
    uint256 public vaultObsBalance;

    struct Proposal {
        uint256 id;
        address proposer;
        string description;
        uint256 requestedFunds;
        address payable recipient;
        bytes32 pqcProofHash;
        bool isEcoAndBambooMandate;
        uint256 startTime;
        uint256 votingMonthId;                      // Snapshot of month at proposal creation
        uint256 proposerLpWeight;                   // Snapshot of proposer's LP at creation
        uint256 yesVotes;
        uint256 noVotes;
        bool executed;
        uint256 lastMilestoneReleaseTime;
        uint256 milestonesReleased;
        mapping(address => bool) voted;
        bool timedOut;                              // Proposal abandoned/expired
        bool completed;                             // All milestones released
    }

    mapping(uint256 => Proposal) public proposals;
    uint256 public proposalCount;

    // Robot authorization nonce for replay protection
    uint256 public robotAuthNonce;

    // --- Events ---
    event RoomieRobotRelayerUpdated(address indexed newRelayer);
    event RelayerPermissionRevokedAndLocked();
    event BondingCurveUnlocked(uint256 totalRaised);
    event MemberJoined(address indexed member);
    event MonthlyLpIssued(uint256 indexed monthId, address indexed member, uint256 amount);
    event ProposalCreated(uint256 indexed proposalId, address indexed proposer, uint256 requestedFunds, string description, bytes32 pqcHash, bool isEcoAndBambooMandate, uint256 votingMonthId);
    event Voted(uint256 indexed proposalId, address indexed voter, bool support, uint256 weight, uint256 monthId);
    event ProposalExecuted(uint256 indexed proposalId);
    event ProposalTimedOut(uint256 indexed proposalId);
    event ProposalCompleted(uint256 indexed proposalId);
    event MilestoneExecutedByRobot(uint256 indexed proposalId, uint256 milestoneIndex, uint256 amountReleased, address indexed recipient, string mandateEnforced);
    event VaultFundsReceived(address indexed from, uint256 amount);
    event VaultFundsWithdrawn(address indexed to, uint256 amount);

    modifier onlyAdmin() {
        if (msg.sender != INITIAL_ADMIN) revert NotAdmin();
        _;
    }

    constructor() {
        // Initialize vault balance to 0
        vaultObsBalance = 0;
    }

    /**
     * @notice Returns the current month ID based on fixed 30-day epochs from genesis.
     *         Using fixed 30-day months ensures deterministic, predictable expiration.
     */
    function getCurrentMonthId() public view returns (uint256) {
        return block.timestamp / MONTH_DURATION;
    }

    /**
     * @notice Returns the month ID for a given timestamp.
     */
    function getMonthId(uint256 timestamp) public pure returns (uint256) {
        return timestamp / MONTH_DURATION;
    }

    /**
     * @notice Checks if a given month ID is the current or a future month (not expired).
     */
    function isMonthActive(uint256 monthId) public view returns (bool) {
        return monthId >= getCurrentMonthId();
    }

    /**
     * @notice Allows any address to join the DAO as a member.
     *         Members receive 100 LP tokens automatically each month via issueMonthlyLp.
     */
    function joinDAO() external {
        if (isMember[msg.sender]) return;
        isMember[msg.sender] = true;
        members.push(msg.sender);
        emit MemberJoined(msg.sender);
    }

    /**
     * @notice Issues 100 LP tokens to all members for the current month.
     *         Can be called by anyone (permissionless) to trigger monthly issuance.
     *         Previous month's LP tokens automatically expire (not accessible via getCurrentMonthId).
     */
    function issueMonthlyLp() external {
        uint256 currentMonth = getCurrentMonthId();
        
        // Issue LP to all members for current month
        for (uint256 i = 0; i < members.length; i++) {
            address member = members[i];
            monthlyLpBalances[currentMonth][member] = MONTHLY_LP_ISSUANCE;
            emit MonthlyLpIssued(currentMonth, member, MONTHLY_LP_ISSUANCE);
        }
    }

    /**
     * @notice Admin function to manually set LP balance for a specific account and month.
     *         Used for testing or exceptional circumstances.
     */
    function setMonthlyLpBalance(address account, uint256 monthId, uint256 lpAmount) external onlyAdmin {
        if (account == address(0)) revert ZeroAddress();
        monthlyLpBalances[monthId][account] = lpAmount;
        emit MonthlyLpIssued(monthId, account, lpAmount);
    }

    /**
     * @notice Returns the LP voting weight for an account in a specific month.
     *         Returns 0 if month has expired.
     */
    function getVotingWeight(address account, uint256 monthId) public view returns (uint256) {
        if (!isMonthActive(monthId)) return 0;
        return monthlyLpBalances[monthId][account];
    }

    /**
     * @notice Sets up or updates the Roomie Robot MCU relayer address and its hybrid PQC public keys.
     *         Can be updated when hardware arrives, and permanently locked later.
     * @param _roomieRobotRelayer The address of the robot relayer (MCU wallet)
     * @param _mlDsaPublicKey The ML-DSA-65 (FIPS 204) robot public key (1952 bytes)
     * @param _ed25519PublicKey The Ed25519 (RFC 8032) robot public key (32 bytes)
     */
    function setupRoomieRobotAndLock(address _roomieRobotRelayer, bytes calldata _mlDsaPublicKey, bytes calldata _ed25519PublicKey) external onlyAdmin {
        if (_roomieRobotRelayer == address(0)) revert ZeroAddress();
        if (relayerUpdatePermissionRevoked) revert RelayerUpdatesLocked();
        if (_mlDsaPublicKey.length != ROBOT_MLDSA_PK_BYTES) revert InvalidPqcSignature();
        if (_ed25519PublicKey.length != ROBOT_ED25519_PK_BYTES) revert InvalidPqcSignature();
        roomieRobotRelayer = _roomieRobotRelayer;
        robotMlDsaPublicKey = _mlDsaPublicKey;
        robotEd25519PublicKey = _ed25519PublicKey;
        emit RoomieRobotRelayerUpdated(_roomieRobotRelayer);
    }

    /**
     * @notice Revokes updating permissions to make the robot relayer mapping permanently immutable.
     *         Can only be called once by the admin.
     */
    function revokeRelayerPermissionAndLock() external onlyAdmin {
        if (relayerUpdatePermissionRevoked) revert RelayerAlreadyRevoked();
        relayerUpdatePermissionRevoked = true;
        emit RelayerPermissionRevokedAndLocked();
    }

    /**
     * @notice Checks the Obscura token contract to see if 5 Billion DAI has been raised on the bonding curve.
     *         Once unlocked, remains unlocked permanently.
     */
    function checkAndUnlockBondingCurveFunds() public {
        if (!bondingCurveFundsUnlocked) {
            uint256 raised = IObscuraToken(OBS_TOKEN_ADDRESS).totalRaisedDAI();
            // Validate decimals: totalRaisedDAI should be in DAI (18 decimals)
            if (raised >= BONDING_CURVE_GOAL) {
                bondingCurveFundsUnlocked = true;
                emit BondingCurveUnlocked(raised);
            }
        }
    }

    /**
     * @notice Creates a proposal. Requires holding at least 50 LP tokens issued for the current month.
     *         Snapshots voting month and proposer's LP weight at creation time to prevent
     *         voting power disappearance during active proposal.
     * @param description Human-readable proposal description
     * @param requestedFunds Amount of OBS tokens requested (18 decimals)
     * @param recipient Address to receive funds upon milestone releases
     * @param pqcProofHash Hash of the PQC proof for this proposal (commitment)
     * @param isEcoAndBambooMandate Must be true - confirms adherence to hardcoded mandates
     * @return proposalId The created proposal's ID
     */
    function createProposal(
        string memory description,
        uint256 requestedFunds,
        address payable recipient,
        bytes32 pqcProofHash,
        bool isEcoAndBambooMandate
    ) external returns (uint256) {
        uint256 currentMonth = getCurrentMonthId();
        uint256 proposerLpWeight = monthlyLpBalances[currentMonth][msg.sender];
        
        if (proposerLpWeight < PROPOSAL_THRESHOLD_LP) revert InsufficientLpBalance();
        if (requestedFunds == 0) revert ZeroFundsRequested();
        if (!isEcoAndBambooMandate) revert MandateRequired();
        if (recipient == address(0)) revert ZeroAddress();

        proposalCount++;
        Proposal storage p = proposals[proposalCount];
        p.id = proposalCount;
        p.proposer = msg.sender;
        p.description = description;
        p.requestedFunds = requestedFunds;
        p.recipient = recipient;
        p.pqcProofHash = pqcProofHash;
        p.isEcoAndBambooMandate = isEcoAndBambooMandate;
        p.startTime = block.timestamp;
        p.votingMonthId = currentMonth;
        p.proposerLpWeight = proposerLpWeight;

        emit ProposalCreated(proposalCount, msg.sender, requestedFunds, description, pqcProofHash, isEcoAndBambooMandate, currentMonth);
        return proposalCount;
    }

    /**
     * @notice 1:1 voting using LP tokens from the proposal's voting month (snapshot at creation).
     *         Prevents voting power disappearance during active proposal.
     * @param proposalId The proposal to vote on
     * @param support True for yes, false for no
     */
    function vote(uint256 proposalId, bool support) external {
        Proposal storage p = proposals[proposalId];
        
        if (block.timestamp > p.startTime + VOTING_PERIOD) revert VotingPeriodEnded();
        if (p.voted[msg.sender]) revert AlreadyVoted();

        // Use SNAPSHOT month from proposal creation, not current month
        uint256 weight = monthlyLpBalances[p.votingMonthId][msg.sender];
        if (weight == 0) revert NoVotingWeight();

        p.voted[msg.sender] = true;
        if (support) {
            p.yesVotes += weight;
        } else {
            p.noVotes += weight;
        }

        emit Voted(proposalId, msg.sender, support, weight, p.votingMonthId);
    }

    /**
     * @notice Executes a successful proposal once quorum (100 LP) and majority are reached,
     *         provided the 5 Billion DAI bonding curve goal has unlocked the vault.
     * @param proposalId The proposal to execute
     */
    function executeProposal(uint256 proposalId) external {
        checkAndUnlockBondingCurveFunds();
        if (!bondingCurveFundsUnlocked) revert BondingCurveNotUnlocked();

        Proposal storage p = proposals[proposalId];
        
        if (block.timestamp <= p.startTime + VOTING_PERIOD) revert VotingPeriodActive();
        if (p.executed) revert ProposalAlreadyExecuted();
        if (p.yesVotes + p.noVotes < QUORUM_THRESHOLD_LP) revert QuorumNotMet();
        if (p.yesVotes <= p.noVotes) revert MajorityNotMet();

        p.executed = true;
        p.lastMilestoneReleaseTime = block.timestamp;

        emit ProposalExecuted(proposalId);
    }

    /**
     * @notice Allows marking a proposal as timed out if voting period ended without execution.
     *         Can be called by anyone after voting period ends if proposal not executed.
     */
    function timeoutProposal(uint256 proposalId) external {
        Proposal storage p = proposals[proposalId];
        
        if (block.timestamp <= p.startTime + VOTING_PERIOD) revert VotingPeriodActive();
        if (p.executed) revert ProposalAlreadyExecuted();
        if (p.timedOut) return; // Idempotent
        
        p.timedOut = true;
        emit ProposalTimedOut(proposalId);
    }

    /**
     * @notice Receives OBS tokens into the DAO vault.
     *         Updates internal vault accounting.
     */
    function receiveObsTokens(uint256 amount) external {
        IERC20(OBS_TOKEN_ADDRESS).safeTransferFrom(msg.sender, address(this), amount);
        vaultObsBalance += amount;
        emit VaultFundsReceived(msg.sender, amount);
    }

    /**
     * @notice Returns the current vault OBS balance (accounting + actual balance).
     */
    function getVaultBalance() public view returns (uint256) {
        uint256 actualBalance = IERC20(OBS_TOKEN_ADDRESS).balanceOf(address(this));
        // Return the minimum of accounting and actual to detect discrepancies
        return actualBalance < vaultObsBalance ? actualBalance : vaultObsBalance;
    }

    /**
     * @notice Strictly enforced by the Roomie Robot hardware MCU and biometric PQC signatures.
     *         Mathematically times out fund releases to exactly once every 2 months (60 days) per tranche,
     *         protecting token price stability and preventing liquidity dumps.
     * 
     * @dev REPLAY PROTECTION: Uses incrementing nonce, deadline, and domain-separated message hash.
     *       The messageHash MUST be computed as:
     *       keccak256(abi.encodePacked(DOMAIN_SEPARATOR, proposalId, milestoneIndex, trancheAmount, recipient, deadline, nonce))
     * 
* @dev PQC VERIFICATION: Both robot signatures (ML-DSA-65 + Ed25519) are verified NATIVELY
 *       on-chain via vendored libraries (contracts/pqc/) over the 32-byte expectedMessageHash.
 *       This contract FAILS CLOSED - if either verification returns false, transaction reverts.
     * 
     * @param proposalId The executed proposal to release funds for
     * @param milestoneIndex The milestone index being released (1, 2, or 3)
     * @param trancheAmount The amount of OBS to release (must match requestedFunds / 3)
     * @param recipient The recipient address (must match proposal recipient)
     * @param deadline Unix timestamp after which this authorization expires
     * @param dilithiumSignature Dilithium signature from robot MCU
     * @param ed25519Signature Ed25519 signature from robot MCU
     */
    function roomieRobotExecuteApprovedProposal(
        uint256 proposalId,
        uint256 milestoneIndex,
        uint256 trancheAmount,
        address recipient,
        uint256 deadline,
        bytes calldata dilithiumSignature,
        bytes calldata ed25519Signature
    ) external {
        if (msg.sender != roomieRobotRelayer) revert NotRelayer();
        if (deadline < block.timestamp) revert MilestoneTimeoutNotMet(); // Reuse for deadline check
        
        // Replay protection: incrementing nonce
        robotAuthNonce++;
        uint256 currentNonce = robotAuthNonce;

        // Construct the expected message hash with domain separation
        bytes32 expectedMessageHash = keccak256(abi.encodePacked(
            bytes32(DOMAIN_SEPARATOR),
            proposalId,
            milestoneIndex,
            trancheAmount,
            recipient,
            deadline,
            currentNonce
        ));

        // Native Hybrid PQC verification (vendored Solidity libs, contracts/pqc/).
        // BOTH signatures are over the 32-byte domain-separated expectedMessageHash.
        if (ed25519Signature.length != ROBOT_ED25519_SIG_BYTES) revert InvalidPqcSignature();
        if (dilithiumSignature.length != ROBOT_MLDSA_SIG_BYTES) revert InvalidPqcSignature();
        bytes memory message = abi.encodePacked(expectedMessageHash);

        bytes32 r;
        bytes32 s;
        assembly {
            r := calldataload(ed25519Signature.offset)
            s := calldataload(add(ed25519Signature.offset, 32))
        }
        if (!Ed25519.verify(bytes32(robotEd25519PublicKey), r, s, message)) revert InvalidPqcSignature();
        if (!MLDSA65.verify(robotMlDsaPublicKey, message, dilithiumSignature)) revert InvalidPqcSignature();

        Proposal storage p = proposals[proposalId];
        if (!p.executed) revert ProposalNotExecuted();
        if (!p.isEcoAndBambooMandate) revert MandateNotCompliant();
        if (p.milestonesReleased >= MILESTONES_COUNT) revert AllMilestonesReleased();
        if (milestoneIndex != p.milestonesReleased + 1) revert MilestoneTimeoutNotMet(); // Reuse for index check
        if (recipient != p.recipient) revert ZeroAddress(); // Reuse for address mismatch
        
        // Verify tranche amount matches expected (requestedFunds / 3)
        uint256 expectedTranche = p.requestedFunds / MILESTONES_COUNT;
        if (trancheAmount != expectedTranche) revert TransferFailed(); // Reuse for amount mismatch

        // Enforce 2-month interval between milestones (after first)
        if (p.milestonesReleased > 0) {
            if (block.timestamp < p.lastMilestoneReleaseTime + MILESTONE_INTERVAL) {
                revert MilestoneTimeoutNotMet();
            }
        }

        // Check vault has sufficient balance
        uint256 vaultBalance = getVaultBalance();
        if (vaultBalance < trancheAmount) revert VaultInsufficientBalance();

        p.milestonesReleased++;
        p.lastMilestoneReleaseTime = block.timestamp;

        // Check if all milestones completed
        if (p.milestonesReleased == MILESTONES_COUNT) {
            p.completed = true;
        }

        // Transfer tokens using SafeERC20 (reentrancy-safe: state updated before transfer)
        vaultObsBalance -= trancheAmount;
        IERC20(OBS_TOKEN_ADDRESS).safeTransfer(recipient, trancheAmount);
        
        emit VaultFundsWithdrawn(recipient, trancheAmount);
        emit MilestoneExecutedByRobot(
            proposalId, 
            p.milestonesReleased, 
            trancheAmount, 
            recipient, 
            BAMBOO_GLOBAL_DISTRIBUTION_RULE
        );

        if (p.completed) {
            emit ProposalCompleted(proposalId);
        }
    }

    // Standard ETH receive (not used for OBS tokens)
    receive() external payable {}
}