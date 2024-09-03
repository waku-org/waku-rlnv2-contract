// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

interface IPriceCalculator {
    /// Returns the token and price to pay in `token` for some `_rateLimit`
    /// @param _rateLimit the rate limit the user wants to acquire
    /// @param _numberOfPeriods the number of periods the user wants to acquire
    /// @return address of the erc20 token
    /// @return uint price to pay for acquiring the specified `_rateLimit`
    function calculate(uint256 _rateLimit, uint32 _numberOfPeriods) external view returns (address, uint256);
}
