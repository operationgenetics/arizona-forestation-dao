// SPDX-License-Identifier: MIT
pragma solidity >=0.8.20 <0.9.0;

library BitPacking {
    uint256 internal constant N = 256;
    uint256 internal constant K = 6;
    uint256 internal constant OMEGA = 55;

    function encode(uint256[N] memory poly, uint256 width, bytes memory dst, uint256 offset) internal pure {
        assembly ("memory-safe") {
            let mask := sub(shl(width, 1), 1)
            let ptr := add(add(dst, 32), offset)
            let polyEnd := add(poly, mul(N, 32))
            let acc := 0
            let accBits := 0

            for { let p := poly } lt(p, polyEnd) { p := add(p, 32) } {
                acc := or(acc, shl(accBits, and(mload(p), mask)))
                accBits := add(accBits, width)

                for {} gt(accBits, 7) {} {
                    mstore8(ptr, acc)
                    ptr := add(ptr, 1)
                    acc := shr(8, acc)
                    accBits := sub(accBits, 8)
                }
            }
        }
    }

    function decode(bytes memory src, uint256 offset, uint256 width, uint256[N] memory out) internal pure {
        assembly ("memory-safe") {
            let mask := sub(shl(width, 1), 1)
            let ptr := add(add(src, 32), offset)
            let outEnd := add(out, mul(N, 32))
            let acc := 0
            let accBits := 0

            for { let o := out } lt(o, outEnd) { o := add(o, 32) } {
                for {} lt(accBits, width) {} {
                    acc := or(acc, shl(accBits, shr(248, mload(ptr))))
                    ptr := add(ptr, 1)
                    accBits := add(accBits, 8)
                }

                mstore(o, and(acc, mask))
                acc := shr(width, acc)
                accBits := sub(accBits, width)
            }
        }
    }

    function decodeHintBits(bytes memory src, uint256 offset, uint256[K] memory h) internal pure returns (bool) {
        uint256 idx = 0;

        for (uint256 i = 0; i < K; i++) {
            uint256 till = byteAt(src, offset + OMEGA + i);
            if (till < idx || till > OMEGA) return true;

            uint256 bits = 0;
            for (uint256 j = idx; j < till; j++) {
                uint256 cur = byteAt(src, offset + j);
                if (j > idx && cur <= byteAt(src, offset + j - 1)) return true;
                bits |= 1 << cur;
            }
            h[i] = bits;

            idx = till;
        }

        for (uint256 i = idx; i < OMEGA; i++) {
            if (byteAt(src, offset + i) != 0) return true;
        }

        return false;
    }

    function byteAt(bytes memory b, uint256 i) private pure returns (uint256 v) {
        assembly ("memory-safe") {
            v := shr(248, mload(add(add(b, 32), i)))
        }
    }
}
