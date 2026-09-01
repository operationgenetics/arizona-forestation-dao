// SPDX-License-Identifier: MIT
pragma solidity >=0.8.20 <0.9.0;

import {Sponge} from "../crypto/Sponge.sol";
import {SHAKE256} from "../crypto/SHAKE256.sol";
import {BitPacking} from "./poly/BitPacking.sol";
import {NTT} from "./poly/NTT.sol";
import {PolyVec} from "./poly/PolyVec.sol";
import {Sampling} from "./poly/Sampling.sol";

// Ported from C++ implementation @ https://github.com/itzmeanjan/ml-dsa/blob/d4706739e3ada636d91d2838949771c79a363106/include/ml_dsa/ml_dsa_65.hpp
//
// The XOF round count is a parameter so that the same verifier serves both the ML-DSA-64 (FIPS 204) and TurboML-DSA-65 (replaces SHAKE with TurboSHAKE).
// Rate and padding are identical for both of them, only number of rounds differ.
library MLDSA65Core {
    uint256 internal constant N = 256;
    uint256 internal constant D = 13;
    uint256 internal constant K = 6;
    uint256 internal constant L = 5;
    uint256 internal constant LAMBDA = 192;
    uint256 internal constant TAU = 49;
    uint256 internal constant ETA = 4;
    uint256 internal constant OMEGA = 55;
    uint256 internal constant W1_BITS = 4;
    uint256 internal constant MAX_CTX_BYTES = 255;

    uint256 internal constant Q_BITS = 23;
    uint256 internal constant GAMMA1_BITS = 19;

    // ---------------------------------------------------------------------

    uint256 internal constant GAMMA1 = 1 << GAMMA1_BITS;
    uint256 internal constant BETA = TAU * ETA;
    uint256 internal constant Z_BOUND = GAMMA1 - BETA;

    uint256 internal constant T1_BITS = Q_BITS - D;
    uint256 internal constant Z_BITS = GAMMA1_BITS + 1;

    uint256 internal constant SEED_BYTES = 32;
    uint256 internal constant TR_BYTES = 64;
    uint256 internal constant MU_BYTES = 64;
    uint256 internal constant CTILDE_BYTES = LAMBDA / 4;

    uint256 internal constant T1_PACKED_BYTES = N * T1_BITS / 8;
    uint256 internal constant Z_PACKED_BYTES = N * Z_BITS / 8;
    uint256 internal constant W1_PACKED_BYTES = N * W1_BITS / 8;
    uint256 internal constant HINT_BYTES = OMEGA + K;

    uint256 internal constant PK_BYTES = SEED_BYTES + K * T1_PACKED_BYTES;
    uint256 internal constant SIG_BYTES = CTILDE_BYTES + L * Z_PACKED_BYTES + HINT_BYTES;

    uint256 private constant Z_OFFSET = CTILDE_BYTES;
    uint256 private constant HINT_OFFSET = Z_OFFSET + L * Z_PACKED_BYTES;
    uint256 private constant T1_OFFSET = SEED_BYTES;

    function verify(bytes memory pk, bytes memory message, bytes memory ctx, bytes memory sig, uint256 rounds) internal pure returns (bool) {
        if (ctx.length > MAX_CTX_BYTES) return false;

        bytes memory mPrime = abi.encodePacked(bytes1(0x00), bytes1(uint8(ctx.length)), ctx, message);
        return verifyInternal(pk, mPrime, sig, rounds);
    }

    function verifyInternal(bytes memory pk, bytes memory mPrime, bytes memory sig, uint256 rounds) internal pure returns (bool) {
        if (pk.length != PK_BYTES) return false;

        bytes memory tr = new bytes(TR_BYTES);
        Sponge.State memory s = Sponge.init(SHAKE256.RATE, rounds);
        Sponge.absorb(s, pk);
        Sponge.finalize(s, SHAKE256.PAD_BYTE);
        Sponge.squeeze(s, tr);

        bytes memory mu = new bytes(MU_BYTES);
        s = Sponge.init(SHAKE256.RATE, rounds);
        Sponge.absorb(s, tr);
        Sponge.absorb(s, mPrime);
        Sponge.finalize(s, SHAKE256.PAD_BYTE);
        Sponge.squeeze(s, mu);

        return verifyCore(pk, mu, sig, rounds);
    }

    function verifyCore(bytes memory pk, bytes memory mu, bytes memory sig, uint256 rounds) internal pure returns (bool) {
        if (pk.length != PK_BYTES) return false;
        if (sig.length != SIG_BYTES) return false;
        if (mu.length != MU_BYTES) return false;

        uint256[K] memory h;
        if (BitPacking.decodeHintBits(sig, HINT_OFFSET, h)) return false;
        if (PolyVec.countOnes(h) > OMEGA) return false;

        uint256[N][L] memory z;
        if (!decodeZ(sig, z)) return false;

        uint256[N] memory c;
        Sampling.sampleInBall(slice(sig, 0, CTILDE_BYTES), c, rounds);
        NTT.ntt(c);

        bytes memory w1Enc = new bytes(K * W1_PACKED_BYTES);
        computeW1(pk, z, c, h, w1Enc, rounds);

        return challengeMatches(sig, mu, w1Enc, rounds);
    }

    function decodeZ(bytes memory sig, uint256[N][L] memory z) private pure returns (bool) {
        for (uint256 j = 0; j < L; j++) {
            BitPacking.decode(sig, Z_OFFSET + j * Z_PACKED_BYTES, Z_BITS, z[j]);
            PolyVec.subFromX(z[j], GAMMA1);

            if (PolyVec.infinityNorm(z[j]) >= Z_BOUND) return false;

            NTT.ntt(z[j]);
        }

        return true;
    }

    function computeW1(bytes memory pk, uint256[N][L] memory z, uint256[N] memory c, uint256[K] memory h, bytes memory w1Enc, uint256 rounds) private pure {
        bytes32 rho;
        assembly ("memory-safe") {
            rho := mload(add(pk, 32))
        }

        uint256[N][K] memory acc;
        uint256[N][4] memory tmp;
        uint256[4] memory rows;
        uint256[4] memory cols;

        // A is generated four entries at a time. K * L is 30, so the last batch is short; its idle
        // lanes repeat an earlier entry and their output is dropped.
        for (uint256 b = 0; b < K * L; b += 4) {
            uint256 count = K * L - b < 4 ? K * L - b : 4;

            for (uint256 t = 0; t < 4; t++) {
                uint256 e = t < count ? b + t : b;
                rows[t] = e / L;
                cols[t] = e % L;
            }

            Sampling.expandA4(rho, rows, cols, tmp, rounds);

            for (uint256 t = 0; t < count; t++) {
                PolyVec.pointwiseMulAdd(acc[(b + t) / L], tmp[t], z[(b + t) % L]);
            }
        }

        uint256[N] memory t1;
        for (uint256 i = 0; i < K; i++) {
            BitPacking.decode(pk, T1_OFFSET + i * T1_PACKED_BYTES, T1_BITS, t1);
            PolyVec.shl(t1, D);
            NTT.ntt(t1);
            PolyVec.pointwiseMulSub(acc[i], c, t1);

            NTT.intt(acc[i]);
            PolyVec.useHint(h[i], acc[i]);
            BitPacking.encode(acc[i], W1_BITS, w1Enc, i * W1_PACKED_BYTES);
        }
    }

    function challengeMatches(bytes memory sig, bytes memory mu, bytes memory w1Enc, uint256 rounds) private pure returns (bool) {
        Sponge.State memory s = Sponge.init(SHAKE256.RATE, rounds);
        Sponge.absorb(s, mu);
        Sponge.absorb(s, w1Enc);
        Sponge.finalize(s, SHAKE256.PAD_BYTE);

        bytes memory expected = new bytes(CTILDE_BYTES);
        Sponge.squeeze(s, expected);

        for (uint256 i = 0; i < CTILDE_BYTES; i++) {
            if (expected[i] != sig[i]) return false;
        }

        return true;
    }

    function slice(bytes memory src, uint256 offset, uint256 len) private pure returns (bytes memory out) {
        out = new bytes(len);
        assembly ("memory-safe") {
            mcopy(add(out, 32), add(add(src, 32), offset), len)
        }
    }
}
