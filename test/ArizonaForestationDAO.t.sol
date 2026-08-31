// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../contracts/ArizonaForestationDAO.sol";

contract MockObscuraToken is IObscuraToken {
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

    function setRaisedDAI(uint256 _raised) external {
        raisedDAI = _raised;
    }
}

contract ArizonaForestationDAOTest is Test {
    ArizonaForestationDAO public dao;
    MockObscuraToken public mockObs;
    address constant ADMIN = 0xaF570ce3b32D765b1236635B0f541a7487A1fB8e;
    address constant RELAYER = address(0x456);
    address constant MEMBER1 = address(0x789);
    address constant MEMBER2 = address(0x999);
    address constant RECIPIENT = address(0x111);

    function setUp() public {
        mockObs = new MockObscuraToken();
        dao = new ArizonaForestationDAO();
        // Etch mock bytecode to the hardcoded OBS_TOKEN_ADDRESS
        vm.etch(dao.OBS_TOKEN_ADDRESS(), address(mockObs).code);
        
        // Fund the DAO vault with mock tokens
        mockObs.mint(address(dao), 1_000_000 * 10**18);
        mockObs.mint(MEMBER1, 1000 * 10**18);
        mockObs.mint(MEMBER2, 1000 * 10**18);
    }

    function testConstants() public view {
        assertEq(dao.OBS_TOKEN_ADDRESS(), 0x2D8760e2877148d239a54952A458710553B2B54b);
        assertEq(dao.INITIAL_ADMIN(), ADMIN);
        assertEq(dao.QUORUM_THRESHOLD_LP(), 100 * 10**18);
        assertEq(dao.MONTHLY_LP_ISSUANCE(), 100 * 10**18);
        assertEq(dao.PROPOSAL_THRESHOLD_LP(), 50 * 10**18);
        assertEq(dao.BONDING_CURVE_GOAL(), 5_000_000_000 * 10**18);
        assertEq(dao.MILESTONES_COUNT(), 3);
        assertEq(dao.MILESTONE_INTERVAL(), 60 days);
    }

    function testMemberJoinAndMonthlyLpIssuance() public {
        // Member joins DAO
        vm.prank(MEMBER1);
        dao.joinDAO();
        assertTrue(dao.isMember(MEMBER1));
        
        // Issue monthly LP (permissionless)
        dao.issueMonthlyLp();
        
        uint256 currentMonth = dao.getCurrentMonthId();
        assertEq(dao.getVotingWeight(MEMBER1, currentMonth), 100 * 10**18);
        
        // Second member joins and gets LP
        vm.prank(MEMBER2);
        dao.joinDAO();
        dao.issueMonthlyLp();
        assertEq(dao.getVotingWeight(MEMBER2, currentMonth), 100 * 10**18);
    }

    function testMonthlyLpExpiration() public {
        vm.prank(MEMBER1);
        dao.joinDAO();
        dao.issueMonthlyLp();
        
        uint256 currentMonth = dao.getCurrentMonthId();
        assertEq(dao.getVotingWeight(MEMBER1, currentMonth), 100 * 10**18);
        
        // Warp to next month (31 days)
        vm.warp(block.timestamp + 31 days);
        
        // Old month LP should be expired (returns 0)
        assertEq(dao.getVotingWeight(MEMBER1, currentMonth), 0);
        
        // New month LP issuance
        dao.issueMonthlyLp();
        uint256 newMonth = dao.getCurrentMonthId();
        assertEq(dao.getVotingWeight(MEMBER1, newMonth), 100 * 10**18);
    }

    function testProposalCreationRequires50Lp() public {
        vm.prank(MEMBER1);
        dao.joinDAO();
        dao.issueMonthlyLp();
        
        // Should succeed with 100 LP (>= 50 threshold)
        vm.prank(MEMBER1);
        bytes32 pqcHash = keccak256("test");
        uint256 proposalId = dao.createProposal(
            "Test proposal",
            1000 * 10**18,
            payable(RECIPIENT),
            pqcHash,
            true
        );
        assertEq(proposalId, 1);
    }

    function testProposalCreationFailsWithInsufficientLp() public {
        vm.prank(MEMBER1);
        dao.joinDAO();
        // Don't issue LP - member has 0 LP
        
        bytes32 pqcHash = keccak256("test");
        vm.expectRevert();
        dao.createProposal(
            "Test proposal",
            1000 * 10**18,
            payable(RECIPIENT),
            pqcHash,
            true
        );
    }

    function testProposalCreationRequiresMandate() public {
        vm.prank(MEMBER1);
        dao.joinDAO();
        dao.issueMonthlyLp();
        
        bytes32 pqcHash = keccak256("test");
        vm.expectRevert();
        dao.createProposal(
            "Test proposal",
            1000 * 10**18,
            payable(RECIPIENT),
            pqcHash,
            false // mandate = false
        );
    }

    function testVotingSnapshotPreventsPowerDisappearance() public {
        vm.prank(MEMBER1);
        dao.joinDAO();
        dao.issueMonthlyLp();
        
        vm.prank(MEMBER1);
        bytes32 pqcHash = keccak256("test");
        uint256 proposalId = dao.createProposal(
            "Test proposal",
            1000 * 10**18,
            payable(RECIPIENT),
            pqcHash,
            true
        );
        
        // Warp to next month - LP expires
        vm.warp(block.timestamp + 31 days);
        dao.issueMonthlyLp(); // New month LP issued
        
        // Vote should still use snapshot month (old month) weight
        vm.prank(MEMBER1);
        dao.vote(proposalId, true);
        
        // Proposal struct has 17 fields in getter. yesVotes at index 10.
        // Need 10 commas before, 6 after = 16 commas total for 17 elements
        (,,,,,,,,,, uint256 yesVotes,,,,,,) = dao.proposals(proposalId);
        assertEq(yesVotes, 100 * 10**18);
    }

    function testDoubleVotePrevented() public {
        vm.prank(MEMBER1);
        dao.joinDAO();
        dao.issueMonthlyLp();
        
        vm.prank(MEMBER1);
        bytes32 pqcHash = keccak256("test");
        uint256 proposalId = dao.createProposal("Test", 1000 * 10**18, payable(RECIPIENT), pqcHash, true);
        
        vm.prank(MEMBER1);
        dao.vote(proposalId, true);
        
        vm.prank(MEMBER1);
        vm.expectRevert();
        dao.vote(proposalId, true);
    }

    function testBondingCurveGate() public {
        vm.prank(MEMBER1);
        dao.joinDAO();
        dao.issueMonthlyLp();
        
        vm.prank(MEMBER1);
        bytes32 pqcHash = keccak256("test");
        uint256 proposalId = dao.createProposal("Test", 1000 * 10**18, payable(RECIPIENT), pqcHash, true);
        
        vm.prank(MEMBER1);
        dao.vote(proposalId, true);
        
        vm.warp(block.timestamp + 4 days);
        
        // Below 5B DAI - should fail
        mockObs.setRaisedDAI(1_000 * 10**18);
        vm.expectRevert();
        dao.executeProposal(proposalId);
        
        // At 5B DAI - should succeed
        mockObs.setRaisedDAI(5_000_000_000 * 10**18);
        dao.executeProposal(proposalId);
        
        // executed at index 12: 12 commas before, 4 after
        (,,,,,,,,,,,, bool executed,,,,) = dao.proposals(proposalId);
        assertTrue(executed);
    }

    function testProposalTimeout() public {
        vm.prank(MEMBER1);
        dao.joinDAO();
        dao.issueMonthlyLp();
        
        vm.prank(MEMBER1);
        bytes32 pqcHash = keccak256("test");
        uint256 proposalId = dao.createProposal("Test", 1000 * 10**18, payable(RECIPIENT), pqcHash, true);
        
        // Don't vote, warp past voting period
        vm.warp(block.timestamp + 4 days);
        
        // Anyone can timeout the proposal
        dao.timeoutProposal(proposalId);
        
        // timedOut at index 15: 15 commas before, 1 after
        (,,,,,,,,,,,,,,, bool timedOut,) = dao.proposals(proposalId);
        assertTrue(timedOut);
    }
}