// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.8.19 <0.9.0;

import { Test, console } from "forge-std/Test.sol";

import { Deploy } from "../script/Deploy.s.sol";
import { DeploymentConfig } from "../script/DeploymentConfig.s.sol";
import { WakuRlnV2 } from "../src/WakuRlnV2.sol";
import { PoseidonT3 } from "poseidon-solidity/PoseidonT3.sol";
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
        assertEq(w.memberExists(idCommitment), true);
        (uint32 fetchedUserMessageLimit, uint32 index) = w.memberInfo(idCommitment);
        assertEq(fetchedUserMessageLimit, userMessageLimit);
        assertEq(index, 0);
        // kats from zerokit
        uint256 rateCommitment = 4699387056273519054140667386511343037709699938246587880795929666834307503001;
        assertEq(w.indexToCommitment(0), rateCommitment);
        uint256[] memory commitments = w.getCommitments(0, 1);
        assertEq(commitments.length, 1);
        assertEq(commitments[index], rateCommitment);
        assertEq(w.root(), 13801897483540040307162267952866411686127372014953358983481592640000001877295);
        vm.resumeGasMetering();
    }
}
