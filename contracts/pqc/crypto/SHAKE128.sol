// SPDX-License-Identifier: MIT
pragma solidity >=0.8.20 <0.9.0;

import {Sponge} from "./Sponge.sol";

library SHAKE128 {
    uint256 internal constant RATE = 168;
    uint256 internal constant ROUNDS = 24;
    uint8 internal constant PAD_BYTE = 0x1F;

    function init() internal pure returns (Sponge.State memory) {
        return Sponge.init(RATE, ROUNDS);
    }

    function absorb(Sponge.State memory s, bytes memory data) internal pure {
        Sponge.absorb(s, data);
    }

    function finalize(Sponge.State memory s) internal pure {
        Sponge.finalize(s, PAD_BYTE);
    }

    function squeeze(Sponge.State memory s, bytes memory out) internal pure {
        Sponge.squeeze(s, out);
    }

    function hash(bytes memory data, uint256 outLen) internal pure returns (bytes memory out) {
        Sponge.State memory s = init();
        absorb(s, data);
        finalize(s);
        out = new bytes(outLen);
        squeeze(s, out);
    }
}
