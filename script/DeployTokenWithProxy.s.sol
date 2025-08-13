// SPDX-License-Identifier: MIT
pragma solidity >=0.8.19 <0.9.0;

import { BaseScript } from "./Base.s.sol";
import { TestStableToken } from "../test/TestStableToken.sol";
import { 
    TransparentUpgradeableProxy, 
    ITransparentUpgradeableProxy 
} from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import { ProxyAdmin } from "@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol";

contract DeployTokenWithProxy is BaseScript {
    function run() public broadcast returns (address proxy, address implementation, address admin) {
        // Deploy the initial implementation
        implementation = address(new TestStableToken());
        
        // Deploy proxy admin
        admin = address(new ProxyAdmin());
        
        // Deploy the proxy with empty initialization data
        proxy = address(new TransparentUpgradeableProxy(implementation, admin, ""));
        
        return (proxy, implementation, admin);
    }
}

contract UpdateTokenImplementation is BaseScript {
    function run(address proxyAddress, address proxyAdminAddress, address newImplementation) public broadcast {
        // Upgrade via ProxyAdmin using the provided implementation address
        ProxyAdmin(proxyAdminAddress).upgradeAndCall(
            ITransparentUpgradeableProxy(proxyAddress),
            newImplementation,
            ""
        );
    }
}