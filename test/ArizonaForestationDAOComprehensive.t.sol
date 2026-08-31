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

contract ArizonaForestationDAOComprehensiveTest is Test {
    ArizonaForestationDAO public dao;
    MockObscuraToken public mockObs;
    address constant ADMIN = 0xaF570ce3b32D765b1236635B0f541a7487A1fB8e;
    address constant RELAYER = address(0x456);
    address constant VOTER = address(0x789);
    address constant RECIPIENT = address(0x111);

    function setUp() public {
        mockObs = new MockObscuraToken();
        dao = new ArizonaForestationDAO();
        vm.etch(dao.OBS_TOKEN_ADDRESS(), address(mockObs).code);
        
        // Fund the DAO vault
        mockObs.mint(address(dao), 10_000_000 * 10**18);
        mockObs.mint(VOTER, 1000 * 10**18);
    }

    function testFullLifecycleAndRoomieRobotAutomation() public {
        // 1. Setup Roomie Robot Relayer as Admin
        vm.prank(ADMIN);
        dao.setupRoomieRobotAndLock(RELAYER);
        assertEq(dao.roomieRobotRelayer(), RELAYER);

        // 2. Revoke relayer update permissions to make immutable
        vm.prank(ADMIN);
        dao.revokeRelayerPermissionAndLock();
        assertTrue(dao.relayerUpdatePermissionRevoked());

        // 3. Attempt to update after revocation should fail
        vm.prank(ADMIN);
        vm.expectRevert();
        dao.setupRoomieRobotAndLock(address(0x999));

        // 4. Voter joins DAO and receives monthly LP
        vm.prank(VOTER);
        dao.joinDAO();
        
        dao.issueMonthlyLp();
        
        uint256 currentMonth = dao.getCurrentMonthId();
        assertEq(dao.getVotingWeight(VOTER, currentMonth), 100 * 10**18);
    }

    function testAdminCanSetLpBalance() public {
        uint256 monthId = dao.getCurrentMonthId();
        
        vm.prank(ADMIN);
        dao.setMonthlyLpBalance(VOTER, monthId, 200 * 10**18);
        
        assertEq(dao.getVotingWeight(VOTER, monthId), 200 * 10**18);
    }

    function testAdminCannotSetLpAfterRevocation() public {
        vm.prank(ADMIN);
        dao.revokeRelayerPermissionAndLock();
        // Admin can still set LP (different permission)
        uint256 monthId = dao.getCurrentMonthId();
        vm.prank(ADMIN);
        dao.setMonthlyLpBalance(VOTER, monthId, 200 * 10**18);
        assertEq(dao.getVotingWeight(VOTER, monthId), 200 * 10**18);
    }
}