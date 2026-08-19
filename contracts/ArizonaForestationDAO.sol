// SPDX-License-Identifier: AGPLv3-3.0
pragma solidity ^0.8.24;

interface IBindingCurveToken {
    function totalRaisedDAI() external view returns (uint256);
    function transferFrom(address sender, address recipient, uint256 amount) external returns (bool);
    function transfer(address recipient, uint256 amount) external returns (bool);
    function balanceOf(address account) external view returns (uint256);
}

contract ArizonaForestationDAO {
    string public constant IPFS_CID = "bafybeigdyrzt5sfp7udm7hu76uh7y26nf4dfuylqab5374y5374y5374y5";
    uint256 public constant VOTING_PERIOD = 3 days;
    uint256 public constant FUNDING_GOAL_DAI = 5_000_000_000 * 10**18;
    uint256 public constant MONTHLY_LP_GRANT = 100 * 10**18;
    uint256 public constant PROPOSAL_COST = 50 * 10**18;
    
    address public constant INITIAL_ADMIN = 0xaF570ce3b32D765b1236635B0f541a7487A1fB8e;
    address public constant OBS_TOKEN_ADDRESS = 0x2D8760e2877148d239a54952A458710553B2B54b;

    IBindingCurveToken public immutable obsToken;
    address public robotExecutionRelayer;
    bytes public robotPqcKey;

    bool public relayerLocked;
    bool public relayerUpdatePermissionRevoked;
    bool public bondingCurveFundsUnlocked;

    struct Proposal {
        uint256 id;
        address proposer;
        string description;
        uint256 requestedFunds;
        address payable recipient;
        uint256 votesFor;
        uint256 votesAgainst;
        uint256 endTime;
        bool executed;
        bool restrictedToArizonaProject;
        bytes32 pqcSignatureHash;
    }

    uint256 public proposalCount;
    mapping(uint256 => Proposal) public proposals;
    mapping(uint256 => mapping(address => bool)) public hasVoted;
    mapping(address => mapping(uint256 => uint256)) public monthlyLPBal;
    mapping(address => bool) public isMember;

    event ProposalCreated(uint256 indexed proposalId, address proposer, uint256 requestedFunds, string description, bytes32 pqcHash);
    event Voted(uint256 indexed proposalId, address voter, bool support, uint256 weight);
    event ProposalExecuted(uint256 indexed proposalId);
    event RobotAutomationTriggered(uint256 indexed proposalId, address indexed relayer, uint256 amountReleased);
    event RobotRelayerUpdated(address indexed newRelayer, bytes pqcKey);
    event RelayerPermissionRevokedAndLocked();
    event BondingCurveFundsUnlocked(uint256 totalRaisedDAI);
    event MemberJoined(address indexed member, uint256 monthIndex, uint256 grantAmount);

    modifier onlyInitialAdmin() {
        require(msg.sender == INITIAL_ADMIN, "Unauthorized: Hardcoded admin only");
        _;
    }

    modifier onlyRobotRelayer() {
        require(msg.sender == robotExecutionRelayer, "Unauthorized: Robot hardware array only");
        _;
    }

    constructor() {
        obsToken = IBindingCurveToken(OBS_TOKEN_ADDRESS);
        robotExecutionRelayer = address(0);
        relayerLocked = false;
        relayerUpdatePermissionRevoked = false;
        bondingCurveFundsUnlocked = false;
    }

    function getCurrentMonthIndex() public view returns (uint256) {
        return block.timestamp / 30 days;
    }

    function joinDAO() external {
        uint256 currentMonth = getCurrentMonthIndex();
        if (!isMember[msg.sender]) {
            isMember[msg.sender] = true;
        }
        monthlyLPBal[msg.sender][currentMonth] = MONTHLY_LP_GRANT;
        emit MemberJoined(msg.sender, currentMonth, MONTHLY_LP_GRANT);
    }

    function getVotingPower(address member) public view returns (uint256) {
        uint256 currentMonth = getCurrentMonthIndex();
        return monthlyLPBal[member][currentMonth];
    }

    function checkAndUnlockBondingCurveFunds() external returns (bool) {
        if (bondingCurveFundsUnlocked) return true;
        uint256 raisedDAI = obsToken.totalRaisedDAI();
        if (raisedDAI >= FUNDING_GOAL_DAI) {
            bondingCurveFundsUnlocked = true;
            emit BondingCurveFundsUnlocked(raisedDAI);
            return true;
        }
        return false;
    }

    function setRobotRelayer(address _newRelayer, bytes calldata _newPqcKey) external onlyInitialAdmin {
        require(!relayerUpdatePermissionRevoked, "Permission permanently revoked and contract locked");
        require(!relayerLocked, "Relayer setup is locked");
        require(_newRelayer != address(0), "Invalid relayer address");

        robotExecutionRelayer = _newRelayer;
        robotPqcKey = _newPqcKey;
        emit RobotRelayerUpdated(_newRelayer, _newPqcKey);
    }

    function revokeRelayerPermissionAndLock() external onlyInitialAdmin {
        require(!relayerUpdatePermissionRevoked, "Already revoked");
        require(robotExecutionRelayer != address(0), "Cannot lock without setting a valid robot relayer first");

        relayerUpdatePermissionRevoked = true;
        relayerLocked = true;

        emit RelayerPermissionRevokedAndLocked();
    }

    function createProposal(
        string calldata _description,
        uint256 _requestedFunds,
        address payable _recipient,
        bytes32 _pqcSignatureHash
    ) external returns (uint256) {
        require(_pqcSignatureHash != bytes32(0), "Invalid hybrid PQC signature hash");
        
        uint256 currentMonth = getCurrentMonthIndex();
        require(monthlyLPBal[msg.sender][currentMonth] >= PROPOSAL_COST, "Insufficient monthly LP tokens (needs 50)");

        monthlyLPBal[msg.sender][currentMonth] -= PROPOSAL_COST;
        
        proposalCount++;
        uint256 newId = proposalCount;

        proposals[newId] = Proposal({
            id: newId,
            proposer: msg.sender,
            description: _description,
            requestedFunds: _requestedFunds,
            recipient: _recipient,
            votesFor: 0,
            votesAgainst: 0,
            endTime: block.timestamp + VOTING_PERIOD,
            executed: false,
            restrictedToArizonaProject: true,
            pqcSignatureHash: _pqcSignatureHash
        });

        emit ProposalCreated(newId, msg.sender, _requestedFunds, _description, _pqcSignatureHash);
        return newId;
    }

    function vote(uint256 _proposalId, bool _support) external {
        Proposal storage proposal = proposals[_proposalId];
        require(block.timestamp < proposal.endTime, "Voting period has closed");
        require(!proposal.executed, "Proposal already executed");
        require(!hasVoted[_proposalId][msg.sender], "Voter has already cast a ballot");

        uint256 weight = getVotingPower(msg.sender);
        require(weight > 0, "Zero voting power: Join DAO and hold monthly LP tokens");

        uint256 currentMonth = getCurrentMonthIndex();
        monthlyLPBal[msg.sender][currentMonth] = 0;

        hasVoted[_proposalId][msg.sender] = true;

        if (_support) {
            proposal.votesFor += weight;
        } else {
            proposal.votesAgainst += weight;
        }

        emit Voted(_proposalId, msg.sender, _support, weight);
    }

    function executeProposal(uint256 _proposalId) external {
        Proposal storage proposal = proposals[_proposalId];
        require(block.timestamp >= proposal.endTime, "Voting period is still active");
        require(!proposal.executed, "Proposal already executed");
        require(proposal.votesFor > proposal.votesAgainst, "Proposal failed majority vote");
        
        require(bondingCurveFundsUnlocked || this.checkAndUnlockBondingCurveFunds(), "Bonding curve 5B DAI milestone not reached");

        proposal.executed = true;
        require(obsToken.transfer(proposal.recipient, proposal.requestedFunds), "OBS token vault transfer failed");

        emit ProposalExecuted(_proposalId);
    }

    function robotExecuteApprovedProposal(uint256 _proposalId, bytes32 _verifiedPqcProof) external onlyRobotRelayer {
        Proposal storage proposal = proposals[_proposalId];
        require(block.timestamp >= proposal.endTime, "Voting period active");
        require(!proposal.executed, "Already executed");
        require(proposal.votesFor > proposal.votesAgainst, "Votes insufficient");
        require(proposal.pqcSignatureHash == _verifiedPqcProof, "Hybrid PQC verification failed");
        require(proposal.restrictedToArizonaProject, "Must adhere to Arizona environmental charter");
        require(bondingCurveFundsUnlocked || this.checkAndUnlockBondingCurveFunds(), "Bonding curve 5B DAI milestone not reached");

        proposal.executed = true;
        require(obsToken.transfer(proposal.recipient, proposal.requestedFunds), "Robot token transfer failed");

        emit RobotAutomationTriggered(_proposalId, msg.sender, proposal.requestedFunds);
    }
}
