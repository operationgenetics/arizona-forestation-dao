#!/usr/bin/env bash
set -e

echo "Updating test/ArizonaForestationDAO.t.sol to etch mock contract to the hardcoded production address..."

cat << 'PROCESSEOF' > test/ArizonaForestationDAO.t.sol
// SPDX-License-Identifier: AGPLv3-3.0
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import "../contracts/ArizonaForestationDAO.sol";

contract MockOBSBindingCurveToken is IBindingCurveToken {
    uint256 public totalRaisedDAIVal;
    mapping(address => uint256) public balances;

    function setRaisedDAI(uint256 _raised) external {
        totalRaisedDAIVal = _raised;
    }

    function mint(address to, uint256 amount) external {
        balances[to] += amount;
    }

    function totalRaisedDAI() external view returns (uint256) {
        return totalRaisedDAIVal;
    }

    function transferFrom(address from, address recipient, uint256 amount) external returns (bool) {
        require(balances[from] >= amount, "Mock: insufficient balance");
        balances[from] -= amount;
        balances[recipient] += amount;
        return true;
    }

    function transfer(address recipient, uint256 amount) external returns (bool) {
        require(balances[msg.sender] >= amount, "Mock: insufficient balance");
        balances[msg.sender] -= amount;
        balances[recipient] += amount;
        return true;
    }

    function balanceOf(address account) external view returns (uint256) {
        return balances[account];
    }
}

contract ArizonaForestationDAOTest is Test {
    ArizonaForestationDAO public dao;
    MockOBSBindingCurveToken public mockObs;

    address constant PRODUCTION_OBS_ADDRESS = 0x2D8760e2877148d239a54952A458710553B2B54b;
    address admin = 0xaF570ce3b32D765b1236635B0f541a7487A1fB8e;
    address member1 = address(0x111);
    address member2 = address(0x222);
    address robotRelayer = address(0x333);
    address recipient = address(0x444);

    function setUp() public {
        // Deploy mock contract normally
        MockOBSBindingCurveToken realMock = new MockOBSBindingCurveToken();
        
        // Etch its runtime bytecode onto the hardcoded production address so static calls resolve correctly
        bytes memory code = address(realMock).code;
        vm.etch(PRODUCTION_OBS_ADDRESS, code);

        // Bind an interface handle to the hardcoded address for test setup calls
        mockObs = MockOBSBindingCurveToken(PRODUCTION_OBS_ADDRESS);

        dao = new ArizonaForestationDAO();

        // Fund the DAO vault with mock tokens at the production address
        mockObs.mint(address(dao), 1_000_000 * 10**18);
    }

    function test_DeploymentConstants() public view {
        assertEq(dao.INITIAL_ADMIN(), admin);
        assertEq(dao.OBS_TOKEN_ADDRESS(), PRODUCTION_OBS_ADDRESS);
        assertEq(dao.FUNDING_GOAL_DAI(), 5_000_000_000 * 10**18);
        assertEq(dao.MONTHLY_LP_GRANT(), 100 * 10**18);
        assertEq(dao.PROPOSAL_COST(), 50 * 10**18);
    }

    function test_MemberJoinAndMonthlyLP() public {
        vm.prank(member1);
        dao.joinDAO();

        assertTrue(dao.isMember(member1));
        assertEq(dao.getVotingPower(member1), 100 * 10**18);
    }

    function test_MonthlyLPExpiration() public {
        vm.prank(member1);
        dao.joinDAO();
        assertEq(dao.getVotingPower(member1), 100 * 10**18);

        vm.warp(block.timestamp + 31 days);

        assertEq(dao.getVotingPower(member1), 0);

        vm.prank(member1);
        dao.joinDAO();
        assertEq(dao.getVotingPower(member1), 100 * 10**18);
    }

    function test_ProposalCreationAndVoting() public {
        vm.prank(member1);
        dao.joinDAO();

        bytes32 pqcHash = keccak256("ArizonaForestPQCProof");

        vm.prank(member1);
        uint256 proposalId = dao.createProposal(
            "Plant 10,000 native mesquite trees in Southern Arizona",
            1000 * 10**18,
            payable(recipient),
            pqcHash
        );

        assertEq(dao.getVotingPower(member1), 100 * 10**18);

        vm.prank(member2);
        dao.joinDAO();

        vm.prank(member2);
        dao.vote(proposalId, true);

        (
            ,
            ,
            ,
            ,
            ,
            uint256 votesFor,
            ,
            ,
            ,
            ,
            
        ) = dao.proposals(proposalId);

        assertEq(votesFor, 100 * 10**18);
    }

    function test_RevertWhen_VotingTwice() public {
        vm.prank(member1);
        dao.joinDAO();

        bytes32 pqcHash = keccak256("Proof");
        vm.prank(member1);
        uint256 proposalId = dao.createProposal("Test", 100, payable(recipient), pqcHash);

        vm.prank(member1);
        dao.vote(proposalId, true);

        vm.prank(member1);
        vm.expectRevert("Voter has already cast a ballot");
        dao.vote(proposalId, true);
    }

    function test_BondingCurveGateAndExecution() public {
        vm.prank(member1);
        dao.joinDAO();

        bytes32 pqcHash = keccak256("Proof");
        vm.prank(member1);
        uint256 proposalId = dao.createProposal("Tree planting", 500 * 10**18, payable(recipient), pqcHash);

        vm.prank(member1);
        dao.vote(proposalId, true);

        vm.warp(block.timestamp + 4 days);

        // Test gate condition: below 5 Billion DAI goal
        mockObs.setRaisedDAI(1_000 * 10**18);
        vm.expectRevert("Funding goal not reached");
        dao.executeProposal(proposalId);

        // Hit 5 Billion DAI target
        mockObs.setRaisedDAI(5_000_000_000 * 10**18);

        dao.executeProposal(proposalId);

        (
            ,
            ,
            ,
            ,
            ,
            ,
            ,
            ,
            ,
            bool executed,
            
        ) = dao.proposals(proposalId);
        assertTrue(executed);
    }

    function test_AdminRelayerAndRevocableImmutability() public {
        bytes memory pqcKey = hex"12345678";

        vm.prank(admin);
        dao.setRobotRelayer(robotRelayer, pqcKey);

        assertEq(dao.robotExecutionRelayer(), robotRelayer);

        vm.prank(admin);
        dao.revokeRelayerPermissionAndLock();

        assertTrue(dao.relayerUpdatePermissionRevoked());
        assertTrue(dao.relayerLocked());

        vm.prank(admin);
        vm.expectRevert("Permission permanently revoked and contract locked");
        dao.setRobotRelayer(address(0x999), hex"87654321");
    }
}
PROCESSEOF

echo "Running full Forge test suite..."
forge test -vvv
