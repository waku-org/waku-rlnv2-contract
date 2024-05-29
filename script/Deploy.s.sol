// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.8.19 <=0.9.0;

import { WakuRlnV2 } from "../src/WakuRlnV2.sol";
import { PoseidonT3 } from "poseidon-solidity/PoseidonT3.sol";
import { LazyIMT } from "@zk-kit/imt.sol/LazyIMT.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import { BaseScript } from "./Base.s.sol";
import "forge-std/console.sol";
import { Upgrades, Options } from "openzeppelin-foundry-upgrades/Upgrades.sol";
import { DeploymentConfig } from "./DeploymentConfig.s.sol";

contract Deploy is BaseScript {
    function run() public broadcast returns (WakuRlnV2 w, address impl) {
        /*opts.unsafeAllow = "external-library-linking";*/
        /*opts.unsafeSkipAllChecks = true;
        address proxy = Upgrades.deployTransparentProxy(
            "WakuRlnV2.sol:WakuRlnV2", msg.sender, abi.encodeCall(WakuRlnV2.initialize, (msg.sender, 20)), opts
        );
        w = WakuRlnV2(proxy);*/

        /*poseidonHasher = new PoseidonHasher();
        address implementation = address(new WakuRlnRegistry());
        bytes memory data = abi.encodeCall(WakuRlnRegistry.initialize, address(poseidonHasher));
        address proxy = address(new ERC1967Proxy(implementation, data));
        wakuRlnRegistry = WakuRlnRegistry(proxy);*/

        impl = address(new WakuRlnV2());
        bytes memory data = abi.encodeCall(WakuRlnV2.initialize, (msg.sender, 20));
        address proxy = address(new ERC1967Proxy(impl, data));
        w = WakuRlnV2(proxy);
    }
}
