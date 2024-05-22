// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.8.19 <0.9.0;

import { Test, console } from "forge-std/Test.sol";

import { Deploy } from "../script/Deploy.s.sol";
import { DeploymentConfig } from "../script/DeploymentConfig.s.sol";
import { WakuRlnV2 } from "../src/WakuRlnV2.sol";
import {PoseidonT3} from "poseidon-solidity/PoseidonT3.sol";
import { LazyIMT } from "@zk-kit/imt.sol/LazyIMT.sol";

contract WakuRlnV2Test is Test {
    WakuRlnV2 internal w;
    DeploymentConfig internal deploymentConfig;

    address internal deployer;

    function setUp() public virtual {
        Deploy deployment = new Deploy();
        (w, deploymentConfig) = deployment.run();
    }

    function test__ValidRegistration() external {
        vm.pauseGasMetering();
        uint256 idCommitment = 2;
        uint32 userMessageLimit = 2;
        vm.resumeGasMetering();
        w.register(idCommitment, userMessageLimit);
        vm.pauseGasMetering();
        assertEq(w.idCommitmentIndex(), 1);
        assertEq(w.memberExists(2), true);
        (uint32 fetchedUserMessageLimit, uint32 index) = w.memberInfo(2);
        assertEq(fetchedUserMessageLimit, 2);
        assertEq(index, 0);
        uint256 rateCommitment = PoseidonT3.hash([idCommitment, userMessageLimit]);
        assertEq(w.indexToCommitment(0), rateCommitment);
        vm.resumeGasMetering();
    }
}
