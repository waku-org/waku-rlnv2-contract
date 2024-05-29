// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.8.19 <=0.9.0;

import { WakuRlnV2 } from "../src/WakuRlnV2.sol";
import { PoseidonT3 } from "poseidon-solidity/PoseidonT3.sol";
import { LazyIMT } from "@zk-kit/imt.sol/LazyIMT.sol";
import { BaseScript } from "./Base.s.sol";
import "forge-std/console.sol";
import { Upgrades, Options } from "openzeppelin-foundry-upgrades/Upgrades.sol";
import { DeploymentConfig } from "./DeploymentConfig.s.sol";

contract Deploy is BaseScript {
    function run() public broadcast returns (WakuRlnV2 w) {
        Options memory opts;
        /*opts.unsafeAllow = "external-library-linking";*/
        opts.unsafeSkipAllChecks = true;
        address proxy = Upgrades.deployTransparentProxy(
            "WakuRlnV2.sol:WakuRlnV2", msg.sender, abi.encodeCall(WakuRlnV2.initialize, (msg.sender, 20)), opts
        );
        w = WakuRlnV2(proxy);
    }
}
