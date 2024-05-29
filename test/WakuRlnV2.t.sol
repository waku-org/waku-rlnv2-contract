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
    address internal impl;
    DeploymentConfig internal deploymentConfig;

    address internal deployer;

    function setUp() public virtual {
        Deploy deployment = new Deploy();
        (w, impl) = deployment.run();
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
        assertEq(
            w.root(),
            13_801_897_483_540_040_307_162_267_952_866_411_686_127_372_014_953_358_983_481_592_640_000_001_877_295
        );
        (uint32 fetchedUserMessageLimit2, uint32 index2, uint256 rateCommitment2) =
            w.idCommitmentToMetadata(idCommitment);
        assertEq(fetchedUserMessageLimit2, userMessageLimit);
        assertEq(index2, 0);
        assertEq(rateCommitment2, rateCommitment);
        uint256[20] memory proof = w.merkleProofElements(0);
        uint256[20] memory expectedProof = [
            0,
            14_744_269_619_966_411_208_579_211_824_598_458_697_587_494_354_926_760_081_771_325_075_741_142_829_156,
            7_423_237_065_226_347_324_353_380_772_367_382_631_490_014_989_348_495_481_811_164_164_159_255_474_657,
            11_286_972_368_698_509_976_183_087_595_462_810_875_513_684_078_608_517_520_839_298_933_882_497_716_792,
            3_607_627_140_608_796_879_659_380_071_776_844_901_612_302_623_152_076_817_094_415_224_584_923_813_162,
            19_712_377_064_642_672_829_441_595_136_074_946_683_621_277_828_620_209_496_774_504_837_737_984_048_981,
            20_775_607_673_010_627_194_014_556_968_476_266_066_927_294_572_720_319_469_184_847_051_418_138_353_016,
            3_396_914_609_616_007_258_851_405_644_437_304_192_397_291_162_432_396_347_162_513_310_381_425_243_293,
            21_551_820_661_461_729_022_865_262_380_882_070_649_935_529_853_313_286_572_328_683_688_269_863_701_601,
            6_573_136_701_248_752_079_028_194_407_151_022_595_060_682_063_033_565_181_951_145_966_236_778_420_039,
            12_413_880_268_183_407_374_852_357_075_976_609_371_175_688_755_676_981_206_018_884_971_008_854_919_922,
            14_271_763_308_400_718_165_336_499_097_156_975_241_954_733_520_325_982_997_864_342_600_795_471_836_726,
            20_066_985_985_293_572_387_227_381_049_700_832_219_069_292_839_614_107_140_851_619_262_827_735_677_018,
            9_394_776_414_966_240_069_580_838_672_673_694_685_292_165_040_808_226_440_647_796_406_499_139_370_960,
            11_331_146_992_410_411_304_059_858_900_317_123_658_895_005_918_277_453_009_197_229_807_340_014_528_524,
            15_819_538_789_928_229_930_262_697_811_477_882_737_253_464_456_578_333_862_691_129_291_651_619_515_538,
            19_217_088_683_336_594_659_449_020_493_828_377_907_203_207_941_212_636_669_271_704_950_158_751_593_251,
            21_035_245_323_335_827_719_745_544_373_081_896_983_162_834_604_456_827_698_288_649_288_827_293_579_666,
            6_939_770_416_153_240_137_322_503_476_966_641_397_417_391_950_902_474_480_970_945_462_551_409_848_591,
            10_941_962_436_777_715_901_943_463_195_175_331_263_348_098_796_018_438_960_955_633_645_115_732_864_202
        ];
        for (uint256 i = 0; i < proof.length; i++) {
            assertEq(proof[i], expectedProof[i]);
        }
        vm.resumeGasMetering();
    }

    function test__ValidRegistration(uint256 idCommitment, uint32 userMessageLimit) external {
        vm.assume(w.isValidCommitment(idCommitment) && w.isValidUserMessageLimit(userMessageLimit));

        assertEq(w.memberExists(idCommitment), false);
        w.register(idCommitment, userMessageLimit);
        uint256 rateCommitment = PoseidonT3.hash([idCommitment, userMessageLimit]);

        (uint32 fetchedUserMessageLimit, uint32 index, uint256 fetchedRateCommitment) =
            w.idCommitmentToMetadata(idCommitment);
        assertEq(fetchedUserMessageLimit, userMessageLimit);
        assertEq(index, 0);
        assertEq(fetchedRateCommitment, rateCommitment);
    }

    function test__IdCommitmentToMetadata__DoesntExist() external view {
        uint256 idCommitment = 2;
        (uint32 userMessageLimit, uint32 index, uint256 rateCommitment) = w.idCommitmentToMetadata(idCommitment);
        assertEq(userMessageLimit, 0);
        assertEq(index, 0);
        assertEq(rateCommitment, 0);
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
        /*| Name                | Type                                                | Slot | Offset | Bytes |
          |---------------------|-----------------------------------------------------|------|--------|-------|
          | MAX_MESSAGE_LIMIT   | uint32                                              | 0    | 0      | 4     |
          | SET_SIZE            | uint32                                              | 0    | 4      | 4     |
          | idCommitmentIndex   | uint32                                              | 0    | 8      | 4     |
          | memberInfo          | mapping(uint256 => struct WakuRlnV2.MembershipInfo) | 1    | 0      | 32    |
          | deployedBlockNumber | uint32                                              | 2    | 0      | 4     |
          | imtData             | struct LazyIMTData                                  | 3    | 0      | 64    |*/
        // we set MAX_MESSAGE_LIMIT to 20 (unaltered)
        // we set SET_SIZE to 4294967295 (1 << 20) (unaltered)
        // we set idCommitmentIndex to 4294967295 (1 << 20) (altered)
        vm.store(address(w), bytes32(0), 0x0000000000000000000000000000000000000000ffffffffffffffff00000014);
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

    function test__ValidPaginationQuery__OneElement() external {
        uint32 userMessageLimit = 2;
        uint256 idCommitment = 1;
        w.register(idCommitment, userMessageLimit);
        uint256[] memory commitments = w.getCommitments(0, 0);
        assertEq(commitments.length, 1);
        uint256 rateCommitment = PoseidonT3.hash([idCommitment, userMessageLimit]);
        assertEq(commitments[0], rateCommitment);
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
        assertEq(commitments.length, idCommitmentsLength + 1);
        for (uint256 i = 0; i < idCommitmentsLength; i++) {
            uint256 rateCommitment = PoseidonT3.hash([i + 1, userMessageLimit]);
            assertEq(commitments[i], rateCommitment);
        }
    }
}
