// SPDX-License-Identifier: MIT
pragma solidity >=0.8.20 <0.9.0;

// Ported from C++ implementation @ https://github.com/itzmeanjan/sha3/blob/e6dbb48280cc22701ea9c82fa815a25795c0fd9e/include/sha3/internals/keccak.hpp
library Keccak {
    uint256 internal constant MAX_NUM_ROUNDS = 24;
    uint256 internal constant LANE_COUNT = 25;
    uint256 private constant LANE_MASK = 0xFFFFFFFFFFFFFFFF;

    // forgefmt: disable-start
    bytes private constant RC =
        hex"0000000000000001"
        hex"0000000000008082"
        hex"800000000000808a"
        hex"8000000080008000"
        hex"000000000000808b"
        hex"0000000080000001"
        hex"8000000080008081"
        hex"8000000000008009"
        hex"000000000000008a"
        hex"0000000000000088"
        hex"0000000080008009"
        hex"000000008000000a"
        hex"000000008000808b"
        hex"800000000000008b"
        hex"8000000000008089"
        hex"8000000000008003"
        hex"8000000000008002"
        hex"8000000000000080"
        hex"000000000000800a"
        hex"800000008000000a"
        hex"8000000080008081"
        hex"8000000000008080"
        hex"0000000080000001"
        hex"8000000080008008";
    // forgefmt: disable-end

    error TooManyRounds(uint256 requested);
    error RoundsNotMultipleOfFour(uint256 requested);

    function permute(uint256[LANE_COUNT] memory a, uint256 numRounds) internal pure {
        if (numRounds > MAX_NUM_ROUNDS) revert TooManyRounds(numRounds);
        if (numRounds % 4 != 0) revert RoundsNotMultipleOfFour(numRounds);

        uint256 startsAt = MAX_NUM_ROUNDS - numRounds;
        bytes memory rc = RC;

        uint256 d0;
        uint256 d1;
        uint256 d2;
        uint256 d3;
        uint256 d4;

        for (uint256 round = startsAt; round < MAX_NUM_ROUNDS; round += 4) {
            uint256 k0;
            uint256 k1;
            uint256 k2;
            uint256 k3;

            assembly ("memory-safe") {
                let p := add(add(rc, 0x20), mul(round, 8))
                k0 := shr(192, mload(p))
                k1 := shr(192, mload(add(p, 8)))
                k2 := shr(192, mload(add(p, 16)))
                k3 := shr(192, mload(add(p, 24)))
            }

            (d0, d1, d2, d3, d4) = thetaD(a);
            round0(a, d0, d1, d2, d3, d4, k0);

            (d0, d1, d2, d3, d4) = thetaD(a);
            round1(a, d0, d1, d2, d3, d4, k1);

            (d0, d1, d2, d3, d4) = thetaD(a);
            round2(a, d0, d1, d2, d3, d4, k2);

            (d0, d1, d2, d3, d4) = thetaD(a);
            round3(a, d0, d1, d2, d3, d4, k3);
        }
    }

    function thetaD(uint256[LANE_COUNT] memory a) private pure returns (uint256 d0, uint256 d1, uint256 d2, uint256 d3, uint256 d4) {
        uint256 c0 = a[0] ^ a[5] ^ a[10] ^ a[15] ^ a[20];
        uint256 c1 = a[1] ^ a[6] ^ a[11] ^ a[16] ^ a[21];
        uint256 c2 = a[2] ^ a[7] ^ a[12] ^ a[17] ^ a[22];
        uint256 c3 = a[3] ^ a[8] ^ a[13] ^ a[18] ^ a[23];
        uint256 c4 = a[4] ^ a[9] ^ a[14] ^ a[19] ^ a[24];

        d0 = c4 ^ rol(c1, 1);
        d1 = c0 ^ rol(c2, 1);
        d2 = c1 ^ rol(c3, 1);
        d3 = c2 ^ rol(c4, 1);
        d4 = c3 ^ rol(c0, 1);
    }

    function round0(uint256[LANE_COUNT] memory a, uint256 d0, uint256 d1, uint256 d2, uint256 d3, uint256 d4, uint256 rc) private pure {
        uint256 t0;
        uint256 t1;
        uint256 t2;
        uint256 t3;
        uint256 t4;

        // group 0
        t0 = a[0] ^ d0;
        t1 = rol(a[6] ^ d1, 44);
        t2 = rol(a[12] ^ d2, 43);
        t3 = rol(a[18] ^ d3, 21);
        t4 = rol(a[24] ^ d4, 14);

        a[0] = t0 ^ (t2 & ~t1) ^ rc;
        a[6] = t1 ^ (t3 & ~t2);
        a[12] = t2 ^ (t4 & ~t3);
        a[18] = t3 ^ (t0 & ~t4);
        a[24] = t4 ^ (t1 & ~t0);

        // group 1
        t2 = rol(a[10] ^ d0, 3);
        t3 = rol(a[16] ^ d1, 45);
        t4 = rol(a[22] ^ d2, 61);
        t0 = rol(a[3] ^ d3, 28);
        t1 = rol(a[9] ^ d4, 20);

        a[10] = t0 ^ (t2 & ~t1);
        a[16] = t1 ^ (t3 & ~t2);
        a[22] = t2 ^ (t4 & ~t3);
        a[3] = t3 ^ (t0 & ~t4);
        a[9] = t4 ^ (t1 & ~t0);

        // group 2
        t4 = rol(a[20] ^ d0, 18);
        t0 = rol(a[1] ^ d1, 1);
        t1 = rol(a[7] ^ d2, 6);
        t2 = rol(a[13] ^ d3, 25);
        t3 = rol(a[19] ^ d4, 8);

        a[20] = t0 ^ (t2 & ~t1);
        a[1] = t1 ^ (t3 & ~t2);
        a[7] = t2 ^ (t4 & ~t3);
        a[13] = t3 ^ (t0 & ~t4);
        a[19] = t4 ^ (t1 & ~t0);

        // group 3
        t1 = rol(a[5] ^ d0, 36);
        t2 = rol(a[11] ^ d1, 10);
        t3 = rol(a[17] ^ d2, 15);
        t4 = rol(a[23] ^ d3, 56);
        t0 = rol(a[4] ^ d4, 27);

        a[5] = t0 ^ (t2 & ~t1);
        a[11] = t1 ^ (t3 & ~t2);
        a[17] = t2 ^ (t4 & ~t3);
        a[23] = t3 ^ (t0 & ~t4);
        a[4] = t4 ^ (t1 & ~t0);

        // group 4
        t3 = rol(a[15] ^ d0, 41);
        t4 = rol(a[21] ^ d1, 2);
        t0 = rol(a[2] ^ d2, 62);
        t1 = rol(a[8] ^ d3, 55);
        t2 = rol(a[14] ^ d4, 39);

        a[15] = t0 ^ (t2 & ~t1);
        a[21] = t1 ^ (t3 & ~t2);
        a[2] = t2 ^ (t4 & ~t3);
        a[8] = t3 ^ (t0 & ~t4);
        a[14] = t4 ^ (t1 & ~t0);
    }

    function round1(uint256[LANE_COUNT] memory a, uint256 d0, uint256 d1, uint256 d2, uint256 d3, uint256 d4, uint256 rc) private pure {
        uint256 t0;
        uint256 t1;
        uint256 t2;
        uint256 t3;
        uint256 t4;

        // group 0
        t0 = a[0] ^ d0;
        t1 = rol(a[16] ^ d1, 44);
        t2 = rol(a[7] ^ d2, 43);
        t3 = rol(a[23] ^ d3, 21);
        t4 = rol(a[14] ^ d4, 14);

        a[0] = t0 ^ (t2 & ~t1) ^ rc;
        a[16] = t1 ^ (t3 & ~t2);
        a[7] = t2 ^ (t4 & ~t3);
        a[23] = t3 ^ (t0 & ~t4);
        a[14] = t4 ^ (t1 & ~t0);

        // group 1
        t2 = rol(a[20] ^ d0, 3);
        t3 = rol(a[11] ^ d1, 45);
        t4 = rol(a[2] ^ d2, 61);
        t0 = rol(a[18] ^ d3, 28);
        t1 = rol(a[9] ^ d4, 20);

        a[20] = t0 ^ (t2 & ~t1);
        a[11] = t1 ^ (t3 & ~t2);
        a[2] = t2 ^ (t4 & ~t3);
        a[18] = t3 ^ (t0 & ~t4);
        a[9] = t4 ^ (t1 & ~t0);

        // group 2
        t4 = rol(a[15] ^ d0, 18);
        t0 = rol(a[6] ^ d1, 1);
        t1 = rol(a[22] ^ d2, 6);
        t2 = rol(a[13] ^ d3, 25);
        t3 = rol(a[4] ^ d4, 8);

        a[15] = t0 ^ (t2 & ~t1);
        a[6] = t1 ^ (t3 & ~t2);
        a[22] = t2 ^ (t4 & ~t3);
        a[13] = t3 ^ (t0 & ~t4);
        a[4] = t4 ^ (t1 & ~t0);

        // group 3
        t1 = rol(a[10] ^ d0, 36);
        t2 = rol(a[1] ^ d1, 10);
        t3 = rol(a[17] ^ d2, 15);
        t4 = rol(a[8] ^ d3, 56);
        t0 = rol(a[24] ^ d4, 27);

        a[10] = t0 ^ (t2 & ~t1);
        a[1] = t1 ^ (t3 & ~t2);
        a[17] = t2 ^ (t4 & ~t3);
        a[8] = t3 ^ (t0 & ~t4);
        a[24] = t4 ^ (t1 & ~t0);

        // group 4
        t3 = rol(a[5] ^ d0, 41);
        t4 = rol(a[21] ^ d1, 2);
        t0 = rol(a[12] ^ d2, 62);
        t1 = rol(a[3] ^ d3, 55);
        t2 = rol(a[19] ^ d4, 39);

        a[5] = t0 ^ (t2 & ~t1);
        a[21] = t1 ^ (t3 & ~t2);
        a[12] = t2 ^ (t4 & ~t3);
        a[3] = t3 ^ (t0 & ~t4);
        a[19] = t4 ^ (t1 & ~t0);
    }

    function round2(uint256[LANE_COUNT] memory a, uint256 d0, uint256 d1, uint256 d2, uint256 d3, uint256 d4, uint256 rc) private pure {
        uint256 t0;
        uint256 t1;
        uint256 t2;
        uint256 t3;
        uint256 t4;

        // group 0
        t0 = a[0] ^ d0;
        t1 = rol(a[11] ^ d1, 44);
        t2 = rol(a[22] ^ d2, 43);
        t3 = rol(a[8] ^ d3, 21);
        t4 = rol(a[19] ^ d4, 14);

        a[0] = t0 ^ (t2 & ~t1) ^ rc;
        a[11] = t1 ^ (t3 & ~t2);
        a[22] = t2 ^ (t4 & ~t3);
        a[8] = t3 ^ (t0 & ~t4);
        a[19] = t4 ^ (t1 & ~t0);

        // group 1
        t2 = rol(a[15] ^ d0, 3);
        t3 = rol(a[1] ^ d1, 45);
        t4 = rol(a[12] ^ d2, 61);
        t0 = rol(a[23] ^ d3, 28);
        t1 = rol(a[9] ^ d4, 20);

        a[15] = t0 ^ (t2 & ~t1);
        a[1] = t1 ^ (t3 & ~t2);
        a[12] = t2 ^ (t4 & ~t3);
        a[23] = t3 ^ (t0 & ~t4);
        a[9] = t4 ^ (t1 & ~t0);

        // group 2
        t4 = rol(a[5] ^ d0, 18);
        t0 = rol(a[16] ^ d1, 1);
        t1 = rol(a[2] ^ d2, 6);
        t2 = rol(a[13] ^ d3, 25);
        t3 = rol(a[24] ^ d4, 8);

        a[5] = t0 ^ (t2 & ~t1);
        a[16] = t1 ^ (t3 & ~t2);
        a[2] = t2 ^ (t4 & ~t3);
        a[13] = t3 ^ (t0 & ~t4);
        a[24] = t4 ^ (t1 & ~t0);

        // group 3
        t1 = rol(a[20] ^ d0, 36);
        t2 = rol(a[6] ^ d1, 10);
        t3 = rol(a[17] ^ d2, 15);
        t4 = rol(a[3] ^ d3, 56);
        t0 = rol(a[14] ^ d4, 27);

        a[20] = t0 ^ (t2 & ~t1);
        a[6] = t1 ^ (t3 & ~t2);
        a[17] = t2 ^ (t4 & ~t3);
        a[3] = t3 ^ (t0 & ~t4);
        a[14] = t4 ^ (t1 & ~t0);

        // group 4
        t3 = rol(a[10] ^ d0, 41);
        t4 = rol(a[21] ^ d1, 2);
        t0 = rol(a[7] ^ d2, 62);
        t1 = rol(a[18] ^ d3, 55);
        t2 = rol(a[4] ^ d4, 39);

        a[10] = t0 ^ (t2 & ~t1);
        a[21] = t1 ^ (t3 & ~t2);
        a[7] = t2 ^ (t4 & ~t3);
        a[18] = t3 ^ (t0 & ~t4);
        a[4] = t4 ^ (t1 & ~t0);
    }

    function round3(uint256[LANE_COUNT] memory a, uint256 d0, uint256 d1, uint256 d2, uint256 d3, uint256 d4, uint256 rc) private pure {
        uint256 t0;
        uint256 t1;
        uint256 t2;
        uint256 t3;
        uint256 t4;

        // group 0
        t0 = a[0] ^ d0;
        t1 = rol(a[1] ^ d1, 44);
        t2 = rol(a[2] ^ d2, 43);
        t3 = rol(a[3] ^ d3, 21);
        t4 = rol(a[4] ^ d4, 14);

        a[0] = t0 ^ (t2 & ~t1) ^ rc;
        a[1] = t1 ^ (t3 & ~t2);
        a[2] = t2 ^ (t4 & ~t3);
        a[3] = t3 ^ (t0 & ~t4);
        a[4] = t4 ^ (t1 & ~t0);

        // group 1
        t2 = rol(a[5] ^ d0, 3);
        t3 = rol(a[6] ^ d1, 45);
        t4 = rol(a[7] ^ d2, 61);
        t0 = rol(a[8] ^ d3, 28);
        t1 = rol(a[9] ^ d4, 20);

        a[5] = t0 ^ (t2 & ~t1);
        a[6] = t1 ^ (t3 & ~t2);
        a[7] = t2 ^ (t4 & ~t3);
        a[8] = t3 ^ (t0 & ~t4);
        a[9] = t4 ^ (t1 & ~t0);

        // group 2
        t4 = rol(a[10] ^ d0, 18);
        t0 = rol(a[11] ^ d1, 1);
        t1 = rol(a[12] ^ d2, 6);
        t2 = rol(a[13] ^ d3, 25);
        t3 = rol(a[14] ^ d4, 8);

        a[10] = t0 ^ (t2 & ~t1);
        a[11] = t1 ^ (t3 & ~t2);
        a[12] = t2 ^ (t4 & ~t3);
        a[13] = t3 ^ (t0 & ~t4);
        a[14] = t4 ^ (t1 & ~t0);

        // group 3
        t1 = rol(a[15] ^ d0, 36);
        t2 = rol(a[16] ^ d1, 10);
        t3 = rol(a[17] ^ d2, 15);
        t4 = rol(a[18] ^ d3, 56);
        t0 = rol(a[19] ^ d4, 27);

        a[15] = t0 ^ (t2 & ~t1);
        a[16] = t1 ^ (t3 & ~t2);
        a[17] = t2 ^ (t4 & ~t3);
        a[18] = t3 ^ (t0 & ~t4);
        a[19] = t4 ^ (t1 & ~t0);

        // group 4
        t3 = rol(a[20] ^ d0, 41);
        t4 = rol(a[21] ^ d1, 2);
        t0 = rol(a[22] ^ d2, 62);
        t1 = rol(a[23] ^ d3, 55);
        t2 = rol(a[24] ^ d4, 39);

        a[20] = t0 ^ (t2 & ~t1);
        a[21] = t1 ^ (t3 & ~t2);
        a[22] = t2 ^ (t4 & ~t3);
        a[23] = t3 ^ (t0 & ~t4);
        a[24] = t4 ^ (t1 & ~t0);
    }

    function rol(uint256 x, uint256 n) private pure returns (uint256) {
        return ((x << n) | (x >> (64 - n))) & LANE_MASK;
    }
}
