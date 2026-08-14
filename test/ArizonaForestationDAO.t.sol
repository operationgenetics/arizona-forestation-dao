// SPDX-License-Identifier: AGPLv3
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import "../contracts/ArizonaForestationDAO.sol";

contract MockBindingCurveToken is IBindingCurveToken {
    string public name = "Obsidian Token";
    string public symbol = "OBS";
    uint8 public decimals = 18;
    uint256 public totalRaisedDAI = 0;
    mapping(address => uint256) public balanceOf;
    mapping(address => mapping(address => uint256)) public allowance;

    function setTotalRaisedDAI(uint256 _raised) external {
        totalRaisedDAI = _raised;
    }

    function mint(address to, uint256 amount) external {
        balanceOf[to] += amount;
    }

    function transfer(address recipient, uint256 amount) external returns (bool) {
        require(balanceOf[msg.sender] >= amount, "Insufficient balance");
        balanceOf[msg.sender] -= amount;
        balanceOf[recipient] += amount;
        return true;
    }

    function transferFrom(address sender, address recipient, uint256 amount) external returns (bool) {
        require(balanceOf[sender] >= amount, "Insufficient balance");
        balanceOf[sender] -= amount;
        balanceOf[recipient] += amount;
        return true;
    }
}

contract ArizonaForestationDAOTest is Test {
    ArizonaForestationDAO public dao;
    MockBindingCurveToken public token;

    address owner = address(0x1);
    address constant HARDCODED_ADMIN = 0xBe53702c6f57aF155410f883f38f92414d39E3d5;
    address robotRelayerWallet = address(0x99);
    address voter1 = address(0x3);

    function setUp() public {
        vm.startPrank(owner);
        token = new MockBindingCurveToken();
        dao = new ArizonaForestationDAO(address(token));
        
        token.mint(voter1, 100_000 * 10**18);
        token.mint(address(dao), 1_000_000 * 10**18);
        vm.stopPrank();
    }

    function test_DeploymentConfiguration() public view {
        assertEq(address(dao.obsToken()), address(token));
        assertEq(dao.robotExecutionRelayer(), address(0));
        assertEq(dao.INITIAL_ADMIN(), HARDCODED_ADMIN);
        assertFalse(dao.relayerUpdatePermissionRevoked());
    }

    function test_BondingCurveMilestoneUnlock() public {
        token.setTotalRaisedDAI(5_000_000_000 * 10**18);
        bool unlocked = dao.checkAndUnlockBondingCurveFunds();
        assertTrue(unlocked);
        assertTrue(dao.bondingCurveFundsUnlocked());
    }

    function test_SetRelayerAndRevokePermission() public {
        vm.prank(HARDCODED_ADMIN);
        dao.setRobotRelayer(robotRelayerWallet);
        assertEq(dao.robotExecutionRelayer(), robotRelayerWallet);

        vm.prank(HARDCODED_ADMIN);
        dao.revokeRelayerPermissionAndLock();
        assertTrue(dao.relayerUpdatePermissionRevoked());
        assertTrue(dao.relayerLocked());
    }
}
