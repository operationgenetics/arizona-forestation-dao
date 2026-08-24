// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../contracts/ArizonaForestationDAO.sol";

contract MockObscuraForComprehensive {
    function totalRaisedDAI() external pure returns (uint256) {
        return 6_000_000_000 * 10**18; // 6 Billion DAI (unlocked)
    }

    function verifyHybridSignature(
        address,
        bytes32,
        bytes calldata,
        bytes calldata
    ) external pure returns (bool) {
        return true;
    }
}

contract ArizonaForestationDAOComprehensiveTest is Test {
    ArizonaForestationDAO public dao;
    MockObscuraForComprehensive public mockObs;
    address public admin = 0xaF570ce3b32D765b1236635B0f541a7487A1fB8e;
    address public relayer = address(0x456);
    address public voter = address(0x789);

    function setUp() public {
        dao = new ArizonaForestationDAO();
    }

    function testFullLifecycleAndRoomieRobotAutomation() public {
        // 1. Setup Roomie Robot Relayer as Admin
        vm.prank(admin);
        dao.setupRoomieRobotAndLock(relayer);
        assertEq(dao.roomieRobotRelayer(), relayer);

        // 2. Revoke relayer update permissions to make immutable
        vm.prank(admin);
        dao.revokeRelayerPermissionAndLock();
        assertTrue(dao.relayerUpdatePermissionRevoked());

        // 3. Record Monthly LP Balance as Admin
        vm.prank(admin);
        dao.recordMonthlyLpBalance(voter, 100 * 10**18);
        
        uint256 currentMonth = block.timestamp / 30 days;
        assertEq(dao.monthlyLpBalances(currentMonth, voter), 100 * 10**18);
    }
}
