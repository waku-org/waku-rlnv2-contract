// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.8.19 <=0.9.0;

import { WakuRlnV2 } from "../src/WakuRlnV2.sol";
import { PoseidonT3 } from "poseidon-solidity/PoseidonT3.sol";
import { LazyIMT } from "@zk-kit/imt.sol/LazyIMT.sol";
import { ERC1967Proxy } from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import { BaseScript } from "./Base.s.sol";
import { DeploymentConfig } from "./DeploymentConfig.s.sol";

contract Deploy is BaseScript {
    function run() public broadcast returns (WakuRlnV2 w, address impl) {
        impl = address(new WakuRlnV2());
        bytes memory data = abi.encodeCall(WakuRlnV2.initialize, (msg.sender, 20));
        address proxy = address(new ERC1967Proxy(impl, data));
        w = WakuRlnV2(proxy);
    }
}
