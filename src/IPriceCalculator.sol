// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

interface IPriceCalculator {
    /// Returns the token and price to pay in `token` for some `_rateLimit`
    /// @param _rateLimit the rate limit the user wants to acquire
    /// @return address of the erc20 token
    /// @return uint price to pay for acquiring the specified `_rateLimit`
    function calculate(uint32 _rateLimit) external view returns (address, uint256);
}
