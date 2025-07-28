// SPDX-License-Identifier: MIT
pragma solidity >=0.8.19 <0.9.0;

import { BaseScript } from "../script/Base.s.sol";
import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { ERC20Permit } from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Permit.sol";

contract TestStableToken is ERC20, ERC20Permit {
    address public immutable owner;

    constructor() ERC20("TestStableToken", "TST") ERC20Permit("TestStableToken") {
        owner = msg.sender;
    }

    function mint(address to, uint256 amount) external {
        require(msg.sender == owner, "Only owner can mint");
        _mint(to, amount);
    }
}

contract TestStableTokenFactory is BaseScript {
    function run() public broadcast returns (address) {
        return address(new TestStableToken());
    }
}
