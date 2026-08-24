// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

interface IObscuraToken {
    function totalRaisedDAI() external view returns (uint256);
    function verifyHybridSignature(
        address signer,
        bytes32 messageHash,
        bytes calldata dilithiumSignature,
        bytes calldata ed25519Signature
    ) external view returns (bool);
}

/**
 * @title Arizona Forestation & Sustainable Off-Grid Ecosystem DAO
 * @notice Fully autonomous off-grid DAO governing solar/water infrastructure, battery storage, 
 *         environmentally safe biotech plants, and strictly enforced automated robot-managed 
 *         bamboo harvesting and free global community distribution for building supplies.
 */
contract ArizonaForestationDAO {
    // --- Constants & Hardcoded Addresses ---
    address public constant OBS_TOKEN_ADDRESS = 0x2D8760e2877148d239a54952A458710553B2B54b;
    address public constant INITIAL_ADMIN = 0xaF570ce3b32D765b1236635B0f541a7487A1fB8e;
    
    uint256 public constant BONDING_CURVE_GOAL = 5_000_000_000 * 10**18; // 5 Billion DAI
    uint256 public constant PROPOSAL_THRESHOLD_LP = 50 * 10**18;      // 50 LP tokens required to propose
    uint256 public constant QUORUM_THRESHOLD_LP = 100 * 10**18;     // 100 LP votes required for quorum
    uint256 public constant VOTING_PERIOD = 3 days;
    uint256 public constant MILESTONES_COUNT = 3;                     // Split into 3 tranches (every 2 months)
    uint256 public constant MILESTONE_INTERVAL = 60 days;             // Robot strict MCU pacing

    // Hardcoded Ecological & Infrastructure Mandate Rules enforced by Robot Hardware
    string public constant INFRASTRUCTURE_MANDATE = "Off-grid solar arrays, battery storage stacks, and atmospheric water generators";
    string public constant BIOTECH_PLANT_MANDATE = "Environmentally safe biotech plant cultivation including maximum-yield bamboo";
    string public constant BAMBOO_GLOBAL_DISTRIBUTION_RULE = "All harvested bamboo must be cut on regular growing max-yield schedule and distributed 100% free to global communities for building supplies";

    // --- State Variables ---
    address public roomieRobotRelayer; // Hardware MCU Public Key / Relayer Address
    bool public relayerUpdatePermissionRevoked = false;
    bool public bondingCurveFundsUnlocked = false;

    // Monthly LP tracking: mapping(monthId => mapping(account => lpBalance))
    mapping(uint256 => mapping(address => uint256)) public monthlyLpBalances;

    struct Proposal {
        uint256 id;
        address proposer;
        string description;
        uint256 requestedFunds;
        address payable recipient;
        bytes32 pqcProofHash;
        bool isEcoAndBambooMandate;
        uint256 startTime;
        uint256 yesVotes;
        uint256 noVotes;
        bool executed;
        uint256 lastMilestoneReleaseTime;
        uint256 milestonesReleased;
        mapping(address => bool) voted;
    }

    mapping(uint256 => Proposal) public proposals;
    uint256 public proposalCount;

    // --- Events ---
    event RoomieRobotRelayerUpdated(address indexed newRelayer);
    event RelayerPermissionRevokedAndLocked();
    event BondingCurveUnlocked(uint256 totalRaised);
    event ProposalCreated(uint256 indexed proposalId, address indexed proposer, uint256 requestedFunds, string description, bytes32 pqcHash, bool isEcoAndBambooMandate);
    event Voted(uint256 indexed proposalId, address indexed voter, bool support, uint256 weight, uint256 monthId);
    event MilestoneExecutedByRobot(uint256 indexed proposalId, uint256 milestoneIndex, uint256 amountReleased, address recipient, string mandateEnforced);

    modifier onlyAdmin() {
        require(msg.sender == INITIAL_ADMIN, "ArizonaForestationDAO: Caller is not the hardcoded admin");
        _;
    }

    constructor() {}

    function setupRoomieRobotAndLock(address _roomieRobotRelayer) external onlyAdmin {
        require(!relayerUpdatePermissionRevoked, "ArizonaForestationDAO: Relayer updates permanently locked");
        roomieRobotRelayer = _roomieRobotRelayer;
        emit RoomieRobotRelayerUpdated(_roomieRobotRelayer);
    }

    function revokeRelayerPermissionAndLock() external onlyAdmin {
        require(!relayerUpdatePermissionRevoked, "ArizonaForestationDAO: Already revoked");
        relayerUpdatePermissionRevoked = true;
        emit RelayerPermissionRevokedAndLocked();
    }

    function checkAndUnlockBondingCurveFunds() public {
        if (!bondingCurveFundsUnlocked) {
            uint256 raised = IObscuraToken(OBS_TOKEN_ADDRESS).totalRaisedDAI();
            if (raised >= BONDING_CURVE_GOAL) {
                bondingCurveFundsUnlocked = true;
                emit BondingCurveUnlocked(raised);
            }
        }
    }

    function recordMonthlyLpBalance(address account, uint256 lpAmount) external onlyAdmin {
        uint256 currentMonth = block.timestamp / 30 days;
        monthlyLpBalances[currentMonth][account] = lpAmount;
    }

    function createProposal(
        string memory description,
        uint256 requestedFunds,
        address payable recipient,
        bytes32 pqcProofHash,
        bool isEcoAndBambooMandate
    ) external returns (uint256) {
        uint256 currentMonth = block.timestamp / 30 days;
        require(monthlyLpBalances[currentMonth][msg.sender] >= PROPOSAL_THRESHOLD_LP, "Insufficient monthly LP balance (50 LP required)");
        require(requestedFunds > 0, "Requested funds must be > 0");
        require(isEcoAndBambooMandate, "Must strictly adhere to Arizona forestation, solar, water, and free bamboo mandates");

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

        emit ProposalCreated(proposalCount, msg.sender, requestedFunds, description, pqcProofHash, isEcoAndBambooMandate);
        return proposalCount;
    }

    function vote(uint256 proposalId, bool support) external {
        Proposal storage p = proposals[proposalId];
        require(block.timestamp <= p.startTime + VOTING_PERIOD, "Voting period ended");
        require(!p.voted[msg.sender], "Already voted");

        uint256 currentMonth = p.startTime / 30 days;
        uint256 weight = monthlyLpBalances[currentMonth][msg.sender];
        require(weight > 0, "No active LP voting weight for this month");

        p.voted[msg.sender] = true;
        if (support) {
            p.yesVotes += weight;
        } else {
            p.noVotes += weight;
        }

        emit Voted(proposalId, msg.sender, support, weight, currentMonth);
    }

    function executeProposal(uint256 proposalId) external {
        checkAndUnlockBondingCurveFunds();
        require(bondingCurveFundsUnlocked, "Bonding curve 5B DAI goal not yet reached");

        Proposal storage p = proposals[proposalId];
        require(block.timestamp > p.startTime + VOTING_PERIOD, "Voting still active");
        require(!p.executed, "Already executed");
        require(p.yesVotes + p.noVotes >= QUORUM_THRESHOLD_LP, "Quorum not met (100 LP required)");
        require(p.yesVotes > p.noVotes, "Did not pass majority");

        p.executed = true;
        p.lastMilestoneReleaseTime = block.timestamp;
    }

    /**
     * @notice Strictly enforced by the Roomie Robot hardware MCU and biometric PQC signatures.
     *         Releases funds only once every 2 months per project tranche, ensuring continuous bamboo 
     *         harvesting, free community building supply distribution, and solar/water infrastructure execution 
     *         without crashing token liquidity.
     */
    function roomieRobotExecuteApprovedProposal(
        uint256 proposalId,
        bytes32 messageHash,
        bytes calldata dilithiumSignature,
        bytes calldata ed25519Signature
    ) external {
        require(msg.sender == roomieRobotRelayer, "Caller is not Roomie Robot relayer/MCU");
        
        bool isValidPqc = IObscuraToken(OBS_TOKEN_ADDRESS).verifyHybridSignature(
            INITIAL_ADMIN,
            messageHash,
            dilithiumSignature,
            ed25519Signature
        );
        require(isValidPqc, "Invalid Hybrid PQC & Biometric signature on Robot MCU");

        Proposal storage p = proposals[proposalId];
        require(p.executed, "Proposal not yet executed by DAO");
        require(p.isEcoAndBambooMandate, "Proposal lacks mandatory ecological/bamboo rules");
        require(p.milestonesReleased < MILESTONES_COUNT, "All milestone tranches completed");

        if (p.milestonesReleased > 0) {
            require(
                block.timestamp >= p.lastMilestoneReleaseTime + MILESTONE_INTERVAL,
                "Robot MCU Pacing: Strictly enforces 2-month interval between fund releases"
            );
        }

        p.milestonesReleased++;
        p.lastMilestoneReleaseTime = block.timestamp;

        uint256 trancheAmount = p.requestedFunds / MILESTONES_COUNT;
        bool success = IERC20(OBS_TOKEN_ADDRESS).transfer(p.recipient, trancheAmount);
        require(success, "DAO vault token transfer failed");

        emit MilestoneExecutedByRobot(
            proposalId, 
            p.milestonesReleased, 
            trancheAmount, 
            p.recipient, 
            BAMBOO_GLOBAL_DISTRIBUTION_RULE
        );
    }

    receive() external payable {}
}
