// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import { Ownable2Step } from "openzeppelin-contracts/contracts/access/Ownable2Step.sol";
import { IPriceCalculator } from "./IPriceCalculator.sol";

/// Address 0x0000...0000 was used instead of an ERC20 token address
error OnlyTokensAllowed();

/// @title Linear Price Calculator to determine the price to acquire a membership
contract LinearPriceCalculator is IPriceCalculator, Ownable2Step {
    /// @notice Address of the ERC20 token accepted by this contract.
    address public token;

    /// @notice The price per message per epoch
    uint256 public pricePerMessagePerEpoch;

    constructor(address _token, uint256 _pricePerMessagePerEpoch) Ownable2Step() {
        _setTokenAndPrice(_token, _pricePerMessagePerEpoch);
    }

    /// Set accepted token and price per message per epoch per period
    /// @param _token The token accepted by RLN membership management
    /// @param _pricePerMessagePerEpoch Price per message per epoch
    function setTokenAndPrice(address _token, uint256 _pricePerMessagePerEpoch) external onlyOwner {
        _setTokenAndPrice(_token, _pricePerMessagePerEpoch);
    }

    /// Set accepted token and price per message per epoch per period
    /// @param _token The token accepted by RLN membership management
    /// @param _pricePerMessagePerEpoch Price per message per epoch
    function _setTokenAndPrice(address _token, uint256 _pricePerMessagePerEpoch) internal {
        if (_token == address(0)) revert OnlyTokensAllowed();
        token = _token;
        pricePerMessagePerEpoch = _pricePerMessagePerEpoch;
    }

    /// Returns the token and price to pay in `token` for some `_rateLimit`
    /// @param _rateLimit the rate limit the user wants to acquire
    /// @return address of the erc20 token
    /// @return uint price to pay for acquiring the specified `_rateLimit`
    function calculate(uint32 _rateLimit) external view returns (address, uint256) {
        return (token, uint256(_rateLimit) * pricePerMessagePerEpoch);
    }
}
