// SPDX-License-Identifier: MIT
pragma solidity >=0.8.20 <0.9.0;

import {Field} from "../math/Field.sol";

library NTT {
    uint256 internal constant N = 256;
    uint256 internal constant LOG2N = 8;
    uint256 internal constant INV_N = 8_347_681;

    // forgefmt: disable-start
    bytes private constant ZETA =
        hex"000001495e023975673965694f062b53df734fe0334f066b76b1ae360dd528ed"
        hex"b0207fe439728370894a0881926d3dc84c729441e0b428a3d266528a4a18a779"
        hex"40340a52ee6b7d814e9f1d1a28772571df1649ee7611bd492bb72af69722d8d5"
        hex"36f72a30911e29d13f49267350685f2010a23887f711b2c30603a40e2bed10b7"
        hex"2c4a5f351f9d15428cd43177f420e612341c1d1ad87373668149553f3952f662"
        hex"564a65ad05439a1c53aa5f30b622087f383b0e6d2c83da1c496e330e2b1c5b70"
        hex"2ee3f1137eb957a9303ac6ef3fd54c4eb2ea503ee17bb1752648b41ef2561d90"
        hex"a245a6d42ae59b52589c6ef1f53f7288175102075d591187ba52aca9773e9e02"
        hex"96d82592ec4cff12404ce84aa5821e54e64f16c11a7e7903978f4e481731b859"
        hex"5884cc1b48275b63d05d787a35225e400c7e6c09d15bd5326bc4d3258ecb2e53"
        hex"4c097a6c3b88206d285c2ca4f8337caa14b2a055853628f18655795d4af67023"
        hex"4a8675e82678de6605528c7adf590f6e175bf3da459b7e628b345dbecb1a9e7b"
        hex"0006d96257c5574b3c69a8ef28983864b5fe7ef8f52a4e78120a230154a809b7"
        hex"ff435e87437ff85cd5b44dc04e4728af7f735d0c8d0d0f66d55a6d8061ab9818"
        hex"5d96437f314682986629604bd57928de06465d8d49b0e309b4347c0db35a68b0"
        hex"409ba964d3d521762a658591246e3948c39b7bc7594f5859392db223092312eb"
        hex"67454df230c31c28542413232e7faf802dbfcb022a0b7e832c26587a6b337509"
        hex"5b766be1cc5e061e78e00d628c373da6044ae53c1f1d686330bb7361b85ea06c"
        hex"671ac7201fc65ba4ff60d77208f2016de024080e6d56038e6956881e6d3e2603"
        hex"bd6a9dfa07c0176dbfd474d0bd63e1e35195737ab60d2867ba2decd458018c3f"
        hex"4cf50b7009427e233cbd372733336739571a4b5d1969261ef20611c14e4c76c8"
        hex"3cf42f7fb19a6af66c2e16693352d6034760085260741e782f63166f0a1107c0"
        hex"f1776d0b0d1ff03458240223d468c5595e88852faa3223fc655e694251e0ed65"
        hex"adb32ca5e679e1fe7b406435e1dd433aac464ade1cfe1473f1ce10170e74b6d7";
    // forgefmt: disable-end

    function ntt(uint256[N] memory poly) internal pure {
        uint256 tblPtr = tablePointer();
        uint256 q = Field.Q;

        for (uint256 lvl = LOG2N; lvl > 0;) {
            lvl--;
            nttLevel(poly, tblPtr, q, 32 << lvl, N >> (lvl + 1));
        }
    }

    function intt(uint256[N] memory poly) internal pure {
        uint256 tblPtr = tablePointer();
        uint256 q = Field.Q;

        for (uint256 lvl = 0; lvl < LOG2N; lvl++) {
            inttLevel(poly, tblPtr, q, 32 << lvl, (N >> lvl) - 1);
        }

        assembly ("memory-safe") {
            for { let p := poly } lt(p, add(poly, mul(N, 32))) { p := add(p, 32) } {
                mstore(p, mulmod(mload(p), INV_N, q))
            }
        }
    }

    function nttLevel(uint256[N] memory poly, uint256 tblPtr, uint256 q, uint256 lenBytes, uint256 k) private pure {
        assembly ("memory-safe") {
            let polyEnd := add(poly, mul(N, 32))

            for { let start := poly } lt(start, polyEnd) { start := add(start, shl(1, lenBytes)) } {
                let z := shr(232, mload(add(tblPtr, mul(k, 3))))
                k := add(k, 1)

                let pj := add(start, lenBytes)
                let end := pj

                switch eq(lenBytes, 32)
                case 1 {
                    let t := mulmod(z, mload(pj), q)
                    let u := mload(start)

                    mstore(pj, addmod(u, sub(q, t), q))
                    mstore(start, addmod(u, t, q))
                }
                default {
                    for { let pi := start } lt(pi, end) {} {
                        let t := mulmod(z, mload(pj), q)
                        let u := mload(pi)

                        mstore(pj, addmod(u, sub(q, t), q))
                        mstore(pi, addmod(u, t, q))

                        t := mulmod(z, mload(add(pj, 32)), q)
                        u := mload(add(pi, 32))

                        mstore(add(pj, 32), addmod(u, sub(q, t), q))
                        mstore(add(pi, 32), addmod(u, t, q))

                        pi := add(pi, 64)
                        pj := add(pj, 64)
                    }
                }
            }
        }
    }

    function inttLevel(uint256[N] memory poly, uint256 tblPtr, uint256 q, uint256 lenBytes, uint256 k) private pure {
        assembly ("memory-safe") {
            let polyEnd := add(poly, mul(N, 32))

            for { let start := poly } lt(start, polyEnd) { start := add(start, shl(1, lenBytes)) } {
                let nz := sub(q, shr(232, mload(add(tblPtr, mul(k, 3)))))
                k := sub(k, 1)

                let pj := add(start, lenBytes)
                let end := pj

                switch eq(lenBytes, 32)
                case 1 {
                    let u := mload(start)
                    let v := mload(pj)

                    mstore(start, addmod(u, v, q))
                    mstore(pj, mulmod(addmod(u, sub(q, v), q), nz, q))
                }
                default {
                    for { let pi := start } lt(pi, end) {} {
                        let u := mload(pi)
                        let v := mload(pj)

                        mstore(pi, addmod(u, v, q))
                        mstore(pj, mulmod(addmod(u, sub(q, v), q), nz, q))

                        u := mload(add(pi, 32))
                        v := mload(add(pj, 32))

                        mstore(add(pi, 32), addmod(u, v, q))
                        mstore(add(pj, 32), mulmod(addmod(u, sub(q, v), q), nz, q))

                        pi := add(pi, 64)
                        pj := add(pj, 64)
                    }
                }
            }
        }
    }

    function tablePointer() private pure returns (uint256 tblPtr) {
        bytes memory table = ZETA;
        assembly ("memory-safe") {
            tblPtr := add(table, 0x20)
        }
    }
}
