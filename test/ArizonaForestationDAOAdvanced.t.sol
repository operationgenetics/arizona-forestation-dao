// SPDX-License-Identifier: AGPLv3
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import "../contracts/ArizonaForestationDAO.sol";

contract AdvancedMockERC20 is IERC20 {
    string public name = "Obsidian Token";
    string public symbol = "OBS";
    uint8 public decimals = 18;
    mapping(address => uint256) public balanceOf;
    mapping(address => mapping(address => uint256)) public allowance;

    bool public failTransfers;

    function setFailTransfers(bool _fail) external {
        failTransfers = _fail;
    }

    function mint(address to, uint256 amount) external {
        balanceOf[to] += amount;
    }

    function transfer(address recipient, uint256 amount) external returns (bool) {
        if (failTransfers) return false;
        require(balanceOf[msg.sender] >= amount, "Insufficient balance");
        balanceOf[msg.sender] -= amount;
        balanceOf[recipient] += amount;
        return true;
    }

    function transferFrom(address sender, address recipient, uint256 amount) external returns (bool) {
        if (failTransfers) return false;
        require(balanceOf[sender] >= amount, "Insufficient balance");
        balanceOf[sender] -= amount;
        balanceOf[recipient] += amount;
        return true;
    }
}

contract MaliciousReentrantReceiver {
    ArizonaForestationDAO public dao;
    uint256 public targetProposalId;

    constructor(address _dao) {
        dao = ArizonaForestationDAO(_dao);
    }

    function setProposal(uint256 _id) external {
        targetProposalId = _id;
    }

    // Attempt re-entry during token transfer callback
    receive() external payable {
        if (targetProposalId != 0) {
            // Try to re-execute or manipulate state
            try dao.executeProposal(targetProposalId) {} catch {}
        }
    }
}

contract ArizonaForestationDAOAdvancedTest is Test {
    ArizonaForestationDAO public dao;
    AdvancedMockERC20 public token;

    address owner = address(0x1);
    address relayer = address(0x2);
    address voter1 = address(0x3);
    address voter2 = address(0x4);
    address recipient = address(0x5);

    bytes32 constant MOCK_PQC_HASH = keccak256("HYBRID_PQC_SECURE_ARIZONA_2026");

    function setUp() public {
        vm.startPrank(owner);
        token = new AdvancedMockERC20();
        dao = new ArizonaForestationDAO(address(token), relayer);
        
        token.mint(voter1, 60_000 * 10**18); // Exceeds 50,000 quorum threshold
        token.mint(voter2, 40_000 * 10**18);
        token.mint(address(dao), 10_000_000 * 10**18);
        vm.stopPrank();
    }

    // --- SECURITY TEST 1: Double Voting Prevention ---
    function test_Security_CannotDoubleVote() public {
        vm.prank(voter1);
        dao.createProposal("Solar Array Expansion", 1000 * 10**18, payable(recipient), MOCK_PQC_HASH);

        vm.startPrank(voter1);
        dao.vote(1, true);

        // Expect revert on second vote attempt
        vm.expectRevert("Voter has already cast a ballot");
        dao.vote(1, true);
        vm.stopPrank();
    }

    // --- SECURITY TEST 2: Premature Execution Block ---
    function test_Security_CannotExecuteBeforeVotingPeriodEnds() public {
        vm.prank(voter1);
        dao.createProposal("Water Generator Maintenance", 1000 * 10**18, payable(recipient), MOCK_PQC_HASH);

        vm.prank(voter1);
        dao.vote(1, true);

        // Attempt execution immediately without skipping time
        vm.expectRevert("Voting period is still active");
        dao.executeProposal(1);
    }

    // --- SECURITY TEST 3: Quorum Enforcements ---
    function test_Security_QuorumNotReachedFails() public {
        // voter2 has 40,000 OBS (below 50,000 quorum threshold)
        vm.prank(voter2);
        dao.createProposal("Low Quorum Proposal", 1000 * 10**18, payable(recipient), MOCK_PQC_HASH);

        vm.prank(voter2);
        dao.vote(1, true);

        skip(4 days);

        vm.expectRevert("Quorum not reached");
        dao.executeProposal(1);
    }

    // --- SECURITY TEST 4: Unauthorized Relayer & Invalid PQC Hook ---
    function test_Security_UnauthorizedRelayerOrInvalidPQC() public {
        vm.prank(voter1);
        dao.createProposal("Robot Automated Irrigation", 1000 * 10**18, payable(recipient), MOCK_PQC_HASH);

        vm.prank(voter1);
        dao.vote(1, true);
        skip(4 days);

        // Attempt execution by non-relayer address
        vm.prank(voter1);
        vm.expectRevert("Unauthorized: Robot hardware array only");
        dao.robotExecuteApprovedProposal(1, MOCK_PQC_HASH);

        // Attempt execution with incorrect PQC signature hash via valid relayer
        vm.prank(relayer);
        vm.expectRevert("Hybrid PQC verification failed");
        dao.robotExecuteApprovedProposal(1, keccak256("INVALID_PQC"));
    }

    // --- SECURITY TEST 5: Zero Address Guardrails in Constructor ---
    function test_Security_ConstructorZeroAddressCheck() public {
        vm.expectRevert("Invalid OBS token address");
        new ArizonaForestationDAO(address(0), relayer);

        vm.expectRevert("Invalid robot relayer address");
        new ArizonaForestationDAO(address(token), address(0));
    }

    // --- FUZZ TESTING: Randomized Proposal Amounts & Voting Weights ---
    function testFuzz_ProposalExecution(uint256 requestAmount, uint256 voterBalance) public {
        vm.assume(requestAmount > 0 && requestAmount <= 5_000_000 * 10**18);
        vm.assume(voterBalance >= 50_000 * 10**18 && voterBalance <= 10_000_000 * 10**18);

        // Fund dynamic voter
        vm.prank(owner);
        token.mint(voter1, voterBalance);

        vm.prank(voter1);
        uint256 pid = dao.createProposal("Fuzz Test Proposal", requestAmount, payable(recipient), MOCK_PQC_HASH);

        vm.prank(voter1);
        dao.vote(pid, true);

        skip(4 days);

        uint256 balanceBefore = token.balanceOf(recipient);
        dao.executeProposal(pid);

        assertEq(token.balanceOf(recipient), balanceBefore + requestAmount);
    }
}
