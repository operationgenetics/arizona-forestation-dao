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

contract ArizonaForestationDAOAdvancedTest is Test {
    ArizonaForestationDAO public dao;
    AdvancedMockERC20 public token;

    address owner = address(0x1);
    address constant HARDCODED_ADMIN = 0xBe53702c6f57aF155410f883f38f92414d39E3d5;
    address relayer = address(0x2);
    address voter1 = address(0x3);
    address voter2 = address(0x4);
    address recipient = address(0x5);

    bytes32 constant MOCK_PQC_HASH = keccak256("HYBRID_PQC_SECURE_ARIZONA_2026");

    function setUp() public {
        vm.startPrank(owner);
        token = new AdvancedMockERC20();
        dao = new ArizonaForestationDAO(address(token));
        
        // Register and lock relayer via hardcoded admin for testing relayer hooks
        vm.startPrank(HARDCODED_ADMIN);
        dao.setRobotRelayer(relayer);
        dao.revokeRelayerPermissionAndLock();
        vm.stopPrank();

        vm.startPrank(owner);
        token.mint(voter1, 60_000 * 10**18);
        token.mint(voter2, 40_000 * 10**18);
        token.mint(address(dao), 10_000_000 * 10**18);
        vm.stopPrank();
    }

    function test_Security_CannotDoubleVote() public {
        vm.prank(voter1);
        dao.createProposal("Solar Array Expansion", 1000 * 10**18, payable(recipient), MOCK_PQC_HASH);

        vm.startPrank(voter1);
        dao.vote(1, true);

        vm.expectRevert("Voter has already cast a ballot");
        dao.vote(1, true);
        vm.stopPrank();
    }

    function test_Security_CannotExecuteBeforeVotingPeriodEnds() public {
        vm.prank(voter1);
        dao.createProposal("Water Generator Maintenance", 1000 * 10**18, payable(recipient), MOCK_PQC_HASH);

        vm.prank(voter1);
        dao.vote(1, true);

        vm.expectRevert("Voting period is still active");
        dao.executeProposal(1);
    }

    function test_Security_QuorumNotReachedFails() public {
        vm.prank(voter2);
        dao.createProposal("Low Quorum Proposal", 1000 * 10**18, payable(recipient), MOCK_PQC_HASH);

        vm.prank(voter2);
        dao.vote(1, true);

        skip(4 days);

        vm.expectRevert("Quorum not reached");
        dao.executeProposal(1);
    }

    function test_Security_UnauthorizedRelayerOrInvalidPQC() public {
        vm.prank(voter1);
        dao.createProposal("Robot Automated Irrigation", 1000 * 10**18, payable(recipient), MOCK_PQC_HASH);

        vm.prank(voter1);
        dao.vote(1, true);
        skip(4 days);

        vm.prank(voter1);
        vm.expectRevert("Unauthorized: Robot hardware array only");
        dao.robotExecuteApprovedProposal(1, MOCK_PQC_HASH);

        vm.prank(relayer);
        vm.expectRevert("Hybrid PQC verification failed");
        dao.robotExecuteApprovedProposal(1, keccak256("INVALID_PQC"));
    }

    function test_Security_ConstructorZeroAddressCheck() public {
        vm.expectRevert("Invalid OBS token address");
        new ArizonaForestationDAO(address(0));
    }

    function testFuzz_ProposalExecution(uint256 requestAmount, uint256 voterBalance) public {
        vm.assume(requestAmount > 0 && requestAmount <= 5_000_000 * 10**18);
        vm.assume(voterBalance >= 50_000 * 10**18 && voterBalance <= 10_000_000 * 10**18);

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
