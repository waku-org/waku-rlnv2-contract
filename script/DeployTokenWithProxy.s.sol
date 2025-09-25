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
        // Read desired max supply from env or use default
        uint256 defaultMaxSupply = vm.envOr({ name: "MAX_SUPPLY", defaultValue: uint256(1_000_000 * 10 ** 18) });

        // Deploy the initial implementation
        address implementation = address(new TestStableToken());

        // Encode the initialize call (maxSupply)
        bytes memory initData = abi.encodeCall(TestStableToken.initialize, (defaultMaxSupply));

        // Deploy the proxy with initialization data
        return new ERC1967Proxy(implementation, initData);
    }
}
