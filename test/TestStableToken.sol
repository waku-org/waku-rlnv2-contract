// SPDX-License-Identifier: MIT
pragma solidity >=0.8.19 <0.9.0;

import { BaseScript } from "../script/Base.s.sol";
import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { ERC20Permit } from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Permit.sol";
import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";

error AccountNotMinter();
error AccountAlreadyMinter();
error AccountNotInMinterList();

contract TestStableToken is ERC20, ERC20Permit, Ownable {
    mapping(address => bool) public isMinter;

    event MinterAdded(address indexed account);
    event MinterRemoved(address indexed account);

    modifier onlyOwnerOrMinter() {
        if (msg.sender != owner() && !isMinter[msg.sender]) revert AccountNotMinter();
        _;
    }

    constructor() ERC20("TestStableToken", "TST") ERC20Permit("TestStableToken") Ownable() { }

    function addMinter(address account) external onlyOwner {
        if (isMinter[account]) revert AccountAlreadyMinter();
        isMinter[account] = true;
        emit MinterAdded(account);
    }

    function removeMinter(address account) external onlyOwner {
        if (!isMinter[account]) revert AccountNotInMinterList();
        isMinter[account] = false;
        emit MinterRemoved(account);
    }

    function mint(address to, uint256 amount) external onlyOwnerOrMinter {
        _mint(to, amount);
    }
}

contract TestStableTokenFactory is BaseScript {
    function run() public broadcast returns (address) {
        return address(new TestStableToken());
    }
}
