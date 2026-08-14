// SPDX-License-Identifier: AGPLv3
pragma solidity ^0.8.24;

/**
 * @title Arizona Forestation & Garden DAO (AfgdDao) with Revocable Hardware Relayer & Immutable Lock
 * @notice Arbitrum One governance contract configured for the OBS token, hybrid PQC hashes, 
 *         IPFS metadata linkage, and a strictly revocable/lockable hardware relayer registration window.
 */

interface IERC20 {
    function transferFrom(address sender, address recipient, uint256 amount) external returns (bool);
    function transfer(address recipient, uint256 amount) external returns (bool);
    function balanceOf(address account) external view returns (uint256);
}

contract ArizonaForestationDAO {

    // --- Constants & Metadata ---
    string public constant IPFS_CID = "bafybeigdyrzt5sfp7udm7hu76uh7y26nf4dfuylqab5374y5374y5374y5";
    uint256 public constant VOTING_PERIOD = 3 days;
    uint256 public constant QUORUM_THRESHOLD = 50_000 * 10**18;
    
    // Hardcoded administrative setup address authorized to set or revoke the robot relayer once
    address public constant INITIAL_ADMIN = 0xbe53702c6f57af155410f883f38f92414d39e3d5;

    IERC20 public immutable obsToken;
    address public robotExecutionRelayer;
    address public owner;

    // --- Security States ---
    bool public relayerLocked;
    bool public relayerUpdatePermissionRevoked;

    // --- Structs ---
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

    // --- State Variables ---
    uint256 public proposalCount;
    mapping(uint256 => Proposal) public proposals;
    mapping(uint256 => mapping(address => bool)) public hasVoted;

    // --- Events ---
    event ProposalCreated(uint256 indexed proposalId, address proposer, uint256 requestedFunds, string description, bytes32 pqcHash);
    event Voted(uint256 indexed proposalId, address voter, bool support, uint256 weight);
    event ProposalExecuted(uint256 indexed proposalId);
    event RobotAutomationTriggered(uint256 indexed proposalId, address indexed relayer, uint256 amountReleased);
    event RobotRelayerUpdated(address indexed newRelayer);
    event RelayerPermissionRevokedAndLocked();

    // --- Modifiers ---
    modifier onlyOwner() {
        require(msg.sender == owner, "Unauthorized: Owner only");
        _;
    }

    modifier onlyInitialAdmin() {
        require(msg.sender == INITIAL_ADMIN, "Unauthorized: Hardcoded admin only");
        _;
    }

    modifier onlyRobotRelayer() {
        require(msg.sender == robotExecutionRelayer, "Unauthorized: Robot hardware array only");
        _;
    }

    constructor(address _obsToken) {
        require(_obsToken != address(0), "Invalid OBS token address");
        obsToken = IERC20(_obsToken);
        owner = msg.sender;
        // Robot relayer starts unassigned (address(0)) until the hardcoded admin registers it upon delivery
        robotExecutionRelayer = address(0);
        relayerLocked = false;
        relayerUpdatePermissionRevoked = false;
    }

    // --- One-Time Hardware Relayer Assignment by INITIAL_ADMIN ---
    function setRobotRelayer(address _newRelayer) external onlyInitialAdmin {
        require(!relayerUpdatePermissionRevoked, "Permission permanently revoked and contract locked");
        require(!relayerLocked, "Relayer setup is locked");
        require(_newRelayer != address(0), "Invalid relayer address");

        robotExecutionRelayer = _newRelayer;
        emit RobotRelayerUpdated(_newRelayer);
    }

    // --- Revoke Update Permission & Lock Contract Permanently ---
    function revokeRelayerPermissionAndLock() external onlyInitialAdmin {
        require(!relayerUpdatePermissionRevoked, "Already revoked");
        require(robotExecutionRelayer != address(0), "Cannot lock without setting a valid robot relayer first");

        relayerUpdatePermissionRevoked = true;
        relayerLocked = true;

        emit RelayerPermissionRevokedAndLocked();
    }

    // --- Proposal Creation with Hybrid PQC Hash ---
    function createProposal(
        string calldata _description,
        uint256 _requestedFunds,
        address payable _recipient,
        bytes32 _pqcSignatureHash
    ) external returns (uint256) {
        require(_pqcSignatureHash != bytes32(0), "Invalid hybrid PQC signature hash");
        
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

    // --- Voting System ---
    function vote(uint256 _proposalId, bool _support) external {
        Proposal storage proposal = proposals[_proposalId];
        require(block.timestamp < proposal.endTime, "Voting period has closed");
        require(!proposal.executed, "Proposal already executed");
        require(!hasVoted[_proposalId][msg.sender], "Voter has already cast a ballot");

        uint256 weight = obsToken.balanceOf(msg.sender);
        require(weight > 0, "Zero voting power: Hold OBS tokens to participate");

        hasVoted[_proposalId][msg.sender] = true;

        if (_support) {
            proposal.votesFor += weight;
        } else {
            proposal.votesAgainst += weight;
        }

        emit Voted(_proposalId, msg.sender, _support, weight);
    }

    // --- Manual Execution ---
    function executeProposal(uint256 _proposalId) external {
        Proposal storage proposal = proposals[_proposalId];
        require(block.timestamp >= proposal.endTime, "Voting period is still active");
        require(!proposal.executed, "Proposal already executed");
        require(proposal.votesFor > proposal.votesAgainst, "Proposal failed majority vote");
        require((proposal.votesFor + proposal.votesAgainst) >= QUORUM_THRESHOLD, "Quorum not reached");

        proposal.executed = true;
        require(obsToken.transfer(proposal.recipient, proposal.requestedFunds), "OBS token transfer failed");

        emit ProposalExecuted(_proposalId);
    }

    // --- Autonomous Hardware Robot Execution Hook with PQC Verification ---
    function robotExecuteApprovedProposal(uint256 _proposalId, bytes32 _verifiedPqcProof) external onlyRobotRelayer {
        Proposal storage proposal = proposals[_proposalId];
        require(block.timestamp >= proposal.endTime, "Voting period active");
        require(!proposal.executed, "Already executed");
        require(proposal.votesFor > proposal.votesAgainst, "Votes insufficient");
        require(proposal.pqcSignatureHash == _verifiedPqcProof, "Hybrid PQC verification failed");
        require(proposal.restrictedToArizonaProject, "Must adhere to Arizona environmental charter");

        proposal.executed = true;
        require(obsToken.transfer(proposal.recipient, proposal.requestedFunds), "Robot token transfer failed");

        emit RobotAutomationTriggered(_proposalId, msg.sender, proposal.requestedFunds);
    }

    // --- Administrative Safeguards ---
    function updateOwner(address _newOwner) external onlyOwner {
        require(_newOwner != address(0), "Invalid address");
        owner = _newOwner;
    }
}
