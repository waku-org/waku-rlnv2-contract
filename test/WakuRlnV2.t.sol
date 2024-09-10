// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.8.19 <0.9.0;

import { Test } from "forge-std/Test.sol";
import { Deploy } from "../script/Deploy.s.sol";
import { DeploymentConfig } from "../script/DeploymentConfig.s.sol";
import "../src/WakuRlnV2.sol"; // solhint-disable-line
import "../src/Membership.sol"; // solhint-disable-line
import { IPriceCalculator } from "../src/IPriceCalculator.sol";
import { LinearPriceCalculator } from "../src/LinearPriceCalculator.sol";
import { TestToken } from "./TestToken.sol";
import { PoseidonT3 } from "poseidon-solidity/PoseidonT3.sol";
import { UUPSUpgradeable } from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import { ERC1967Proxy } from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import "forge-std/console.sol";

contract WakuRlnV2Test is Test {
    WakuRlnV2 internal w;
    address internal impl;
    DeploymentConfig internal deploymentConfig;
    TestToken internal token;

    address internal deployer;

    function setUp() public virtual {
        token = new TestToken();

        Deploy deployment = new Deploy();
        (w, impl) = deployment.run(address(token));

        // Minting a large number of tokens to not have to worry about
        // Not having enough balance
        token.mint(address(this), 100_000_000 ether);
    }

    function test__ValidRegistration__kats() external {
        vm.pauseGasMetering();
        // Merkle tree leaves are calculated using 2 as rateLimit
        vm.prank(w.owner());
        w.setMinRateLimitPerMembership(2);

        uint256 idCommitment = 2;
        uint32 userMessageLimit = 2;
        (, uint256 price) = w.priceCalculator().calculate(userMessageLimit);
        vm.resumeGasMetering();
        token.approve(address(w), price);
        w.register(idCommitment, userMessageLimit);
        vm.pauseGasMetering();
        assertEq(w.commitmentIndex(), 1);
        assertEq(w.memberExists(idCommitment), true);
        (,,,,, uint32 fetchedUserMessageLimit, uint32 index, address holder,) = w.members(idCommitment);
        assertEq(fetchedUserMessageLimit, userMessageLimit);
        assertEq(holder, address(this));
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

    function test__ValidRegistration(uint32 userMessageLimit) external {
        vm.pauseGasMetering();
        uint256 idCommitment = 2;
        (, uint256 price) = w.priceCalculator().calculate(userMessageLimit);
        uint256 minUserMessageLimit = w.minRateLimitPerMembership();
        uint256 maxUserMessageLimit = w.maxRateLimitPerMembership();
        vm.assume(userMessageLimit >= minUserMessageLimit && userMessageLimit <= maxUserMessageLimit);
        vm.assume(w.isValidUserMessageLimit(userMessageLimit));
        vm.resumeGasMetering();

        assertEq(w.memberExists(idCommitment), false);
        token.approve(address(w), price);
        w.register(idCommitment, userMessageLimit);
        uint256 rateCommitment = PoseidonT3.hash([idCommitment, userMessageLimit]);

        (uint32 fetchedUserMessageLimit, uint32 index, uint256 fetchedRateCommitment) =
            w.idCommitmentToMetadata(idCommitment);
        assertEq(fetchedUserMessageLimit, userMessageLimit);
        assertEq(index, 0);
        assertEq(fetchedRateCommitment, rateCommitment);

        assertEq(token.balanceOf(address(w)), price);
        assertEq(w.totalRateLimitPerEpoch(), userMessageLimit);
    }

    function test__InsertionNormalOrder(uint32 idCommitmentsLength) external {
        vm.assume(idCommitmentsLength > 0 && idCommitmentsLength <= 50);

        uint32 userMessageLimit = w.minRateLimitPerMembership();
        (, uint256 price) = w.priceCalculator().calculate(userMessageLimit);

        // Register some commitments
        for (uint256 i = 0; i < idCommitmentsLength; i++) {
            uint256 idCommitment = i + 1;
            token.approve(address(w), price);
            w.register(idCommitment, userMessageLimit);
            (uint256 prev, uint256 next,,,,,,,) = w.members(idCommitment);
            // new membership will always be the tail
            assertEq(next, 0);
            assertEq(w.tail(), idCommitment);
            // current membership prevLink will always point to previous membership
            assertEq(prev, idCommitment - 1);
        }
        assertEq(w.head(), 1);
        assertEq(w.tail(), idCommitmentsLength);

        // Ensure that prev and next are chained correctly
        for (uint256 i = 0; i < idCommitmentsLength; i++) {
            uint256 idCommitment = i + 1;
            (uint256 prev, uint256 next,,,,,,,) = w.members(idCommitment);

            assertEq(prev, idCommitment - 1);
            if (i == idCommitmentsLength - 1) {
                assertEq(next, 0);
            } else {
                assertEq(next, idCommitment + 1);
            }
        }
    }

    function test__LinearPriceCalculation(uint32 userMessageLimit) external view {
        IPriceCalculator priceCalculator = w.priceCalculator();
        uint256 pricePerMessagePerPeriod = LinearPriceCalculator(address(priceCalculator)).pricePerMessagePerEpoch();
        assertNotEq(pricePerMessagePerPeriod, 0);
        uint256 expectedPrice = uint256(userMessageLimit) * pricePerMessagePerPeriod;
        (, uint256 price) = w.priceCalculator().calculate(userMessageLimit);
        assertEq(price, expectedPrice);
    }

    function test__InvalidTokenAmount(uint256 idCommitment, uint32 userMessageLimit) external {
        vm.pauseGasMetering();
        uint256 minUserMessageLimit = w.minRateLimitPerMembership();
        uint256 maxUserMessageLimit = w.maxRateLimitPerMembership();
        vm.assume(userMessageLimit >= minUserMessageLimit && userMessageLimit <= maxUserMessageLimit);
        vm.assume(w.isValidCommitment(idCommitment) && w.isValidUserMessageLimit(userMessageLimit));
        (, uint256 price) = w.priceCalculator().calculate(userMessageLimit);
        vm.resumeGasMetering();

        token.approve(address(w), price - 1);
        vm.expectRevert(bytes("ERC20: insufficient allowance"));
        w.register(idCommitment, userMessageLimit);
    }

    function test__IdCommitmentToMetadata__DoesntExist() external view {
        uint256 idCommitment = 2;
        (uint32 userMessageLimit, uint32 index, uint256 rateCommitment) = w.idCommitmentToMetadata(idCommitment);
        assertEq(userMessageLimit, 0);
        assertEq(index, 0);
        assertEq(rateCommitment, 0);
    }

    function test__InvalidRegistration__InvalidIdCommitment__Zero() external {
        vm.pauseGasMetering();
        uint256 idCommitment = 0;
        uint32 userMessageLimit = 2;
        (, uint256 price) = w.priceCalculator().calculate(userMessageLimit);
        vm.resumeGasMetering();

        token.approve(address(w), price);
        vm.expectRevert(abi.encodeWithSelector(InvalidIdCommitment.selector, 0));
        w.register(idCommitment, userMessageLimit);
    }

    function test__InvalidRegistration__InvalidIdCommitment__LargerThanField() external {
        vm.pauseGasMetering();
        uint32 userMessageLimit = 20;
        (, uint256 price) = w.priceCalculator().calculate(userMessageLimit);
        vm.resumeGasMetering();

        uint256 idCommitment = w.Q() + 1;
        token.approve(address(w), price);
        vm.expectRevert(abi.encodeWithSelector(InvalidIdCommitment.selector, idCommitment));
        w.register(idCommitment, userMessageLimit);
    }

    function test__InvalidRegistration__InvalidUserMessageLimit__MinMax() external {
        uint256 idCommitment = 2;

        uint32 invalidMin = w.minRateLimitPerMembership() - 1;
        uint32 invalidMax = w.maxRateLimitPerMembership() + 1;

        vm.expectRevert(abi.encodeWithSelector(InvalidRateLimit.selector));
        w.register(idCommitment, invalidMin);

        vm.expectRevert(abi.encodeWithSelector(InvalidRateLimit.selector));
        w.register(idCommitment, invalidMax);
    }

    function test__ValidRegistrationExtend(uint32 userMessageLimit) external {
        vm.pauseGasMetering();
        uint256 idCommitment = 2;
        (, uint256 price) = w.priceCalculator().calculate(userMessageLimit);
        vm.assume(
            userMessageLimit >= w.minRateLimitPerMembership() && userMessageLimit <= w.maxRateLimitPerMembership()
        );
        vm.assume(w.isValidUserMessageLimit(userMessageLimit));
        vm.resumeGasMetering();

        token.approve(address(w), price);
        w.register(idCommitment, userMessageLimit);
        (,,, uint256 gracePeriodStartDate,,,,,) = w.members(idCommitment);

        assertFalse(w.isGracePeriod(idCommitment));
        assertFalse(w.isExpired(idCommitment));

        vm.warp(gracePeriodStartDate);

        assertTrue(w.isGracePeriod(idCommitment));
        assertFalse(w.isExpired(idCommitment));

        // Registering other memberships just to check linkage is correct
        for (uint256 i = 1; i < 5; i++) {
            token.approve(address(w), price);
            w.register(idCommitment + i, userMessageLimit);
        }

        assertEq(w.head(), idCommitment);

        uint256[] memory commitmentsToExtend = new uint256[](1);
        commitmentsToExtend[0] = idCommitment;

        // Attempt to extend the membership (but it is not owned by us)
        address randomAddress = vm.addr(block.timestamp);
        vm.prank(randomAddress);
        vm.expectRevert(abi.encodeWithSelector(NotHolder.selector, commitmentsToExtend[0]));
        w.extend(commitmentsToExtend);

        // Attempt to extend the membership (but now we are the owner)
        vm.expectEmit(true, false, false, false); // only check the first parameter of the event (the idCommitment)
        emit Membership.MemberExtended(idCommitment, 0, 0, 0);
        w.extend(commitmentsToExtend);

        (,,, uint256 newGracePeriodStartDate,,,,,) = w.members(idCommitment);

        assertEq(block.timestamp + uint256(w.expirationTerm()), newGracePeriodStartDate);
        assertFalse(w.isGracePeriod(idCommitment));
        assertFalse(w.isExpired(idCommitment));

        // Verify list order is correct
        assertEq(w.tail(), idCommitment);
        assertEq(w.head(), idCommitment + 1);

        // Ensure that prev and next are chained correctly
        for (uint256 i = 0; i < 5; i++) {
            uint256 currIdCommitment = idCommitment + i;
            (uint256 prev, uint256 next,,,,,,,) = w.members(currIdCommitment);
            console.log("idCommitment: %s - prev: %s - next: %s", currIdCommitment, prev, next);
            if (i == 0) {
                // Verifying links of extended idCommitment
                assertEq(next, 0);
                assertEq(prev, idCommitment + 4);
            } else if (i == 1) {
                // The second element in the chain became the oldest
                assertEq(next, currIdCommitment + 1);
                assertEq(prev, 0);
            } else if (i == 4) {
                assertEq(prev, currIdCommitment - 1);
                assertEq(next, idCommitment);
            } else {
                // The rest of the elements maintain their order
                assertEq(prev, currIdCommitment - 1);
                assertEq(next, currIdCommitment + 1);
            }
        }

        // Attempt to extend a non grace period membership
        commitmentsToExtend[0] = idCommitment + 1;
        vm.expectRevert(abi.encodeWithSelector(NotInGracePeriod.selector, commitmentsToExtend[0]));
        w.extend(commitmentsToExtend);
    }

    function test__ValidRegistrationExtendSingleMembership(uint32 userMessageLimit) external {
        vm.pauseGasMetering();
        uint256 idCommitment = 2;
        (, uint256 price) = w.priceCalculator().calculate(userMessageLimit);
        vm.assume(
            userMessageLimit >= w.minRateLimitPerMembership() && userMessageLimit <= w.maxRateLimitPerMembership()
        );
        vm.assume(w.isValidUserMessageLimit(userMessageLimit));
        vm.resumeGasMetering();

        token.approve(address(w), price);
        w.register(idCommitment, userMessageLimit);
        (,,, uint256 gracePeriodStartDate,,,,,) = w.members(idCommitment);

        vm.warp(gracePeriodStartDate);

        uint256[] memory commitmentsToExtend = new uint256[](1);
        commitmentsToExtend[0] = idCommitment;

        // Extend the membership
        vm.expectEmit(true, false, false, false); // only check the first parameter of the event (the idCommitment)
        emit Membership.MemberExtended(idCommitment, 0, 0, 0);
        w.extend(commitmentsToExtend);

        // Verify list order is correct
        assertEq(w.tail(), idCommitment);
        assertEq(w.head(), idCommitment);
        (uint256 prev, uint256 next,,,,,,,) = w.members(idCommitment);
        assertEq(next, 0);
        assertEq(prev, 0);
    }

    function test__ValidRegistrationExpiry(uint32 userMessageLimit) external {
        vm.pauseGasMetering();
        uint256 idCommitment = 2;
        (, uint256 price) = w.priceCalculator().calculate(userMessageLimit);
        vm.assume(
            userMessageLimit >= w.minRateLimitPerMembership() && userMessageLimit <= w.maxRateLimitPerMembership()
        );
        vm.assume(w.isValidUserMessageLimit(userMessageLimit));
        vm.resumeGasMetering();

        token.approve(address(w), price);
        w.register(idCommitment, userMessageLimit);

        (,,, uint256 fetchedGracePeriodStartDate, uint32 fetchedGracePeriod,,,,) = w.members(idCommitment);

        uint256 expectedExpirationDate = fetchedGracePeriodStartDate + uint256(fetchedGracePeriod) + 1;
        uint256 expirationDate = w.expirationDate(idCommitment);

        assertEq(expectedExpirationDate, expirationDate);

        vm.warp(expirationDate);

        assertFalse(w.isGracePeriod(idCommitment));
        assertTrue(w.isExpired(idCommitment));

        // Registering other memberships just to check linkage is correct
        for (uint256 i = 1; i <= 5; i++) {
            token.approve(address(w), price);
            w.register(idCommitment + i, userMessageLimit);
        }

        assertEq(w.head(), idCommitment);
        assertEq(w.tail(), idCommitment + 5);
    }

    function test__ValidRegistrationWithEraseList() external {
        vm.pauseGasMetering();
        vm.startPrank(w.owner());
        w.setMinRateLimitPerMembership(20);
        w.setMaxRateLimitPerMembership(100);
        w.setMaxTotalRateLimitPerEpoch(100);
        vm.stopPrank();
        vm.resumeGasMetering();

        (, uint256 price) = w.priceCalculator().calculate(20);

        for (uint256 i = 1; i <= 5; i++) {
            token.approve(address(w), price);
            w.register(i, 20);
            // Make sure they're expired
            vm.warp(w.expirationDate(i));
        }

        // Time travel to a point in which the last commitment is active
        (,,, uint256 gracePeriodStartDate,,,,,) = w.members(5);
        vm.warp(gracePeriodStartDate - 1);

        // Ensure that this is the case
        assertTrue(w.isExpired(4));
        assertFalse(w.isExpired(5));
        assertFalse(w.isGracePeriod(5));

        (, price) = w.priceCalculator().calculate(60);
        token.approve(address(w), price);

        // Attempt to expire 3 commitments including one that can't be erased (the last one)
        uint256[] memory commitmentsToErase = new uint256[](3);
        commitmentsToErase[0] = 1;
        commitmentsToErase[1] = 2;
        commitmentsToErase[2] = 5; // This one is still active
        token.approve(address(w), price);
        vm.expectRevert(abi.encodeWithSelector(CantEraseMembership.selector, 5));
        w.register(6, 60, commitmentsToErase);

        // Attempt to expire 3 commitments that can be erased
        commitmentsToErase[2] = 4;
        vm.expectEmit(true, false, false, false);
        emit Membership.MemberExpired(1, 0, 0);
        vm.expectEmit(true, false, false, false);
        emit Membership.MemberExpired(2, 0, 0);
        vm.expectEmit(true, false, false, false);
        emit Membership.MemberExpired(4, 0, 0);
        w.register(6, 60, commitmentsToErase);

        // Ensure that the chosen memberships were erased and others unaffected
        address holder;
        (,,,,,,, holder,) = w.members(1);
        assertEq(holder, address(0));
        (,,,,,,, holder,) = w.members(2);
        assertEq(holder, address(0));
        (,,,,,,, holder,) = w.members(3);
        assertEq(holder, address(this));
        (,,,,,,, holder,) = w.members(4);
        assertEq(holder, address(0));
        (,,,,,,, holder,) = w.members(5);
        assertEq(holder, address(this));
        (,,,,,,, holder,) = w.members(6);
        assertEq(holder, address(this));
    }

    function test__RegistrationWhenMaxRateLimitIsReached() external {
        vm.pauseGasMetering();
        vm.startPrank(w.owner());
        w.setMinRateLimitPerMembership(1);
        w.setMaxRateLimitPerMembership(5);
        w.setMaxTotalRateLimitPerEpoch(5);
        vm.stopPrank();
        vm.resumeGasMetering();

        bool isValid = w.isValidUserMessageLimit(6);
        assertFalse(isValid);

        // Exceeds the max rate limit per user
        uint32 userMessageLimit = 10;
        (, uint256 price) = w.priceCalculator().calculate(userMessageLimit);
        token.approve(address(w), price);
        vm.expectRevert(abi.encodeWithSelector(InvalidRateLimit.selector));
        w.register(1, userMessageLimit);

        // Should register succesfully
        userMessageLimit = 4;
        (, price) = w.priceCalculator().calculate(userMessageLimit);
        token.approve(address(w), price);
        w.register(2, userMessageLimit);

        // Exceeds the rate limit
        userMessageLimit = 2;
        (, price) = w.priceCalculator().calculate(userMessageLimit);
        token.approve(address(w), price);
        vm.expectRevert(abi.encodeWithSelector(ExceedAvailableMaxRateLimitPerEpoch.selector));
        w.register(3, userMessageLimit);

        // Should register succesfully
        userMessageLimit = 1;
        (, price) = w.priceCalculator().calculate(userMessageLimit);
        token.approve(address(w), price);
        w.register(3, userMessageLimit);

        // We ran out of rate limit again
        userMessageLimit = 1;
        (, price) = w.priceCalculator().calculate(userMessageLimit);
        token.approve(address(w), price);
        vm.expectRevert(abi.encodeWithSelector(ExceedAvailableMaxRateLimitPerEpoch.selector));
        w.register(4, userMessageLimit);
    }

    function test__RegistrationWhenMaxRateLimitIsReachedAndSingleExpiredMemberAvailable() external {
        vm.pauseGasMetering();
        vm.startPrank(w.owner());
        w.setMinRateLimitPerMembership(1);
        w.setMaxRateLimitPerMembership(5);
        w.setMaxTotalRateLimitPerEpoch(5);
        vm.stopPrank();
        vm.resumeGasMetering();

        uint32 userMessageLimitA = 2;
        uint32 totalUserMessageLimit = userMessageLimitA;
        (, uint256 priceA) = w.priceCalculator().calculate(userMessageLimitA);
        token.approve(address(w), priceA);
        w.register(1, userMessageLimitA);

        (,,, uint256 gracePeriodStartDate,,, uint32 indexA,,) = w.members(1);
        vm.warp(gracePeriodStartDate + 1);

        // Exceeds the rate limit, but if the first were expired, it should register
        // It is in grace period so can't be erased
        assertTrue(w.isGracePeriod(1));
        assertFalse(w.isExpired(1));
        uint32 userMessageLimitB = 4;
        (, uint256 priceB) = w.priceCalculator().calculate(userMessageLimitB);
        (, priceB) = w.priceCalculator().calculate(userMessageLimitB);
        token.approve(address(w), priceB);
        vm.expectRevert(abi.encodeWithSelector(ExceedAvailableMaxRateLimitPerEpoch.selector));
        w.register(2, userMessageLimitB);

        // FFW until the membership is expired so we can get rid of it
        uint256 expirationDate = w.expirationDate(1);
        vm.warp(expirationDate);
        assertTrue(w.isExpired(1));

        // It should succeed now
        vm.expectEmit();
        emit Membership.MemberExpired(1, userMessageLimitA, indexA);
        w.register(2, userMessageLimitB);

        // The previous expired membership should have been erased
        (,,,,,,, address holder,) = w.members(1);
        assertEq(holder, address(0));

        uint32 expectedUserMessageLimit = totalUserMessageLimit - userMessageLimitA + userMessageLimitB;
        assertEq(expectedUserMessageLimit, w.totalRateLimitPerEpoch());

        // The new commitment should be the only element in the list
        assertEq(w.head(), 2);
        assertEq(w.tail(), 2);
        (uint256 prev, uint256 next,,,,, uint32 indexB,,) = w.members(2);
        assertEq(prev, 0);
        assertEq(next, 0);

        // Index should have been reused
        assertEq(indexA, indexB);

        // The balance available for withdrawal should match the amount of the expired membership
        uint256 availableBalance = w.balancesToWithdraw(address(this), address(token));
        assertEq(availableBalance, priceA);
    }

    function test__RegistrationWhenMaxRateLimitIsReachedAndMultipleExpiredMembersAvailable() external {
        vm.pauseGasMetering();
        vm.startPrank(w.owner());
        w.setMinRateLimitPerMembership(1);
        w.setMaxRateLimitPerMembership(5);
        w.setMaxTotalRateLimitPerEpoch(5);
        vm.stopPrank();
        vm.resumeGasMetering();

        (, uint256 priceA) = w.priceCalculator().calculate(1);
        token.approve(address(w), priceA);
        w.register(1, 1);
        vm.warp(block.timestamp + 100);
        token.approve(address(w), priceA);
        w.register(2, 1);
        vm.warp(block.timestamp + 100);
        uint256 expirationDate = w.expirationDate(2);
        vm.warp(expirationDate);
        token.approve(address(w), priceA);
        w.register(3, 1);

        // Make sure only the first 2 memberships are expired
        assertTrue(w.isExpired(1));
        assertTrue(w.isExpired(2));
        assertFalse(w.isExpired(3) || w.isGracePeriod(3));

        (,,,,,, uint32 index1,,) = w.members(1);
        (,,,,,, uint32 index2,,) = w.members(2);

        // Attempt to register a membership that will require to expire 2 memberships
        // Currently there is 2 available, and we want to register 4
        // If we remove first membership, we'll have 3 available
        // If we also remove the second, we'll have 4 available
        (, uint256 priceB) = w.priceCalculator().calculate(4);
        token.approve(address(w), priceB);
        vm.expectEmit(true, false, false, false);
        emit Membership.MemberExpired(1, 0, 0);
        vm.expectEmit(true, false, false, false);
        emit Membership.MemberExpired(2, 0, 0);
        w.register(4, 4);

        // idCommitment4 will use the last removed index available (since we push to an array)
        (,,,,,, uint32 index4,,) = w.members(4);
        assertEq(index4, index2);

        // the index of the first removed membership is still available for further registrations
        assertEq(index1, w.availableExpiredIndices(0));

        // The previous expired memberships should have been erased
        (,,,,,,, address holder,) = w.members(1);
        assertEq(holder, address(0));
        (,,,,,,, holder,) = w.members(2);
        assertEq(holder, address(0));

        // The total rate limit used should be those from idCommitment 3 and 4
        assertEq(5, w.totalRateLimitPerEpoch());

        // There should only be 2 memberships, the non expired and the new one
        assertEq(w.head(), 3);
        assertEq(w.tail(), 4);
        (uint256 prev, uint256 next,,,,,,,) = w.members(3);
        assertEq(prev, 0);
        assertEq(next, 4);
        (prev, next,,,,,,,) = w.members(4);
        assertEq(prev, 3);
        assertEq(next, 0);

        // The balance available for withdrawal should match the amount of the expired membership
        uint256 availableBalance = w.balancesToWithdraw(address(this), address(token));
        assertEq(availableBalance, priceA * 2);
    }

    function test__RegistrationWhenMaxRateLimitReachedAndMultipleExpiredMembersAvailableWithoutEnoughRateLimit()
        external
    {
        vm.pauseGasMetering();
        vm.startPrank(w.owner());
        w.setMinRateLimitPerMembership(1);
        w.setMaxRateLimitPerMembership(5);
        w.setMaxTotalRateLimitPerEpoch(5);
        vm.stopPrank();
        vm.resumeGasMetering();

        (, uint256 priceA) = w.priceCalculator().calculate(1);
        token.approve(address(w), priceA);
        w.register(1, 1);
        vm.warp(block.timestamp + 100);
        token.approve(address(w), priceA);
        w.register(2, 1);
        vm.warp(block.timestamp + 100);
        uint256 expirationDate = w.expirationDate(2);
        vm.warp(expirationDate);
        token.approve(address(w), priceA);
        w.register(3, 1);

        // Make sure only the first 2 memberships are expired
        assertTrue(w.isExpired(1));
        assertTrue(w.isExpired(2));
        assertFalse(w.isExpired(3) || w.isGracePeriod(3));

        // Attempt to register a membership that will require to expire 2 memberships
        // Currently there is 2 available, and we want to register 5
        // If we remove first membership, we'll have 3 available
        // If we also remove the second, we'll have 4 available, but it is still not enough
        // for registering
        (, uint256 priceB) = w.priceCalculator().calculate(5);
        token.approve(address(w), priceB);
        vm.expectRevert(abi.encodeWithSelector(ExceedAvailableMaxRateLimitPerEpoch.selector));
        w.register(4, 5);
    }

    function test__indexReuse_eraseMemberships(uint32 idCommitmentsLength) external {
        vm.assume(idCommitmentsLength > 0 && idCommitmentsLength < 50);

        (, uint256 price) = w.priceCalculator().calculate(20);
        uint32 index;
        uint256[] memory commitmentsToErase = new uint256[](idCommitmentsLength);
        for (uint256 i = 1; i <= idCommitmentsLength; i++) {
            token.approve(address(w), price);
            w.register(i, 20);
            (,,,,,, index,,) = w.members(i);
            assertEq(index, w.commitmentIndex() - 1); // TODO: renname commitmentIndex to nextCommitmentIndex
            commitmentsToErase[i - 1] = i;
        }

        // time travel to the moment we can erase all expired memberships
        uint256 expirationDate = w.expirationDate(idCommitmentsLength);
        vm.warp(expirationDate);
        w.eraseMemberships(commitmentsToErase);

        // Verify that expired indices match what we expect
        for (uint32 i = 0; i < idCommitmentsLength; i++) {
            assertEq(i, w.availableExpiredIndices(i));
        }

        uint32 currCommitmentIndex = w.commitmentIndex();
        for (uint256 i = 1; i <= idCommitmentsLength; i++) {
            uint256 idCommitment = i + 10;
            uint256 expectedReusedIndexPos = idCommitmentsLength - i;
            uint32 expectedIndex = w.availableExpiredIndices(expectedReusedIndexPos);
            token.approve(address(w), price);
            w.register(idCommitment, 20);
            (,,,,,, index,,) = w.members(idCommitment);
            assertEq(expectedIndex, index);
            // Should have been removed from the list
            vm.expectRevert();
            w.availableExpiredIndices(expectedReusedIndexPos);
            // Should not have been affected
            assertEq(currCommitmentIndex, w.commitmentIndex());
        }

        // No indexes should be available for reuse
        vm.expectRevert();
        w.availableExpiredIndices(0);

        // Should use a new index since we got rid of all available indexes
        token.approve(address(w), price);
        w.register(100, 20);
        (,,,,,, index,,) = w.members(100);
        assertEq(index, currCommitmentIndex);
        assertEq(currCommitmentIndex + 1, w.commitmentIndex());
    }

    function test__RemoveExpiredMemberships(uint32 userMessageLimit) external {
        vm.pauseGasMetering();
        uint256 idCommitment = 2;
        (, uint256 price) = w.priceCalculator().calculate(userMessageLimit);
        vm.assume(
            userMessageLimit >= w.minRateLimitPerMembership() && userMessageLimit <= w.maxRateLimitPerMembership()
        );
        vm.assume(w.isValidUserMessageLimit(userMessageLimit));
        vm.resumeGasMetering();

        uint256 time = block.timestamp;
        for (uint256 i = 0; i < 5; i++) {
            token.approve(address(w), price);
            w.register(idCommitment + i, userMessageLimit);
            time += 100;
            vm.warp(time);
        }

        // Expiring the first 3
        uint256 expirationDate = w.expirationDate(idCommitment + 2);
        vm.warp(expirationDate);
        for (uint256 i = 0; i < 5; i++) {
            if (i <= 2) {
                assertTrue(w.isExpired(idCommitment + i));
            } else {
                assertFalse(w.isExpired(idCommitment + i));
            }
        }

        uint256[] memory commitmentsToErase = new uint256[](2);
        commitmentsToErase[0] = idCommitment + 1;
        commitmentsToErase[1] = idCommitment + 2;

        vm.expectEmit(true, false, false, false); // only check the first parameter of the event (the idCommitment)
        emit Membership.MemberExpired(commitmentsToErase[0], 0, 0);
        vm.expectEmit(true, false, false, false); // only check the first parameter of the event (the idCommitment)
        emit Membership.MemberExpired(commitmentsToErase[0], 0, 0);
        w.eraseMemberships(commitmentsToErase);

        address holder;

        (,,,,,,, holder,) = w.members(idCommitment + 1);
        assertEq(holder, address(0));

        (,,,,,,, holder,) = w.members(idCommitment + 2);
        assertEq(holder, address(0));

        // Verify list order is correct
        uint256 prev;
        uint256 next;
        (prev, next,,,,,,,) = w.members(idCommitment);
        assertEq(prev, 0);
        assertEq(next, idCommitment + 3);
        (prev, next,,,,,,,) = w.members(idCommitment + 3);
        assertEq(prev, idCommitment);
        assertEq(next, idCommitment + 4);
        (prev, next,,,,,,,) = w.members(idCommitment + 4);
        assertEq(prev, idCommitment + 3);
        assertEq(next, 0);
        assertEq(w.head(), idCommitment);
        assertEq(w.tail(), idCommitment + 4);

        // Attempting to call erase when some of the commitments can't be erased yet
        // idCommitment can be erased (in grace period), but idCommitment + 4 is still active
        (,,, uint256 gracePeriodStartDate,,,,,) = w.members(idCommitment + 4);
        vm.warp(gracePeriodStartDate - 1);
        commitmentsToErase[0] = idCommitment;
        commitmentsToErase[1] = idCommitment + 4;
        vm.expectRevert(abi.encodeWithSelector(CantEraseMembership.selector, idCommitment + 4));
        w.eraseMemberships(commitmentsToErase);
    }

    function test__RemoveAllExpiredMemberships(uint32 idCommitmentsLength) external {
        vm.pauseGasMetering();
        vm.assume(idCommitmentsLength > 1 && idCommitmentsLength <= 100);
        uint32 userMessageLimit = w.minRateLimitPerMembership();
        (, uint256 price) = w.priceCalculator().calculate(userMessageLimit);
        vm.resumeGasMetering();

        uint256 time = block.timestamp;
        for (uint256 i = 1; i <= idCommitmentsLength; i++) {
            token.approve(address(w), price);
            w.register(i, userMessageLimit);
            time += 100;
            vm.warp(time);
        }

        uint256 expirationDate = w.expirationDate(idCommitmentsLength);
        vm.warp(expirationDate);
        for (uint256 i = 1; i <= 5; i++) {
            assertTrue(w.isExpired(i));
        }

        uint256[] memory commitmentsToErase = new uint256[](idCommitmentsLength);
        for (uint256 i = 0; i < idCommitmentsLength; i++) {
            commitmentsToErase[i] = i + 1;
            vm.expectEmit(true, false, false, false); // only check the first parameter of the event (the idCommitment)
            emit Membership.MemberExpired(i + 1, 0, 0);
        }

        w.eraseMemberships(commitmentsToErase);

        // No memberships registered
        assertEq(w.head(), 0);
        assertEq(w.tail(), 0);

        for (uint256 i = 10; i <= idCommitmentsLength + 10; i++) {
            token.approve(address(w), price);
            w.register(i, userMessageLimit);
            assertEq(w.tail(), i);
        }

        // Verify list order is correct
        assertEq(w.head(), 10);
        assertEq(w.tail(), idCommitmentsLength + 10);
        uint256 prev;
        uint256 next;
        (prev, next,,,,,,,) = w.members(10);
        assertEq(prev, 0);
        assertEq(next, 11);
        (prev, next,,,,,,,) = w.members(idCommitmentsLength + 10);
        assertEq(prev, idCommitmentsLength + 9);
        assertEq(next, 0);
    }

    function test__WithdrawToken(uint32 userMessageLimit) external {
        vm.pauseGasMetering();
        uint256 idCommitment = 2;
        LinearPriceCalculator priceCalculator = LinearPriceCalculator(address(w.priceCalculator()));
        vm.prank(priceCalculator.owner());
        priceCalculator.setTokenAndPrice(address(token), 5 wei);
        (, uint256 price) = w.priceCalculator().calculate(userMessageLimit);
        token.mint(address(this), price);
        vm.assume(
            userMessageLimit >= w.minRateLimitPerMembership() && userMessageLimit <= w.maxRateLimitPerMembership()
        );
        vm.assume(w.isValidUserMessageLimit(userMessageLimit));
        vm.resumeGasMetering();

        token.approve(address(w), price);
        w.register(idCommitment, userMessageLimit);

        (,,, uint256 gracePeriodStartDate,,,,,) = w.members(idCommitment);

        vm.warp(gracePeriodStartDate);

        uint256[] memory commitmentsToErase = new uint256[](1);
        commitmentsToErase[0] = idCommitment;
        w.eraseMemberships(commitmentsToErase);

        uint256 availableBalance = w.balancesToWithdraw(address(this), address(token));

        assertEq(availableBalance, price);
        assertEq(token.balanceOf(address(w)), price);

        uint256 balanceBeforeWithdraw = token.balanceOf(address(this));

        w.withdraw(address(token));

        uint256 balanceAfterWithdraw = token.balanceOf(address(this));

        availableBalance = w.balancesToWithdraw(address(this), address(token));
        assertEq(availableBalance, 0);
        assertEq(token.balanceOf(address(w)), 0);
        assertEq(balanceBeforeWithdraw + price, balanceAfterWithdraw);
    }

    function test__InvalidRegistration__DuplicateIdCommitment() external {
        vm.pauseGasMetering();
        uint256 idCommitment = 2;
        uint32 userMessageLimit = w.minRateLimitPerMembership();
        (, uint256 price) = w.priceCalculator().calculate(userMessageLimit);
        vm.resumeGasMetering();

        token.approve(address(w), price);
        w.register(idCommitment, userMessageLimit);

        token.approve(address(w), price);
        vm.expectRevert(DuplicateIdCommitment.selector);
        w.register(idCommitment, userMessageLimit);
    }

    function test__InvalidRegistration__FullTree() external {
        vm.pauseGasMetering();
        uint32 userMessageLimit = 20;
        (, uint256 price) = w.priceCalculator().calculate(userMessageLimit);
        vm.resumeGasMetering();

        // we progress the tree to the last leaf

        /*| Name                | Type                                                | Slot | Offset | Bytes |
          |---------------------|-----------------------------------------------------|------|--------|-------|
          | commitmentIndex     | uint32                                              | 206  | 0      | 4     | */

        /*
        Pro tip: to easily find the storage slot of a variable, without having to calculate the storage layout
        based on the variable declaration, set the variable to an easily grepable value like 0xDEADBEEF, and then
        execute:
        ```
        for (uint256 i = 0; i <= 500; i++) {
            bytes32 slot0Value = vm.load(address(w), bytes32(i));
            console.log("%s", i);
            console.logBytes32(slot0Value);
        }
        revert();
        ```
        Search the value in the output (i.e. `DEADBEEF`) to determine the storage slot being used.
        If the storage layout changes, update the next line accordingly
        */

        // we set commitmentIndex to 4294967295 (1 << 20) = 0x00100000
        vm.store(address(w), bytes32(uint256(206)), 0x0000000000000000000000000000000000000000000000000000000000100000);
        token.approve(address(w), price);
        vm.expectRevert(FullTree.selector);
        w.register(1, userMessageLimit);
    }

    function test__InvalidPaginationQuery__StartIndexGTEndIndex() external {
        vm.expectRevert(abi.encodeWithSelector(InvalidPaginationQuery.selector, 1, 0));
        w.getCommitments(1, 0);
    }

    function test__InvalidPaginationQuery__EndIndexGTcommitmentIndex() external {
        vm.expectRevert(abi.encodeWithSelector(InvalidPaginationQuery.selector, 0, 2));
        w.getCommitments(0, 2);
    }

    function test__ValidPaginationQuery__OneElement() external {
        vm.pauseGasMetering();
        uint256 idCommitment = 1;
        uint32 userMessageLimit = w.minRateLimitPerMembership();
        (, uint256 price) = w.priceCalculator().calculate(userMessageLimit);
        vm.resumeGasMetering();

        token.approve(address(w), price);
        w.register(idCommitment, userMessageLimit);
        uint256[] memory commitments = w.getCommitments(0, 0);
        assertEq(commitments.length, 1);
        uint256 rateCommitment = PoseidonT3.hash([idCommitment, userMessageLimit]);
        assertEq(commitments[0], rateCommitment);
    }

    function test__ValidPaginationQuery(uint32 idCommitmentsLength) external {
        vm.pauseGasMetering();
        vm.assume(idCommitmentsLength > 0 && idCommitmentsLength <= 100);
        uint32 userMessageLimit = w.minRateLimitPerMembership();
        (, uint256 price) = w.priceCalculator().calculate(userMessageLimit);

        for (uint256 i = 0; i < idCommitmentsLength; i++) {
            token.approve(address(w), price);
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

    function test__Upgrade() external {
        address testImpl = address(new WakuRlnV2());
        bytes memory data = abi.encodeCall(WakuRlnV2.initialize, (address(0), 100, 1, 10, 10 minutes, 4 minutes));
        address proxy = address(new ERC1967Proxy(testImpl, data));

        address newImpl = address(new WakuRlnV2());
        UUPSUpgradeable(proxy).upgradeTo(newImpl);
        // ensure that the implementation is set correctly
        // ref:
        // solhint-disable-next-line
        // https://github.com/OpenZeppelin/openzeppelin-foundry-upgrades/blob/4cd15fc50b141c77d8cc9ff8efb44d00e841a299/src/internal/Core.sol#L289
        address fetchedImpl = address(
            uint160(
                uint256(vm.load(address(proxy), 0x360894a13ba1a3210667c828492db98dca3e2076cc3735a920a3ca505d382bbc))
            )
        );
        assertEq(fetchedImpl, newImpl);
    }
}
