// SPDX-License-Identifier: MIT
pragma solidity >=0.8.20 <0.9.0;

import {SHAKE128} from "./SHAKE128.sol";
import {Sponge4} from "./Sponge4.sol";

/// @dev Four independent SHAKE128 instances driven in lockstep.
// All four messages to be absorbed must be of the same length.
// Every squeeze must request the same length from all four.
library SHAKE128x4 {
    uint256 internal constant RATE = SHAKE128.RATE;
    uint256 internal constant ROUNDS = SHAKE128.ROUNDS;
    uint8 internal constant PAD_BYTE = SHAKE128.PAD_BYTE;
    uint256 internal constant WAYS = 4;

    function init() internal pure returns (Sponge4.State memory) {
        return Sponge4.init(RATE, ROUNDS);
    }

    function absorb(Sponge4.State memory s, bytes[WAYS] memory data) internal pure {
        Sponge4.absorb(s, data);
    }

    function finalize(Sponge4.State memory s) internal pure {
        Sponge4.finalize(s, PAD_BYTE);
    }

    function squeeze(Sponge4.State memory s, bytes[WAYS] memory out) internal pure {
        Sponge4.squeeze(s, out);
    }
}
