// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import { Ownable } from "openzeppelin-contracts/contracts/access/Ownable.sol";
import { IPriceCalculator } from "./IPriceCalculator.sol";

/// @title Linear Price Calculator to determine the price to acquire a membership
contract LinearPriceCalculator is IPriceCalculator, Ownable {
    /// @notice Address of the ERC20 token accepted by this contract. Address(0) represents ETH
    address public token;

    /// @notice The price per message per epoch per period
    uint256 public pricePerMessagePerPeriod;

    constructor(address _token, uint256 _pricePerPeriod) Ownable() {
        token = _token;
        pricePerMessagePerPeriod = _pricePerPeriod;
    }

    /// Set accepted token and price per message per epoch per period
    /// @param _token The token accepted by the membership management for RLN
    /// @param _pricePerPeriod Price per message per epoch
    function setTokenAndPrice(address _token, uint256 _pricePerPeriod) external onlyOwner {
        token = _token;
        pricePerMessagePerPeriod = _pricePerPeriod;
    }

    /// Returns the token and price to pay in `token` for some `_rateLimit`
    /// @param _rateLimit the rate limit the user wants to acquire
    /// @param _numberOfPeriods the number of periods the user wants to acquire
    /// @return address of the erc20 token
    /// @return uint price to pay for acquiring the specified `_rateLimit`
    function calculate(uint256 _rateLimit, uint32 _numberOfPeriods) external view returns (address, uint256) {
        return (token, uint256(_numberOfPeriods) * uint256(_rateLimit) * pricePerMessagePerPeriod);
    }
}