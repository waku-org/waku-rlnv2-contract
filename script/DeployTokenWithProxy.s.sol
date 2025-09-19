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
        // Read desired token cap from env or use default
        uint256 defaultCap = vm.envOr({ name: "TOKEN_CAP", defaultValue: uint256(1_000_000 * 10 ** 18) });

        // Deploy the initial implementation
        address implementation = address(new TestStableToken());

        // Encode the initialize call (cap)
        bytes memory initData = abi.encodeCall(TestStableToken.initialize, (defaultCap));

        // Deploy the proxy with initialization data
        ERC1967Proxy proxy = new ERC1967Proxy(implementation, initData);

        // Post-deploy assertions to ensure initialization succeeded
        // These revert the script if validation fails.
        address proxyAddr = address(proxy);

        // Check cap set
        uint256 actualMax = TestStableToken(proxyAddr).cap();
        if (actualMax != defaultCap) revert("Proxy token cap mismatch after initialization");

        return proxy;
    }
}
