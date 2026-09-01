// SPDX-License-Identifier: MIT
pragma solidity >=0.8.20 <0.9.0;

import {Field} from "../math/Field.sol";
import {Rounding} from "../math/Rounding.sol";

library PolyVec {
    uint256 internal constant N = 256;
    uint256 internal constant K = 6;
    uint256 internal constant L = 5;

    function pointwiseMulAdd(uint256[N] memory acc, uint256[N] memory a, uint256[N] memory b) internal pure {
        uint256 q = Field.Q;

        assembly ("memory-safe") {
            let end := add(acc, mul(N, 32))
            let pa := a
            let pb := b

            for { let p := acc } lt(p, end) { p := add(p, 32) } {
                mstore(p, addmod(mload(p), mulmod(mload(pa), mload(pb), q), q))
                pa := add(pa, 32)
                pb := add(pb, 32)
            }
        }
    }

    function pointwiseMulSub(uint256[N] memory acc, uint256[N] memory a, uint256[N] memory b) internal pure {
        uint256 q = Field.Q;

        assembly ("memory-safe") {
            let end := add(acc, mul(N, 32))
            let pa := a
            let pb := b

            for { let p := acc } lt(p, end) { p := add(p, 32) } {
                mstore(p, addmod(mload(p), sub(q, mulmod(mload(pa), mload(pb), q)), q))
                pa := add(pa, 32)
                pb := add(pb, 32)
            }
        }
    }

    function shl(uint256[N] memory a, uint256 n) internal pure {
        uint256 q = Field.Q;
        uint256 factor = 1 << n;

        assembly ("memory-safe") {
            let end := add(a, mul(N, 32))
            for { let p := a } lt(p, end) { p := add(p, 32) } { mstore(p, mulmod(mload(p), factor, q)) }
        }
    }

    function subFromX(uint256[N] memory a, uint256 x) internal pure {
        uint256 q = Field.Q;

        assembly ("memory-safe") {
            let end := add(a, mul(N, 32))
            for { let p := a } lt(p, end) { p := add(p, 32) } { mstore(p, addmod(x, sub(q, mload(p)), q)) }
        }
    }

    function infinityNorm(uint256[N] memory a) internal pure returns (uint256 best) {
        uint256 q = Field.Q;
        uint256 half = q >> 1;

        assembly ("memory-safe") {
            let end := add(a, mul(N, 32))

            for { let p := a } lt(p, end) { p := add(p, 32) } {
                let v := mload(p)
                if gt(v, half) { v := sub(q, v) }
                if gt(v, best) { best := v }
            }
        }
    }

    function useHint(uint256 hBits, uint256[N] memory w) internal pure {
        for (uint256 i = 0; i < N; i++) {
            w[i] = Rounding.useHint((hBits >> i) & 1, w[i]);
        }
    }

    function countOnes(uint256[K] memory h) internal pure returns (uint256 total) {
        for (uint256 i = 0; i < K; i++) {
            total += popcount(h[i]);
        }
    }

    function popcount(uint256 x) internal pure returns (uint256 c) {
        assembly ("memory-safe") {
            let m1 := 0x5555555555555555555555555555555555555555555555555555555555555555
            let m2 := 0x3333333333333333333333333333333333333333333333333333333333333333
            let m4 := 0x0f0f0f0f0f0f0f0f0f0f0f0f0f0f0f0f0f0f0f0f0f0f0f0f0f0f0f0f0f0f0f0f

            x := sub(x, and(shr(1, x), m1))
            x := add(and(x, m2), and(shr(2, x), m2))
            x := and(add(x, shr(4, x)), m4)

            for { let i := 0 } lt(i, 32) { i := add(i, 1) } { c := add(c, byte(i, x)) }
        }
    }
}
