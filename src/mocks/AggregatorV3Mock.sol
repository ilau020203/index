// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import "../interfaces/AggregatorV3Interface.sol";

contract AggregatorV3Mock is AggregatorV3Interface {
    int256 private _answer;

    constructor(int256 initialAnswer) {
        _answer = initialAnswer;
    }

    function latestAnswer() external view returns (int256) {
        return _answer;
    }

    function setAnswer(int256 answer) external {
        _answer = answer;
    }
}
