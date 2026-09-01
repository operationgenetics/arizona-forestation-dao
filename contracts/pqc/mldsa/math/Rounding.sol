// SPDX-License-Identifier: MIT
pragma solidity >=0.8.20 <0.9.0;

import {Field} from "./Field.sol";

library Rounding {
    uint256 internal constant Q = Field.Q;
    uint256 internal constant GAMMA2 = (Q - 1) / 32;
    uint256 internal constant ALPHA = 2 * GAMMA2;
    uint256 internal constant M = (Q - 1) / ALPHA;
    uint256 internal constant NEG_THRESHOLD = Q - GAMMA2;

    function decompose(uint256 r) internal pure returns (uint256 r1, uint256 r0) {
        // forge-lint: disable-next-line(divide-before-multiply)
        uint256 t = ((r + GAMMA2 - 1) / ALPHA) * ALPHA;

        r0 = Field.sub(r, t);

        if (t == Q - 1) {
            r0 = Field.sub(r0, 1);
        } else {
            r1 = t / ALPHA;
        }
    }

    function useHint(uint256 h, uint256 r) internal pure returns (uint256) {
        (uint256 r1, uint256 r0) = decompose(r);

        if (h == 0) return r1;
        if (r0 == 0) return r1;

        if (r0 < NEG_THRESHOLD) {
            return r1 == M - 1 ? 0 : r1 + 1;
        }
        return r1 == 0 ? M - 1 : r1 - 1;
    }
}
