// SPDX-License-Identifier: MIT
pragma solidity >=0.8.20 <0.9.0;

import {Keccak4} from "./Keccak4.sol";

// Ported from C++ implementation @ https://github.com/itzmeanjan/sha3/blob/81590542e105a1a148d6eba07f6c9987950ca513/include/sha3/internals/sponge_x4.hpp
library Sponge4 {
    uint256 internal constant LANE_COUNT = 25;
    uint256 internal constant WAYS = 4;

    uint256 private constant BUF_WORDS = 7;
    uint256 private constant BUF_BYTES = 224; // sizeof(uint256) * BUF_WORDS

    uint256 private constant MASK8 = 0x00FF00FF00FF00FF00FF00FF00FF00FF00FF00FF00FF00FF00FF00FF00FF00FF;
    uint256 private constant MASK16 = 0x0000FFFF0000FFFF0000FFFF0000FFFF0000FFFF0000FFFF0000FFFF0000FFFF;
    uint256 private constant MASK32 = 0x00000000FFFFFFFF00000000FFFFFFFF00000000FFFFFFFF00000000FFFFFFFF;

    uint256 private constant F0 = 0xFFFFFFFFFFFFFFFF000000000000000000000000000000000000000000000000;
    uint256 private constant F1 = 0x0000000000000000FFFFFFFFFFFFFFFF00000000000000000000000000000000;
    uint256 private constant F2 = 0x00000000000000000000000000000000FFFFFFFFFFFFFFFF0000000000000000;
    uint256 private constant F3 = 0x000000000000000000000000000000000000000000000000FFFFFFFFFFFFFFFF;

    struct State {
        uint256[LANE_COUNT] lanes;
        uint256[BUF_WORDS * WAYS] buf;
        uint256 rate;
        uint256 numRounds;
        uint256 offset;
    }

    function init(uint256 rate, uint256 numRounds) internal pure returns (State memory s) {
        s.rate = rate;
        s.numRounds = numRounds;
    }

    function absorb(State memory s, bytes[WAYS] memory data) internal pure {
        uint256 rate = s.rate;
        uint256 offset = s.offset;
        uint256 len = data[0].length;
        uint256 buf = bufPtr(s);
        uint256 lanes = lanePtr(s);

        uint256 read = 0;
        while (read < len) {
            uint256 take = len - read;
            uint256 room = rate - offset;
            if (take > room) take = room;

            for (uint256 j = 0; j < WAYS; j++) {
                bytes memory src = data[j];
                assembly ("memory-safe") {
                    mcopy(add(add(buf, mul(j, BUF_BYTES)), offset), add(add(src, 32), read), take)
                }
            }

            offset += take;
            read += take;

            if (offset == rate) {
                xorBlockIn(lanes, buf, rate);
                Keccak4.permute(s.lanes, s.numRounds);
                clear(buf);
                offset = 0;
            }
        }

        s.offset = offset;
    }

    function finalize(State memory s, uint8 padByte) internal pure {
        uint256 rate = s.rate;
        uint256 offset = s.offset;
        uint256 buf = bufPtr(s);
        uint256 lanes = lanePtr(s);

        assembly ("memory-safe") {
            let last := sub(rate, 1)
            let term := or(0x80, mul(eq(offset, last), padByte))
            for { let j := 0 } lt(j, WAYS) { j := add(j, 1) } {
                let b := add(buf, mul(j, BUF_BYTES))
                mstore8(add(b, offset), padByte)
                mstore8(add(b, last), term)
            }
        }

        xorBlockIn(lanes, buf, rate);
        Keccak4.permute(s.lanes, s.numRounds);
        blockOut(lanes, buf, rate);

        s.offset = 0;
    }

    function squeeze(State memory s, bytes[WAYS] memory out) internal pure {
        uint256 rate = s.rate;
        uint256 offset = s.offset;
        uint256 len = out[0].length;
        uint256 buf = bufPtr(s);
        uint256 lanes = lanePtr(s);

        uint256 written = 0;
        while (written < len) {
            if (offset == rate) {
                Keccak4.permute(s.lanes, s.numRounds);
                blockOut(lanes, buf, rate);
                offset = 0;
            }

            uint256 take = len - written;
            uint256 available = rate - offset;
            if (take > available) take = available;

            for (uint256 j = 0; j < WAYS; j++) {
                bytes memory dst = out[j];
                assembly ("memory-safe") {
                    mcopy(add(add(dst, 32), written), add(add(buf, mul(j, BUF_BYTES)), offset), take)
                }
            }

            offset += take;
            written += take;
        }

        s.offset = offset;
    }

    function xorBlockIn(uint256 lanes, uint256 buf, uint256 rate) private pure {
        assembly ("memory-safe") {
            let end := add(lanes, mul(shr(2, add(shr(3, rate), 3)), 128))

            for {
                let d := lanes
                let sp := buf
            } lt(d, end) { sp := add(sp, 32) } {
                let w0 := mload(sp)
                w0 := or(shl(8, and(w0, MASK8)), and(shr(8, w0), MASK8))
                w0 := or(shl(16, and(w0, MASK16)), and(shr(16, w0), MASK16))
                w0 := or(shl(32, and(w0, MASK32)), and(shr(32, w0), MASK32))

                let w1 := mload(add(sp, BUF_BYTES))
                w1 := or(shl(8, and(w1, MASK8)), and(shr(8, w1), MASK8))
                w1 := or(shl(16, and(w1, MASK16)), and(shr(16, w1), MASK16))
                w1 := or(shl(32, and(w1, MASK32)), and(shr(32, w1), MASK32))

                let w2 := mload(add(sp, mul(2, BUF_BYTES)))
                w2 := or(shl(8, and(w2, MASK8)), and(shr(8, w2), MASK8))
                w2 := or(shl(16, and(w2, MASK16)), and(shr(16, w2), MASK16))
                w2 := or(shl(32, and(w2, MASK32)), and(shr(32, w2), MASK32))

                let w3 := mload(add(sp, mul(3, BUF_BYTES)))
                w3 := or(shl(8, and(w3, MASK8)), and(shr(8, w3), MASK8))
                w3 := or(shl(16, and(w3, MASK16)), and(shr(16, w3), MASK16))
                w3 := or(shl(32, and(w3, MASK32)), and(shr(32, w3), MASK32))

                mstore(d, xor(mload(d), or(or(and(w0, F0), shr(64, and(w1, F0))), or(shr(128, and(w2, F0)), shr(192, and(w3, F0))))))
                mstore(add(d, 32), xor(mload(add(d, 32)), or(or(shl(64, and(w0, F1)), and(w1, F1)), or(shr(64, and(w2, F1)), shr(128, and(w3, F1))))))
                mstore(add(d, 64), xor(mload(add(d, 64)), or(or(shl(128, and(w0, F2)), shl(64, and(w1, F2))), or(and(w2, F2), shr(64, and(w3, F2))))))
                mstore(add(d, 96), xor(mload(add(d, 96)), or(or(shl(192, and(w0, F3)), shl(128, and(w1, F3))), or(shl(64, and(w2, F3)), and(w3, F3)))))

                d := add(d, 128)
            }
        }
    }

    function blockOut(uint256 lanes, uint256 buf, uint256 rate) private pure {
        assembly ("memory-safe") {
            let end := add(lanes, mul(shr(2, add(shr(3, rate), 3)), 128))

            for {
                let d := lanes
                let dp := buf
            } lt(d, end) { dp := add(dp, 32) } {
                let s0 := mload(d)
                let s1 := mload(add(d, 32))
                let s2 := mload(add(d, 64))
                let s3 := mload(add(d, 96))

                let w0 := or(or(and(s0, F0), shr(64, and(s1, F0))), or(shr(128, and(s2, F0)), shr(192, and(s3, F0))))
                let w1 := or(or(shl(64, and(s0, F1)), and(s1, F1)), or(shr(64, and(s2, F1)), shr(128, and(s3, F1))))
                let w2 := or(or(shl(128, and(s0, F2)), shl(64, and(s1, F2))), or(and(s2, F2), shr(64, and(s3, F2))))
                let w3 := or(or(shl(192, and(s0, F3)), shl(128, and(s1, F3))), or(shl(64, and(s2, F3)), and(s3, F3)))

                w0 := or(shl(8, and(w0, MASK8)), and(shr(8, w0), MASK8))
                w0 := or(shl(16, and(w0, MASK16)), and(shr(16, w0), MASK16))
                w0 := or(shl(32, and(w0, MASK32)), and(shr(32, w0), MASK32))
                mstore(dp, w0)

                w1 := or(shl(8, and(w1, MASK8)), and(shr(8, w1), MASK8))
                w1 := or(shl(16, and(w1, MASK16)), and(shr(16, w1), MASK16))
                w1 := or(shl(32, and(w1, MASK32)), and(shr(32, w1), MASK32))
                mstore(add(dp, BUF_BYTES), w1)

                w2 := or(shl(8, and(w2, MASK8)), and(shr(8, w2), MASK8))
                w2 := or(shl(16, and(w2, MASK16)), and(shr(16, w2), MASK16))
                w2 := or(shl(32, and(w2, MASK32)), and(shr(32, w2), MASK32))
                mstore(add(dp, mul(2, BUF_BYTES)), w2)

                w3 := or(shl(8, and(w3, MASK8)), and(shr(8, w3), MASK8))
                w3 := or(shl(16, and(w3, MASK16)), and(shr(16, w3), MASK16))
                w3 := or(shl(32, and(w3, MASK32)), and(shr(32, w3), MASK32))
                mstore(add(dp, mul(3, BUF_BYTES)), w3)

                d := add(d, 128)
            }
        }
    }

    function clear(uint256 buf) private pure {
        assembly ("memory-safe") {
            let end := add(buf, mul(mul(BUF_WORDS, WAYS), 32))
            for { let p := buf } lt(p, end) { p := add(p, 32) } { mstore(p, 0) }
        }
    }

    function lanePtr(State memory s) private pure returns (uint256 p) {
        uint256[LANE_COUNT] memory l = s.lanes;
        assembly ("memory-safe") {
            p := l
        }
    }

    function bufPtr(State memory s) private pure returns (uint256 p) {
        uint256[BUF_WORDS * WAYS] memory b = s.buf;
        assembly ("memory-safe") {
            p := b
        }
    }
}
