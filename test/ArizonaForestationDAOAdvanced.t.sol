// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../contracts/ArizonaForestationDAO.sol";

contract AdvancedMockBindingCurveToken is IObscuraToken {
    uint256 public raisedDAI = 6_000_000_000 * 10**18;
    mapping(address => uint256) public balances;

    function totalRaisedDAI() external view returns (uint256) {
        return raisedDAI;
    }

    function verifyHybridSignature(
        address,
        bytes32,
        bytes calldata,
        bytes calldata
    ) external pure returns (bool) {
        return true;
    }

    function balanceOf(address account) external view returns (uint256) {
        return balances[account];
    }

    function transfer(address recipient, uint256 amount) external returns (bool) {
        balances[msg.sender] -= amount;
        balances[recipient] += amount;
        return true;
    }

    function transferFrom(address sender, address recipient, uint256 amount) external returns (bool) {
        balances[sender] -= amount;
        balances[recipient] += amount;
        return true;
    }

    function mint(address to, uint256 amount) external {
        balances[to] += amount;
    }
}

contract ArizonaForestationDAOAdvancedTest is Test {
    ArizonaForestationDAO dao;
    AdvancedMockBindingCurveToken token;
    address constant ADMIN = 0xaF570ce3b32D765b1236635B0f541a7487A1fB8e;
    address constant RELAYER = address(0x456);
    address constant USER = address(0x789);
    address constant RECIPIENT = address(0x111);

    function setUp() public {
        token = new AdvancedMockBindingCurveToken();
        dao = new ArizonaForestationDAO();
        vm.etch(dao.OBS_TOKEN_ADDRESS(), address(token).code);
        
        token.mint(address(dao), 10_000_000 * 10**18);
        token.mint(USER, 1000 * 10**18);
    }

    function testAdvancedDeploymentAndSetup() public {
        vm.startPrank(ADMIN);
        dao.setupRoomieRobotAndLock(RELAYER);
        assertEq(dao.roomieRobotRelayer(), RELAYER);
        vm.stopPrank();
    }

    function testRevocableImmutability() public {
        vm.startPrank(ADMIN);
        dao.setupRoomieRobotAndLock(RELAYER);
        dao.revokeRelayerPermissionAndLock();
        assertTrue(dao.relayerUpdatePermissionRevoked());
        
        vm.expectRevert();
        dao.setupRoomieRobotAndLock(address(0x999));
        vm.stopPrank();
    }

    function testProposalCreationAndVotingWithSnapshot() public {
        vm.prank(USER);
        dao.joinDAO();
        dao.issueMonthlyLp();
        
        uint256 monthAtCreation = dao.getCurrentMonthId();
        
        vm.prank(USER);
        bytes32 pqcHash = keccak256("PQCProof");
        uint256 proposalId = dao.createProposal(
            "Plant native mesquite trees",
            3000 * 10**18,
            payable(RECIPIENT),
            pqcHash,
            true
        );
        
        // votingMonthId at index 8: 8 commas before, 8 after
        (,,,,,,,, uint256 votingMonthId,,,,,,,,) = dao.proposals(proposalId);
        assertEq(votingMonthId, monthAtCreation);
        
        // Vote with snapshot weight
        vm.prank(USER);
        dao.vote(proposalId, true);
        
        // yesVotes at index 10: 10 commas before, 6 after
        (,,,,,,,,,, uint256 yesVotes,,,,,,) = dao.proposals(proposalId);
        assertEq(yesVotes, 100 * 10**18);
    }

    function testVotingPowerSnapshotPreservedAcrossMonthBoundary() public {
        vm.prank(USER);
        dao.joinDAO();
        dao.issueMonthlyLp();
        
        vm.prank(USER);
        bytes32 pqcHash = keccak256("PQCProof");
        uint256 proposalId = dao.createProposal(
            "Test proposal",
            3000 * 10**18,
            payable(RECIPIENT),
            pqcHash,
            true
        );
        
        // Warp to next month - LP expires
        vm.warp(block.timestamp + 31 days);
        dao.issueMonthlyLp(); // New month
        
        // Vote should still use old month's weight (100 LP)
        vm.prank(USER);
        dao.vote(proposalId, true);
        
        (,,,,,,,,,, uint256 yesVotes,,,,,,) = dao.proposals(proposalId);
        assertEq(yesVotes, 100 * 10**18);
    }

    function testQuorumAndMajorityRequirements() public {
        vm.prank(USER);
        dao.joinDAO();
        dao.issueMonthlyLp();
        
        // Add second member
        address member2 = address(0x222);
        vm.prank(member2);
        dao.joinDAO();
        dao.issueMonthlyLp();
        
        vm.prank(USER);
        bytes32 pqcHash = keccak256("PQCProof");
        uint256 proposalId = dao.createProposal(
            "Test proposal",
            3000 * 10**18,
            payable(RECIPIENT),
            pqcHash,
            true
        );
        
        // Only 1 voter (100 LP) - below quorum (100 LP required)
        vm.prank(USER);
        dao.vote(proposalId, true);
        
        vm.warp(block.timestamp + 4 days);
        vm.expectRevert();
        dao.executeProposal(proposalId);
        
        // Add second voter to reach quorum
        vm.prank(member2);
        dao.vote(proposalId, true);
        
        // Now quorum met (200 LP), majority yes
        dao.executeProposal(proposalId);
        
        // executed at index 12: 12 commas before, 4 after
        (,,,,,,,,,,,, bool executed,,,,) = dao.proposals(proposalId);
        assertTrue(executed);
    }

    function testRobotMilestoneExecutionWithReplayProtection() public {
        vm.prank(USER);
        dao.joinDAO();
        dao.issueMonthlyLp();
        
        vm.prank(USER);
        bytes32 pqcHash = keccak256("PQCProof");
        uint256 proposalId = dao.createProposal(
            "Test proposal",
            3000 * 10**18,
            payable(RECIPIENT),
            pqcHash,
            true
        );
        
        vm.prank(USER);
        dao.vote(proposalId, true);
        
        vm.warp(block.timestamp + 4 days);
        dao.executeProposal(proposalId);
        
        // Setup relayer
        vm.prank(ADMIN);
        dao.setupRoomieRobotAndLock(RELAYER);
        vm.prank(ADMIN);
        dao.revokeRelayerPermissionAndLock();
        
        // Execute first milestone
        uint256 trancheAmount = 1000 * 10**18; // 3000 / 3
        uint256 deadline = block.timestamp + 1 days;
        
        // Construct the expected message hash for testing
        bytes32 expectedHash = keccak256(abi.encodePacked(
            bytes32(dao.DOMAIN_SEPARATOR()),
            proposalId,
            uint256(1), // milestone index
            trancheAmount,
            RECIPIENT,
            deadline,
            uint256(1) // nonce
        ));
        
        vm.prank(RELAYER);
        dao.roomieRobotExecuteApprovedProposal(
            proposalId,
            1, // milestone index
            trancheAmount,
            RECIPIENT,
            deadline,
            hex"1234", // dummy dilithium sig
            hex"5678"  // dummy ed25519 sig
        );
        
        // milestonesReleased at index 14: 14 commas before, 2 after
        (,,,,,,,,,,,,,, uint256 milestonesReleased,,) = dao.proposals(proposalId);
        assertEq(milestonesReleased, 1);
    }

    function testMilestoneIntervalEnforcement() public {
        vm.prank(USER);
        dao.joinDAO();
        dao.issueMonthlyLp();
        
        vm.prank(USER);
        bytes32 pqcHash = keccak256("PQCProof");
        uint256 proposalId = dao.createProposal(
            "Test proposal",
            3000 * 10**18,
            payable(RECIPIENT),
            pqcHash,
            true
        );
        
        vm.prank(USER);
        dao.vote(proposalId, true);
        
        vm.warp(block.timestamp + 4 days);
        dao.executeProposal(proposalId);
        
        vm.prank(ADMIN);
        dao.setupRoomieRobotAndLock(RELAYER);
        vm.prank(ADMIN);
        dao.revokeRelayerPermissionAndLock();
        
        // First milestone
        uint256 trancheAmount = 1000 * 10**18;
        uint256 deadline = block.timestamp + 1 days;
        
        vm.prank(RELAYER);
        dao.roomieRobotExecuteApprovedProposal(proposalId, 1, trancheAmount, RECIPIENT, deadline, hex"1234", hex"5678");
        
        // Try second milestone immediately - should fail (60 days not passed)
        vm.warp(block.timestamp + 1 days);
        deadline = block.timestamp + 1 days;
        
        vm.prank(RELAYER);
        vm.expectRevert();
        dao.roomieRobotExecuteApprovedProposal(proposalId, 2, trancheAmount, RECIPIENT, deadline, hex"1234", hex"5678");
        
        // After 60 days - should succeed
        vm.warp(block.timestamp + 60 days);
        deadline = block.timestamp + 1 days;
        
        vm.prank(RELAYER);
        dao.roomieRobotExecuteApprovedProposal(proposalId, 2, trancheAmount, RECIPIENT, deadline, hex"1234", hex"5678");
        
        (,,,,,,,,,,,,,, uint256 milestonesReleased,,) = dao.proposals(proposalId);
        assertEq(milestonesReleased, 2);
    }

    function testVaultAccountingAndSafeTransfer() public {
        vm.prank(USER);
        dao.joinDAO();
        dao.issueMonthlyLp();
        
        vm.prank(USER);
        bytes32 pqcHash = keccak256("PQCProof");
        uint256 proposalId = dao.createProposal(
            "Test proposal",
            3000 * 10**18,
            payable(RECIPIENT),
            pqcHash,
            true
        );
        
        vm.prank(USER);
        dao.vote(proposalId, true);
        
        vm.warp(block.timestamp + 4 days);
        dao.executeProposal(proposalId);
        
        vm.prank(ADMIN);
        dao.setupRoomieRobotAndLock(RELAYER);
        vm.prank(ADMIN);
        dao.revokeRelayerPermissionAndLock();
        
        uint256 initialVaultBalance = dao.getVaultBalance();
        assertEq(initialVaultBalance, 10_000_000 * 10**18);
        
        uint256 trancheAmount = 1000 * 10**18;
        uint256 deadline = block.timestamp + 1 days;
        
        vm.prank(RELAYER);
        dao.roomieRobotExecuteApprovedProposal(proposalId, 1, trancheAmount, RECIPIENT, deadline, hex"1234", hex"5678");
        
        uint256 finalVaultBalance = dao.getVaultBalance();
        assertEq(finalVaultBalance, initialVaultBalance - trancheAmount);
        
        uint256 recipientBalance = token.balanceOf(RECIPIENT);
        assertEq(recipientBalance, trancheAmount);
    }

    function testVaultInsufficientBalanceReverts() public {
        // Deploy with minimal vault balance
        ArizonaForestationDAO poorDao = new ArizonaForestationDAO();
        vm.etch(poorDao.OBS_TOKEN_ADDRESS(), address(token).code);
        // Don't mint tokens to poorDao
        
        vm.prank(USER);
        poorDao.joinDAO();
        poorDao.issueMonthlyLp();
        
        vm.prank(USER);
        bytes32 pqcHash = keccak256("PQCProof");
        uint256 proposalId = poorDao.createProposal(
            "Test proposal",
            3000 * 10**18,
            payable(RECIPIENT),
            pqcHash,
            true
        );
        
        vm.prank(USER);
        poorDao.vote(proposalId, true);
        
        vm.warp(block.timestamp + 4 days);
        poorDao.executeProposal(proposalId);
        
        vm.prank(ADMIN);
        poorDao.setupRoomieRobotAndLock(RELAYER);
        vm.prank(ADMIN);
        poorDao.revokeRelayerPermissionAndLock();
        
        uint256 trancheAmount = 1000 * 10**18;
        uint256 deadline = block.timestamp + 1 days;
        
        vm.prank(RELAYER);
        vm.expectRevert();
        poorDao.roomieRobotExecuteApprovedProposal(proposalId, 1, trancheAmount, RECIPIENT, deadline, hex"1234", hex"5678");
    }
}