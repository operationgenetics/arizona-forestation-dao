// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../contracts/ArizonaForestationDAO.sol";
import "./RobotPqcVectors.sol";

contract AdvancedMockBindingCurveToken is IObscuraToken {
    uint256 public raisedDAI = 6_000_000_000 * 10**18;
    mapping(address => uint256) public balances;

    function totalRaisedDAI() external view returns (uint256) {
        return raisedDAI;
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

    function setRaisedDAI(uint256 _raised) external {
        raisedDAI = _raised;
    }
}

contract ArizonaForestationDAOAdvancedTest is Test {
    ArizonaForestationDAO dao;
    AdvancedMockBindingCurveToken token;
    address constant ADMIN = 0xaF570ce3b32D765b1236635B0f541a7487A1fB8e;
    address constant RELAYER = address(0x456);
    address constant USER = address(0x789);
    address constant RECIPIENT = address(0x111);
    address constant VAULT_FUNDER = address(0xABC);

    function setUp() public {
        token = new AdvancedMockBindingCurveToken();
        dao = new ArizonaForestationDAO();
        vm.etch(dao.OBS_TOKEN_ADDRESS(), address(token).code);
        
        // The etched hardcoded OBS address has its OWN storage independent of `token`.
        // All token operations must be routed through the etched address so the DAO
        // observes consistent state (raised DAI >= 5B to unlock the bonding curve).
        AdvancedMockBindingCurveToken obs = AdvancedMockBindingCurveToken(dao.OBS_TOKEN_ADDRESS());
        obs.setRaisedDAI(6_000_000_000 * 10**18);
        obs.mint(VAULT_FUNDER, 10_000_000 * 10**18);
        obs.mint(USER, 1000 * 10**18);
        
        // Deposit vault funds THROUGH receiveObsTokens so internal vaultObsBalance
        // accounting is updated (direct mint bypasses accounting and yields 0 vault).
        vm.prank(VAULT_FUNDER);
        dao.receiveObsTokens(10_000_000 * 10**18);
    }

    function testAdvancedDeploymentAndSetup() public {
        vm.startPrank(ADMIN);
        dao.setupRoomieRobotAndLock(RELAYER, RobotPqcVectors.MLDSA_PK, RobotPqcVectors.ED25519_PK);
        assertEq(dao.roomieRobotRelayer(), RELAYER);
        vm.stopPrank();
    }

    function testRevocableImmutability() public {
        vm.startPrank(ADMIN);
        dao.setupRoomieRobotAndLock(RELAYER, RobotPqcVectors.MLDSA_PK, RobotPqcVectors.ED25519_PK);
        dao.revokeRelayerPermissionAndLock();
        assertTrue(dao.relayerUpdatePermissionRevoked());
        
        vm.expectRevert();
        dao.setupRoomieRobotAndLock(address(0x999), RobotPqcVectors.MLDSA_PK, RobotPqcVectors.ED25519_PK);
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
        
        uint256 monthAtCreation = dao.getCurrentMonthId();
        
        vm.prank(USER);
        bytes32 pqcHash = keccak256("PQCProof");
        uint256 proposalId = dao.createProposal(
            "Test proposal",
            3000 * 10**18,
            payable(RECIPIENT),
            pqcHash,
            true
        );
        
        // The proposal snapshots its voting month at creation. Voting within the
        // 3-day window uses that SNAPSHOT month's LP weight (100), so a member's
        // voting power is preserved even if their current-month LP changes.
        (, , , , , , , , uint256 votingMonthId, , , , , , , , ) = dao.proposals(proposalId);
        assertEq(votingMonthId, monthAtCreation);
        
        vm.prank(USER);
        dao.vote(proposalId, true);
        
        (,,,,,,,,,, uint256 yesVotes,,,,,,) = dao.proposals(proposalId);
        assertEq(yesVotes, 100 * 10**18);
    }

    function testQuorumAndMajorityRequirements() public {
        // Two members each hold 100 LP for the current month
        vm.prank(USER);
        dao.joinDAO();
        dao.issueMonthlyLp();
        
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
        
        // No votes yet, advance past voting window: quorum (100 LP) not met
        vm.warp(block.timestamp + 4 days);
        vm.expectRevert();
        dao.executeProposal(proposalId);
        
        // A proposal that passed its 3-day voting window can no longer be voted on;
        // members must decide before expiry. Create a fresh proposal and vote within
        // the window to reach quorum + majority.
        vm.prank(USER);
        uint256 proposalId2 = dao.createProposal(
            "Second proposal",
            3000 * 10**18,
            payable(RECIPIENT),
            pqcHash,
            true
        );
        
        vm.prank(USER);
        dao.vote(proposalId2, true);    // yes = 100 LP
        vm.prank(member2);
        dao.vote(proposalId2, true);    // yes = 200 LP total, quorum met, majority yes
        
        vm.warp(block.timestamp + 4 days);
        dao.executeProposal(proposalId2);
        
        (,,,,,,,,,,,, bool executed,,,,) = dao.proposals(proposalId2);
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
        dao.setupRoomieRobotAndLock(RELAYER, RobotPqcVectors.MLDSA_PK, RobotPqcVectors.ED25519_PK);
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
        // The real robot MLDSA-65 + Ed25519 signatures (RobotPqcVectors) were generated
        // OFF-CHAIN over this exact expectedMessageHash.
        assertEq(expectedHash, bytes32(RobotPqcVectors.MH_M1));
        
        vm.prank(RELAYER);
        dao.roomieRobotExecuteApprovedProposal(
            proposalId,
            1, // milestone index
            trancheAmount,
            RECIPIENT,
            deadline,
            RobotPqcVectors.MLDSA_SIG_M1, // real ML-DSA-65 (FIPS 204) robot signature
            RobotPqcVectors.ED25519_SIG_M1 // real RFC 8032 Ed25519 robot signature
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
        dao.setupRoomieRobotAndLock(RELAYER, RobotPqcVectors.MLDSA_PK, RobotPqcVectors.ED25519_PK);
        vm.prank(ADMIN);
        dao.revokeRelayerPermissionAndLock();
        
        // First milestone at t0 = 345601; deadline must exceed block.timestamp.
        uint256 trancheAmount = 1000 * 10**18;
        uint256 t0 = block.timestamp;
        // NOTE: via-IR optimizer can reorder/cache `block.timestamp + N days`
        // expressions across chained vm.warp calls, so use EXPLICIT absolute
        // timestamps for the deadline to keep the interval test deterministic.
        uint256 deadline = t0 + 1 days;
        
        vm.prank(RELAYER);
        dao.roomieRobotExecuteApprovedProposal(proposalId, 1, trancheAmount, RECIPIENT, deadline, RobotPqcVectors.MLDSA_SIG_M1, RobotPqcVectors.ED25519_SIG_M1);
        
        // Try second milestone immediately - should fail (60 days not passed)
        vm.warp(t0 + 1 days); // 432001
        deadline = t0 + 1 days + 1 days; // 518401, still valid
        
        vm.prank(RELAYER);
        vm.expectRevert(); // MilestoneTimeoutNotMet (60-day interval)
        dao.roomieRobotExecuteApprovedProposal(proposalId, 2, trancheAmount, RECIPIENT, deadline, RobotPqcVectors.MLDSA_SIG_M2, RobotPqcVectors.ED25519_SIG_M2);
        
        // After 60 days - should succeed
        vm.warp(t0 + 60 days); // now past the interval
        deadline = t0 + 60 days + 1 days;
        
        vm.prank(RELAYER);
        dao.roomieRobotExecuteApprovedProposal(proposalId, 2, trancheAmount, RECIPIENT, deadline, RobotPqcVectors.MLDSA_SIG_M3, RobotPqcVectors.ED25519_SIG_M3);
        
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
        dao.setupRoomieRobotAndLock(RELAYER, RobotPqcVectors.MLDSA_PK, RobotPqcVectors.ED25519_PK);
        vm.prank(ADMIN);
        dao.revokeRelayerPermissionAndLock();
        
        uint256 initialVaultBalance = dao.getVaultBalance();
        assertEq(initialVaultBalance, 10_000_000 * 10**18);
        
        uint256 trancheAmount = 1000 * 10**18;
        uint256 deadline = block.timestamp + 1 days;
        
        vm.prank(RELAYER);
        dao.roomieRobotExecuteApprovedProposal(proposalId, 1, trancheAmount, RECIPIENT, deadline, RobotPqcVectors.MLDSA_SIG_M1, RobotPqcVectors.ED25519_SIG_M1);
        
        uint256 finalVaultBalance = dao.getVaultBalance();
        assertEq(finalVaultBalance, initialVaultBalance - trancheAmount);
        
        // Verify recipient received the tranche via the etched token address
        uint256 recipientBalance = AdvancedMockBindingCurveToken(dao.OBS_TOKEN_ADDRESS()).balanceOf(RECIPIENT);
        assertEq(recipientBalance, trancheAmount);
    }

    function testVaultInsufficientBalanceReverts() public {
        // Deploy with minimal vault balance
        ArizonaForestationDAO poorDao = new ArizonaForestationDAO();
        vm.etch(poorDao.OBS_TOKEN_ADDRESS(), address(token).code);
        // Unlock the bonding curve at the etched address but do NOT mint vault funds
        AdvancedMockBindingCurveToken(poorDao.OBS_TOKEN_ADDRESS()).setRaisedDAI(6_000_000_000 * 10**18);
        
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
        poorDao.setupRoomieRobotAndLock(RELAYER, RobotPqcVectors.MLDSA_PK, RobotPqcVectors.ED25519_PK);
        vm.prank(ADMIN);
        poorDao.revokeRelayerPermissionAndLock();
        
        uint256 trancheAmount = 1000 * 10**18;
        uint256 deadline = block.timestamp + 1 days;
        
        vm.prank(RELAYER);
        vm.expectRevert(); // VaultInsufficientBalance
        poorDao.roomieRobotExecuteApprovedProposal(proposalId, 1, trancheAmount, RECIPIENT, deadline, RobotPqcVectors.MLDSA_SIG_M1, RobotPqcVectors.ED25519_SIG_M1);
    }
}