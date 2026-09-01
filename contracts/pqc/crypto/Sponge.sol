// SPDX-License-Identifier: MIT
pragma solidity >=0.8.20 <0.9.0;

import {Keccak} from "./Keccak.sol";

// Ported from C++ implementation @ https://github.com/itzmeanjan/sha3/blob/81590542e105a1a148d6eba07f6c9987950ca513/include/sha3/internals/sponge.hpp
library Sponge {
    uint256 internal constant LANE_COUNT = 25;
    // Each word of the buffer hold four lanes of Keccak.
    // This buffer can hold 28 lanes.
    // Keccak has 25 lanes.
    // The buffer size is chosen to be the ceiling value needed for holding the full Keccak state.
    uint256 private constant BUF_WORDS = 7;

    uint256 private constant MASK8 = 0x00FF00FF00FF00FF00FF00FF00FF00FF00FF00FF00FF00FF00FF00FF00FF00FF;
    uint256 private constant MASK16 = 0x0000FFFF0000FFFF0000FFFF0000FFFF0000FFFF0000FFFF0000FFFF0000FFFF;
    uint256 private constant MASK32 = 0x00000000FFFFFFFF00000000FFFFFFFF00000000FFFFFFFF00000000FFFFFFFF;
    uint256 private constant LANE_MASK = 0xFFFFFFFFFFFFFFFF;

    struct State {
        uint256[LANE_COUNT] lanes;
        uint256[BUF_WORDS] buf;
        uint256 rate;
        uint256 numRounds;
        uint256 offset;
    }

    function init(uint256 rate, uint256 numRounds) internal pure returns (State memory s) {
        s.rate = rate;
        s.numRounds = numRounds;
    }

    function absorb(State memory s, bytes memory data) internal pure {
        uint256 rate = s.rate;
        uint256 offset = s.offset;
        uint256 len = data.length;
        uint256 buf = bufPtr(s);
        uint256 lanes = lanePtr(s);

        uint256 src;
        assembly ("memory-safe") {
            src := add(data, 32)
        }

        uint256 read = 0;
        while (read < len) {
            uint256 take = len - read;
            uint256 room = rate - offset;
            if (take > room) take = room;

            assembly ("memory-safe") {
                mcopy(add(buf, offset), add(src, read), take)
            }

            offset += take;
            read += take;

            if (offset == rate) {
                xorBlockIn(lanes, buf, rate);
                Keccak.permute(s.lanes, s.numRounds);
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
            mstore8(add(buf, offset), padByte)
            mstore8(add(buf, last), term)
        }

        xorBlockIn(lanes, buf, rate);
        Keccak.permute(s.lanes, s.numRounds);
        blockOut(lanes, buf, rate);

        s.offset = 0;
    }

    function squeeze(State memory s, bytes memory out) internal pure {
        uint256 rate = s.rate;
        uint256 offset = s.offset;
        uint256 len = out.length;
        uint256 buf = bufPtr(s);
        uint256 lanes = lanePtr(s);

        uint256 dst;
        assembly ("memory-safe") {
            dst := add(out, 32)
        }

        uint256 written = 0;
        while (written < len) {
            if (offset == rate) {
                Keccak.permute(s.lanes, s.numRounds);
                blockOut(lanes, buf, rate);
                offset = 0;
            }

            uint256 take = len - written;
            uint256 available = rate - offset;
            if (take > available) take = available;

            assembly ("memory-safe") {
                mcopy(add(dst, written), add(buf, offset), take)
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
                let w := mload(sp)
                w := or(shl(8, and(w, MASK8)), and(shr(8, w), MASK8))
                w := or(shl(16, and(w, MASK16)), and(shr(16, w), MASK16))
                w := or(shl(32, and(w, MASK32)), and(shr(32, w), MASK32))

                mstore(d, xor(mload(d), shr(192, w)))
                let d1 := add(d, 32)
                mstore(d1, xor(mload(d1), and(shr(128, w), LANE_MASK)))
                let d2 := add(d, 64)
                mstore(d2, xor(mload(d2), and(shr(64, w), LANE_MASK)))
                let d3 := add(d, 96)
                mstore(d3, xor(mload(d3), and(w, LANE_MASK)))

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
                let w :=
                    or(
                        or(shl(192, mload(d)), shl(128, and(mload(add(d, 32)), LANE_MASK))),
                        or(shl(64, and(mload(add(d, 64)), LANE_MASK)), and(mload(add(d, 96)), LANE_MASK))
                    )

                w := or(shl(8, and(w, MASK8)), and(shr(8, w), MASK8))
                w := or(shl(16, and(w, MASK16)), and(shr(16, w), MASK16))
                w := or(shl(32, and(w, MASK32)), and(shr(32, w), MASK32))
                mstore(dp, w)

                d := add(d, 128)
            }
        }
    }

    function clear(uint256 buf) private pure {
        assembly ("memory-safe") {
            let end := add(buf, mul(BUF_WORDS, 32))
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
        uint256[BUF_WORDS] memory b = s.buf;
        assembly ("memory-safe") {
            p := b
        }
    }
}
