// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../contracts/ArizonaForestationDAO.sol";

contract MockOBSBindingCurveToken is IObscuraToken {
    uint256 public raisedDAI = 6_000_000_000 * 10**18;

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
}

contract ArizonaForestationDAOTest is Test {
    ArizonaForestationDAO public dao;

    function setUp() public {
        dao = new ArizonaForestationDAO();
    }

    function testConstants() public view {
        assertEq(dao.OBS_TOKEN_ADDRESS(), 0x2D8760e2877148d239a54952A458710553B2B54b);
        assertEq(dao.INITIAL_ADMIN(), 0xaF570ce3b32D765b1236635B0f541a7487A1fB8e);
        assertEq(dao.QUORUM_THRESHOLD_LP(), 100 * 10**18);
    }
}
