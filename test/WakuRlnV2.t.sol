// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.8.19 <0.9.0;

import { Test } from "forge-std/Test.sol";
import { stdStorage, StdStorage } from "forge-std/Test.sol";

import { Deploy } from "../script/Deploy.s.sol";
import { DeploymentConfig } from "../script/DeploymentConfig.s.sol";
import "../src/WakuRlnV2.sol";
import { PoseidonT3 } from "poseidon-solidity/PoseidonT3.sol";
import { LazyIMT } from "@zk-kit/imt.sol/LazyIMT.sol";

contract WakuRlnV2Test is Test {
    using stdStorage for StdStorage;

    WakuRlnV2 internal w;
    DeploymentConfig internal deploymentConfig;

    address internal deployer;

    function setUp() public virtual {
        Deploy deployment = new Deploy();
        (w, deploymentConfig) = deployment.run();
    }

    function test__ValidRegistration__kats() external {
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
        uint256 rateCommitment =
            4_699_387_056_273_519_054_140_667_386_511_343_037_709_699_938_246_587_880_795_929_666_834_307_503_001;
        assertEq(w.indexToCommitment(0), rateCommitment);
        uint256[] memory commitments = w.getCommitments(0, 1);
        assertEq(commitments.length, 1);
        assertEq(commitments[index], rateCommitment);
        assertEq(
            w.root(),
            13_801_897_483_540_040_307_162_267_952_866_411_686_127_372_014_953_358_983_481_592_640_000_001_877_295
        );
        (uint32 fetchedUserMessageLimit2, uint32 index2, uint256 rateCommitment2) =
            w.idCommitmentToMetadata(idCommitment);
        assertEq(fetchedUserMessageLimit2, userMessageLimit);
        assertEq(index2, 0);
        assertEq(rateCommitment2, rateCommitment);
        vm.resumeGasMetering();
    }

    function test__ValidRegistration(uint256 idCommitment, uint32 userMessageLimit) external {
        vm.assume(w.isValidCommitment(idCommitment) && w.isValidUserMessageLimit(userMessageLimit));

        assertEq(w.memberExists(idCommitment), false);
        w.register(idCommitment, userMessageLimit);
        uint256[] memory commitments = w.getCommitments(0, 1);
        assertEq(commitments.length, 1);
        uint256 rateCommitment = PoseidonT3.hash([idCommitment, userMessageLimit]);
        assertEq(commitments[0], rateCommitment);

        (uint32 fetchedUserMessageLimit, uint32 index, uint256 fetchedRateCommitment) =
            w.idCommitmentToMetadata(idCommitment);
        assertEq(fetchedUserMessageLimit, userMessageLimit);
        assertEq(index, 0);
        assertEq(fetchedRateCommitment, rateCommitment);
    }

    function test__InvalidRegistration__InvalidIdCommitment__Zero() external {
        uint256 idCommitment = 0;
        uint32 userMessageLimit = 2;
        vm.expectRevert(abi.encodeWithSelector(InvalidIdCommitment.selector, 0));
        w.register(idCommitment, userMessageLimit);
    }

    function test__InvalidRegistration__InvalidIdCommitment__LargerThanField() external {
        uint256 idCommitment = w.Q() + 1;
        uint32 userMessageLimit = 2;
        vm.expectRevert(abi.encodeWithSelector(InvalidIdCommitment.selector, idCommitment));
        w.register(idCommitment, userMessageLimit);
    }

    function test__InvalidRegistration__InvalidUserMessageLimit__Zero() external {
        uint256 idCommitment = 2;
        uint32 userMessageLimit = 0;
        vm.expectRevert(abi.encodeWithSelector(InvalidUserMessageLimit.selector, 0));
        w.register(idCommitment, userMessageLimit);
    }

    function test__InvalidRegistration__InvalidUserMessageLimit__LargerThanMax() external {
        uint256 idCommitment = 2;
        uint32 userMessageLimit = w.MAX_MESSAGE_LIMIT() + 1;
        vm.expectRevert(abi.encodeWithSelector(InvalidUserMessageLimit.selector, userMessageLimit));
        w.register(idCommitment, userMessageLimit);
    }

    function test__InvalidRegistration__DuplicateIdCommitment() external {
        uint256 idCommitment = 2;
        uint32 userMessageLimit = 2;
        w.register(idCommitment, userMessageLimit);
        vm.expectRevert(DuplicateIdCommitment.selector);
        w.register(idCommitment, userMessageLimit);
    }

    function test__InvalidRegistration__FullTree() external {
        uint32 userMessageLimit = 2;
        // we progress the tree to the last leaf
        stdstore.target(address(w)).sig("idCommitmentIndex()").checked_write(1 << w.DEPTH());
        vm.expectRevert(FullTree.selector);
        w.register(1, userMessageLimit);
    }

    function test__InvalidPaginationQuery__StartIndexGTEndIndex() external {
        vm.expectRevert(abi.encodeWithSelector(InvalidPaginationQuery.selector, 1, 0));
        w.getCommitments(1, 0);
    }

    function test__InvalidPaginationQuery__EndIndexGTIdCommitmentIndex() external {
        vm.expectRevert(abi.encodeWithSelector(InvalidPaginationQuery.selector, 0, 2));
        w.getCommitments(0, 2);
    }

    function test__ValidPaginationQuery(uint32 idCommitmentsLength) external {
        vm.assume(idCommitmentsLength > 0 && idCommitmentsLength <= 100);
        uint32 userMessageLimit = 2;

        vm.pauseGasMetering();
        for (uint256 i = 0; i < idCommitmentsLength; i++) {
            w.register(i + 1, userMessageLimit);
        }
        vm.resumeGasMetering();

        uint256[] memory commitments = w.getCommitments(0, idCommitmentsLength);
        assertEq(commitments.length, idCommitmentsLength);
        for (uint256 i = 0; i < idCommitmentsLength; i++) {
            uint256 rateCommitment = PoseidonT3.hash([i + 1, userMessageLimit]);
            assertEq(commitments[i], rateCommitment);
        }
    }
}
