// SPDX-License-Identifier: AGPLv3-3.0
pragma solidity ^0.8.24;

interface IBindingCurveToken {
    function totalRaisedDAI() external view returns (uint256);
    function transfer(address recipient, uint256 amount) external returns (bool);
    function transferFrom(address sender, address recipient, uint256 amount) external returns (bool);
    function balanceOf(address account) external view returns (uint256);
}

contract ArizonaForestationDAO {
    address public immutable INITIAL_ADMIN = 0xaF570ce3b32D765b1236635B0f541a7487A1fB8e;
    address public constant OBS_TOKEN_ADDRESS = 0x2D8760e2877148d239a54952A458710553B2B54b;
    
    uint256 public constant FUNDING_GOAL_DAI = 5_000_000_000 * 10**18;
    uint256 public constant MONTHLY_LP_GRANT = 100 * 10**18;
    uint256 public constant PROPOSAL_COST = 50 * 10**18;
    uint256 public constant VOTING_PERIOD = 3 days;
    uint256 public constant TIMELOCK_DELAY = 1 days;

    address public robotExecutionRelayer;
    bytes public robotPqcPublicKey;
    bool public relayerUpdatePermissionRevoked;
    bool public relayerLocked;

    struct Member {
        uint256 joinTimestamp;
        uint256 lastGrantTimestamp;
        bool active;
    }

    struct Proposal {
        uint256 id;
        address proposer;
        string description;
        uint256 requestedFunds;
        address payable recipient;
        uint256 votesFor;
        uint256 votesAgainst;
        uint256 endTime;
        uint256 executionTime;
        bool executed;
        bytes32 pqcHash;
    }

    mapping(address => Member) public members;
    mapping(uint256 => Proposal) public proposals;
    mapping(uint256 => mapping(address => bool)) public hasVoted;
    uint256 public proposalCount;

    event MemberJoined(address indexed member, uint256 monthIndex, uint256 grantAmount);
    event ProposalCreated(uint256 indexed proposalId, address indexed proposer, uint256 requestedFunds, string description, bytes32 pqcHash);
    event Voted(uint256 indexed proposalId, address indexed voter, bool support, uint256 weight);
    event ProposalExecuted(uint256 indexed proposalId);
    event RobotRelayerUpdated(address indexed newRelayer);
    event RelayerPermissionRevokedAndLocked();

    modifier onlyAdmin() {
        require(msg.sender == INITIAL_ADMIN, "Only admin");
        _;
    }

    function setRobotRelayer(address _relayer, bytes calldata _pqcKey) external onlyAdmin {
        require(!relayerLocked, "Permission permanently revoked and contract locked");
        robotExecutionRelayer = _relayer;
        robotPqcPublicKey = _pqcKey;
        emit RobotRelayerUpdated(_relayer);
    }

    function revokeRelayerPermissionAndLock() external onlyAdmin {
        require(!relayerUpdatePermissionRevoked, "Already revoked");
        relayerUpdatePermissionRevoked = true;
        relayerLocked = true;
        emit RelayerPermissionRevokedAndLocked();
    }

    function joinDAO() external {
        Member storage member = members[msg.sender];
        if (!member.active) {
            member.joinTimestamp = block.timestamp;
            member.active = true;
        }
        member.lastGrantTimestamp = block.timestamp;
        emit MemberJoined(msg.sender, block.timestamp / 30 days, MONTHLY_LP_GRANT);
    }

    function isMember(address account) public view returns (bool) {
        Member memory member = members[account];
        if (!member.active) return false;
        if (block.timestamp > member.lastGrantTimestamp + 30 days) return false;
        return true;
    }

    function getVotingPower(address account) public view returns (uint256) {
        if (!isMember(account)) return 0;
        return MONTHLY_LP_GRANT;
    }

    function createProposal(
        string calldata description,
        uint256 requestedFunds,
        address payable recipient,
        bytes32 pqcHash
    ) external returns (uint256) {
        require(isMember(msg.sender), "Must be active DAO member");
        require(getVotingPower(msg.sender) >= PROPOSAL_COST, "Insufficient LP balance for proposal fee");
        
        proposalCount++;
        proposals[proposalCount] = Proposal({
            id: proposalCount,
            proposer: msg.sender,
            description: description,
            requestedFunds: requestedFunds,
            recipient: recipient,
            votesFor: 0,
            votesAgainst: 0,
            endTime: block.timestamp + VOTING_PERIOD,
            executionTime: block.timestamp + VOTING_PERIOD + TIMELOCK_DELAY,
            executed: false,
            pqcHash: pqcHash
        });
        emit ProposalCreated(proposalCount, msg.sender, requestedFunds, description, pqcHash);
        return proposalCount;
    }

    function vote(uint256 proposalId, bool support) external {
        require(isMember(msg.sender), "Must be active DAO member");
        Proposal storage proposal = proposals[proposalId];
        require(block.timestamp < proposal.endTime, "Voting has ended");
        require(!hasVoted[proposalId][msg.sender], "Voter has already cast a ballot");

        uint256 weight = getVotingPower(msg.sender);
        require(weight > 0, "No voting power");

        hasVoted[proposalId][msg.sender] = true;
        if (support) {
            proposal.votesFor += weight;
        } else {
            proposal.votesAgainst += weight;
        }
        emit Voted(proposalId, msg.sender, support, weight);
    }

    function checkAndUnlockBondingCurveFunds() public view returns (bool) {
        uint256 raised = IBindingCurveToken(OBS_TOKEN_ADDRESS).totalRaisedDAI();
        return raised >= FUNDING_GOAL_DAI;
    }

    function executeProposal(uint256 proposalId) external {
        Proposal storage proposal = proposals[proposalId];
        require(!proposal.executed, "Proposal already executed");
        require(block.timestamp >= proposal.executionTime, "Timelock not expired");
        require(proposal.votesFor > proposal.votesAgainst, "Proposal failed");
        require(checkAndUnlockBondingCurveFunds(), "Funding goal not reached");

        proposal.executed = true;
        bool success = IBindingCurveToken(OBS_TOKEN_ADDRESS).transfer(proposal.recipient, proposal.requestedFunds);
        require(success, "Token transfer failed");
        emit ProposalExecuted(proposalId);
    }
}
