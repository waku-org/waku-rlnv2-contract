// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.8.19 <0.9.0;

import { Test, console } from "forge-std/Test.sol";

import { Deploy } from "../script/Deploy.s.sol";
import { DeploymentConfig } from "../script/DeploymentConfig.s.sol";
import { WakuRlnV2 } from "../src/WakuRlnV2.sol";

contract WakuRlnV2Test is Test {
    WakuRlnV2 internal w;
    DeploymentConfig internal deploymentConfig;

    address internal deployer;

    function setUp() public virtual {
        Deploy deployment = new Deploy();
        (w, deploymentConfig) = deployment.run();
    }

    function test__ValidRegistration() external { }
}
