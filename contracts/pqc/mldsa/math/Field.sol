// SPDX-License-Identifier: MIT
pragma solidity >=0.8.20 <0.9.0;

library Field {
    uint256 internal constant Q = 8_380_417;
    uint256 internal constant Q_HALF = Q / 2;

    function add(uint256 a, uint256 b) internal pure returns (uint256) {
        return addmod(a, b, Q);
    }

    function sub(uint256 a, uint256 b) internal pure returns (uint256) {
        return addmod(a, Q - b, Q);
    }

    function neg(uint256 a) internal pure returns (uint256) {
        return addmod(0, Q - a, Q);
    }

    function mul(uint256 a, uint256 b) internal pure returns (uint256) {
        return mulmod(a, b, Q);
    }

    function shl(uint256 a, uint256 n) internal pure returns (uint256) {
        return mulmod(a, 1 << n, Q);
    }

    function centeredAbs(uint256 a) internal pure returns (uint256) {
        return a > Q_HALF ? Q - a : a;
    }
}
