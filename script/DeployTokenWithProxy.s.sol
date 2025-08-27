// SPDX-License-Identifier: MIT
pragma solidity >=0.8.19 <0.9.0;

import { BaseScript } from "./Base.s.sol";
import { TestStableToken } from "../test/TestStableToken.sol";
import { ERC1967Proxy } from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

contract DeployTokenWithProxy is BaseScript {
    function run() public broadcast returns (address) {
        return address(deploy());
    }

    function deploy() public returns (ERC1967Proxy) {
        // Deploy the initial implementation
        address implementation = address(new TestStableToken());

        // Encode the initialize call
        bytes memory data = abi.encodeCall(TestStableToken.initialize, ());

        // Deploy the proxy with initialization data
        return new ERC1967Proxy(implementation, data);
    }
}
