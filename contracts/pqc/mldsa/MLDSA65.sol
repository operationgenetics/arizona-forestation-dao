// SPDX-License-Identifier: MIT
pragma solidity >=0.8.20 <0.9.0;

import {SHAKE256} from "../crypto/SHAKE256.sol";
import {MLDSA65Core} from "./MLDSA65Core.sol";

// ML-DSA-65 verification, per FIPS 204 @ https://doi.org/10.6028/NIST.FIPS.204.
library MLDSA65 {
    uint256 internal constant ROUNDS = SHAKE256.ROUNDS;

    uint256 internal constant PK_BYTES = MLDSA65Core.PK_BYTES;
    uint256 internal constant SIG_BYTES = MLDSA65Core.SIG_BYTES;
    uint256 internal constant MU_BYTES = MLDSA65Core.MU_BYTES;
    uint256 internal constant CTILDE_BYTES = MLDSA65Core.CTILDE_BYTES;
    uint256 internal constant MAX_CTX_BYTES = MLDSA65Core.MAX_CTX_BYTES;

    function verify(bytes memory pk, bytes memory message, bytes memory sig) internal pure returns (bool) {
        return MLDSA65Core.verify(pk, message, "", sig, ROUNDS);
    }

    function verify(bytes memory pk, bytes memory message, bytes memory sig, bytes memory ctx) internal pure returns (bool) {
        return MLDSA65Core.verify(pk, message, ctx, sig, ROUNDS);
    }

    function verifyInternal(bytes memory pk, bytes memory mPrime, bytes memory sig) internal pure returns (bool) {
        return MLDSA65Core.verifyInternal(pk, mPrime, sig, ROUNDS);
    }

    function verifyCore(bytes memory pk, bytes memory mu, bytes memory sig) internal pure returns (bool) {
        return MLDSA65Core.verifyCore(pk, mu, sig, ROUNDS);
    }
}
