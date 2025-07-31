// SPDX-License-Identifier: MIT
pragma solidity >=0.8.19 <0.9.0;

import { BaseScript } from "../script/Base.s.sol";
import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { ERC20Permit } from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Permit.sol";
import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";

error AccountNotApproved();
error AccountAlreadyApproved();
error AccountNotInList();

contract TestStableToken is ERC20, ERC20Permit, Ownable {
    mapping(address => bool) public approvedAccounts;

    modifier onlyOwnerOrApproved() {
        if (msg.sender != owner() && !approvedAccounts[msg.sender]) revert AccountNotApproved();
        _;
    }

    constructor() ERC20("TestStableToken", "TST") ERC20Permit("TestStableToken") Ownable() { }

    function addApprovedAccount(address account) external onlyOwner {
        if (approvedAccounts[account]) revert AccountAlreadyApproved();
        approvedAccounts[account] = true;
    }

    function removeApprovedAccount(address account) external onlyOwner {
        if (!approvedAccounts[account]) revert AccountNotInList();
        approvedAccounts[account] = false;
    }

    function mint(address to, uint256 amount) external onlyOwnerOrApproved {
        _mint(to, amount);
    }
}

contract TestStableTokenFactory is BaseScript {
    function run() public broadcast returns (address) {
        return address(new TestStableToken());
    }
}
