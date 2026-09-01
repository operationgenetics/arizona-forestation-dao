// SPDX-License-Identifier: MIT
pragma solidity >=0.8.20 <0.9.0;

import {Field} from "../math/Field.sol";
import {Sponge} from "../../crypto/Sponge.sol";
import {Sponge4} from "../../crypto/Sponge4.sol";
import {SHAKE128x4} from "../../crypto/SHAKE128x4.sol";
import {SHAKE256} from "../../crypto/SHAKE256.sol";

library Sampling {
    uint256 internal constant N = 256;
    uint256 internal constant TAU = 49;

    // Expands four entries of public matrix A at a time, using 4x parallel SHAKE128 XOF, SIMD-parallelized over native 256-bit word of EVM.
    // This implementation actually ports the technique from AVX2 accelerated public matrix A sampling technique in ML-KEM C++ implementation @ https://github.com/itzmeanjan/ml-kem/blob/ed73e36d518c0f27311e9c3d96d29ca981627aa0/include/ml_kem/internals/poly/sampling/avx2.hpp#L78-L149
    //
    // Last parameter `rounds` selects the XOF: 24 for SHAKE128, 12 for TurboSHAKE128. Both of them share rate and padding.
    function expandA4(bytes32 rho, uint256[4] memory rows, uint256[4] memory cols, uint256[N][4] memory out, uint256 rounds) internal pure {
        bytes[4] memory seeds;
        for (uint256 j = 0; j < 4; j++) {
            bytes memory seed = new bytes(34);
            uint256 col = cols[j];
            uint256 row = rows[j];
            assembly ("memory-safe") {
                mstore(add(seed, 32), rho)
                mstore8(add(seed, 64), col)
                mstore8(add(seed, 65), row)
            }
            seeds[j] = seed;
        }

        Sponge4.State memory s = Sponge4.init(SHAKE128x4.RATE, rounds);
        Sponge4.absorb(s, seeds);
        Sponge4.finalize(s, SHAKE128x4.PAD_BYTE);

        bytes[4] memory bufs;
        for (uint256 j = 0; j < 4; j++) {
            bufs[j] = new bytes(SHAKE128x4.RATE);
        }

        uint256[4] memory n;
        while (n[0] < N || n[1] < N || n[2] < N || n[3] < N) {
            Sponge4.squeeze(s, bufs);

            for (uint256 j = 0; j < 4; j++) {
                if (n[j] < N) n[j] = rejectionScan(bufs[j], out[j], n[j]);
            }
        }
    }

    function rejectionScan(bytes memory buf, uint256[N] memory out, uint256 n) private pure returns (uint256) {
        uint256 q = Field.Q;

        assembly ("memory-safe") {
            let p := add(buf, 32)
            let pEnd := add(p, mload(buf))
            let o := add(out, mul(n, 32))
            let outEnd := add(out, mul(N, 32))

            for {} and(lt(p, pEnd), lt(o, outEnd)) { p := add(p, 3) } {
                let w := mload(p)
                let t := or(or(byte(0, w), shl(8, byte(1, w))), shl(16, and(byte(2, w), 0x7f)))

                if lt(t, q) {
                    mstore(o, t)
                    o := add(o, 32)
                }
            }

            n := shr(5, sub(o, out))
        }

        return n;
    }

    // Last parameter `rounds` selects the XOF: 24 for SHAKE256, 12 for TurboSHAKE256.
    function sampleInBall(bytes memory seed, uint256[N] memory out, uint256 rounds) internal pure {
        Sponge.State memory s = Sponge.init(SHAKE256.RATE, rounds);
        Sponge.absorb(s, seed);
        Sponge.finalize(s, SHAKE256.PAD_BYTE);

        bytes memory signBytes = new bytes(8);
        Sponge.squeeze(s, signBytes);

        uint256 signs = 0;
        for (uint256 b = 0; b < 8; b++) {
            signs |= uint256(uint8(signBytes[b])) << (8 * b);
        }

        uint256 negOne = Field.Q - 1;
        uint256 from = N - TAU;
        uint256 i = from;

        bytes memory buf = new bytes(SHAKE256.RATE);

        while (i < N) {
            Sponge.squeeze(s, buf);

            for (uint256 off = 0; off < SHAKE256.RATE && i < N; off++) {
                uint256 t = uint8(buf[off]);
                if (t > i) continue;

                out[i] = out[t];
                out[t] = ((signs >> (i - from)) & 1) == 1 ? negOne : 1;
                i++;
            }
        }
    }
}
