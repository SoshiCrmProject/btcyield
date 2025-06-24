// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

/**
 * @title FixedPoint
 * @notice Library for handling fixed-point arithmetic with 18 decimal places
 * @dev Used for precise calculations in yield and reward computations
 */
library FixedPoint {
    uint256 private constant DECIMALS = 18;
    uint256 private constant SCALAR = 10**DECIMALS;

    struct Unsigned {
        uint256 rawValue;
    }

    function fromUnscaledUint(uint256 a) internal pure returns (Unsigned memory) {
        return Unsigned(a * SCALAR);
    }

    function toUint(Unsigned memory a) internal pure returns (uint256) {
        return a.rawValue / SCALAR;
    }

    function add(Unsigned memory a, Unsigned memory b) internal pure returns (Unsigned memory) {
        return Unsigned(a.rawValue + b.rawValue);
    }

    function sub(Unsigned memory a, Unsigned memory b) internal pure returns (Unsigned memory) {
        return Unsigned(a.rawValue - b.rawValue);
    }

    function mul(Unsigned memory a, Unsigned memory b) internal pure returns (Unsigned memory) {
        return Unsigned((a.rawValue * b.rawValue) / SCALAR);
    }

    function mulCeil(Unsigned memory a, Unsigned memory b) internal pure returns (Unsigned memory) {
        uint256 product = a.rawValue * b.rawValue;
        return Unsigned((product + SCALAR - 1) / SCALAR);
    }

    function div(Unsigned memory a, Unsigned memory b) internal pure returns (Unsigned memory) {
        return Unsigned((a.rawValue * SCALAR) / b.rawValue);
    }

    function isEqual(Unsigned memory a, Unsigned memory b) internal pure returns (bool) {
        return a.rawValue == b.rawValue;
    }

    function isGreaterThan(Unsigned memory a, Unsigned memory b) internal pure returns (bool) {
        return a.rawValue > b.rawValue;
    }

    function isLessThan(Unsigned memory a, Unsigned memory b) internal pure returns (bool) {
        return a.rawValue < b.rawValue;
    }
}
