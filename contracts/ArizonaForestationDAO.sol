// SPDX-License-Identifier: AGPLv3
pragma solidity ^0.8.24;

/**
 * @title Arizona Forestation & Garden DAO (AfgdDao)
 * @notice Arbitrum One governance contract configured for the OBS token, 
 *         IPFS metadata linkage, and hardcoded robotic fund-allocation rules 
 *         dedicated to off-grid solar, atmospheric water generation, and 
 *         free-distribution biotech bamboo.
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

    IERC20 public immutable obsToken;
    address public immutable robotExecutionRelayer;

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
    }

    // --- State Variables ---
    address public owner;
    uint256 public proposalCount;
    mapping(uint256 => Proposal) public proposals;
    mapping(uint256 => mapping(address => bool)) public hasVoted;

    // --- Events ---
    event ProposalCreated(uint256 indexed proposalId, address proposer, uint256 requestedFunds, string description);
    event Voted(uint256 indexed proposalId, address voter, bool support, uint256 weight);
    event ProposalExecuted(uint256 indexed proposalId);
    event RobotAutomationTriggered(uint256 indexed proposalId, address indexed relayer, uint256 amountReleased);

    // --- Modifiers ---
    modifier onlyOwner() {
        require(msg.sender == owner, "Unauthorized: Owner only");
        _;
    }

    modifier onlyRobotRelayer() {
        require(msg.sender == robotExecutionRelayer, "Unauthorized: Robot hardware array only");
        _;
    }

    constructor(address _obsToken, address _robotExecutionRelayer) {
        require(_obsToken != address(0), "Invalid OBS token address");
        require(_robotExecutionRelayer != address(0), "Invalid robot relayer address");
        obsToken = IERC20(_obsToken);
        robotExecutionRelayer = _robotExecutionRelayer;
        owner = msg.sender;
    }

    // --- Proposal Creation ---
    function createProposal(
        string calldata _description,
        uint256 _requestedFunds,
        address payable _recipient
    ) external returns (uint256) {
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
            restrictedToArizonaProject: true
        });

        emit ProposalCreated(newId, msg.sender, _requestedFunds, _description);
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

    // --- Manual or Automated Execution ---
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

    // --- Autonomous Hardware Robot Execution Hook ---
    function robotExecuteApprovedProposal(uint256 _proposalId) external onlyRobotRelayer {
        Proposal storage proposal = proposals[_proposalId];
        require(block.timestamp >= proposal.endTime, "Voting period active");
        require(!proposal.executed, "Already executed");
        require(proposal.votesFor > proposal.votesAgainst, "Votes insufficient");
        require(proposal.restrictedToArizonaProject, "Must adhere to Arizona environmental charter");

        proposal.executed = true;
        require(obsToken.transfer(proposal.recipient, proposal.requestedFunds), "Robot token transfer failed");

        emit RobotAutomationTriggered(_proposalId, msg.sender, proposal.requestedFunds);
    }

    // --- Emergency Administrative Safeguards ---
    function updateOwner(address _newOwner) external onlyOwner {
        require(_newOwner != address(0), "Invalid address");
        owner = _newOwner;
    }
}
