// SPDX-License-Identifier: MIT
pragma solidity >=0.8.19 <0.9.0;

import { BaseScript } from "../script/Base.s.sol";
import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract TestToken is ERC20 {
    constructor() ERC20("TestToken", "TTT") { }

    function mint(address to, uint256 amount) public {
        _mint(to, amount);
    }
}

contract TestTokenFactory is BaseScript {
    function run() public broadcast returns (address) {
        return address(new TestToken());
    }
}
