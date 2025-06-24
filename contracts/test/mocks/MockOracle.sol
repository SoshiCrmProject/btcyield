// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import {IChainlinkOracle} from "../../src/interfaces/IChainlinkOracle.sol";

contract MockOracle is IChainlinkOracle {
    int256 public price = 50000 * 10**8; // $50,000
    uint8 public override decimals = 8;
    
    function latestRoundData() external view override returns (
        uint80 roundId,
        int256 _price,
        uint256 startedAt,
        uint256 updatedAt,
        uint80 answeredInRound
    ) {
        return (1, price, block.timestamp, block.timestamp, 1);
    }
    
    function setPrice(int256 _price) external {
        price = _price;
    }
}
