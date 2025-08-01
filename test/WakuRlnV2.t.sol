// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.8.19 <0.9.0;

import { Test } from "forge-std/Test.sol";
import { DeployPriceCalculator, DeployWakuRlnV2, DeployProxy } from "../script/Deploy.s.sol";
import "../src/WakuRlnV2.sol"; // solhint-disable-line
import "../src/Membership.sol"; // solhint-disable-line
import { IPriceCalculator } from "../src/IPriceCalculator.sol";
import { LinearPriceCalculator } from "../src/LinearPriceCalculator.sol";
import { TestStableToken } from "./TestStableToken.sol";
import { PoseidonT3 } from "poseidon-solidity/PoseidonT3.sol";
import { UUPSUpgradeable } from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import { ERC1967Proxy } from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import { ECDSA } from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol"; // For signature manipulation
import "forge-std/console.sol";

contract WakuRlnV2Test is Test {
    WakuRlnV2 internal w;
    TestStableToken internal token;

    address internal deployer;

    uint256[] internal noIdCommitmentsToErase = new uint256[](0);

    function setUp() public virtual {
        token = new TestStableToken();
        IPriceCalculator priceCalculator = (new DeployPriceCalculator()).deploy(address(token));
        WakuRlnV2 wakuRlnV2 = (new DeployWakuRlnV2()).deploy();
        ERC1967Proxy proxy = (new DeployProxy()).deploy(address(priceCalculator), address(wakuRlnV2));

        w = WakuRlnV2(address(proxy));

        // TestStableTokening a large number of tokens to not have to worry about
        // Not having enough balance
        token.mint(address(this), 100_000_000 ether);
    }

    function test__ValidRegistration__kats() external {
        vm.pauseGasMetering();
        // Merkle tree leaves are calculated using 2 as rateLimit
        vm.prank(w.owner());
        w.setMinMembershipRateLimit(2);

        uint256 idCommitment = 2;
        uint32 membershipRateLimit = 2;
        (, uint256 price) = w.priceCalculator().calculate(membershipRateLimit);
        vm.resumeGasMetering();
        token.approve(address(w), price);
        w.register(idCommitment, membershipRateLimit, noIdCommitmentsToErase);
        vm.pauseGasMetering();
        assertEq(w.nextFreeIndex(), 1);
        assertEq(w.isInMembershipSet(idCommitment), true);
        (,,,, uint32 membershipRateLimit1, uint32 index, address holder,) = w.memberships(idCommitment);
        assertEq(membershipRateLimit1, membershipRateLimit);
        assertEq(holder, address(this));
        assertEq(index, 0);
        // kats from zerokit
        uint256 rateCommitment =
            4_699_387_056_273_519_054_140_667_386_511_343_037_709_699_938_246_587_880_795_929_666_834_307_503_001;
        assertEq(
            w.root(),
            13_801_897_483_540_040_307_162_267_952_866_411_686_127_372_014_953_358_983_481_592_640_000_001_877_295
        );
        uint32 fetchedMembershipRateLimit2;
        uint32 index2;
        uint256 rateCommitment2;
        (fetchedMembershipRateLimit2, index2, rateCommitment2) = w.getMembershipInfo(idCommitment);
        assertEq(fetchedMembershipRateLimit2, membershipRateLimit);
        assertEq(index2, 0);
        assertEq(rateCommitment2, rateCommitment);
        uint256[20] memory proof = w.getMerkleProof(0);
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

    function test__ValidRegistration(uint32 membershipRateLimit) external {
        vm.pauseGasMetering();
        uint256 idCommitment = 2;
        (, uint256 price) = w.priceCalculator().calculate(membershipRateLimit);
        uint256 minMembershipRateLimit = w.minMembershipRateLimit();
        uint256 maxMembershipRateLimit = w.maxMembershipRateLimit();
        vm.assume(minMembershipRateLimit <= membershipRateLimit && membershipRateLimit <= maxMembershipRateLimit);
        vm.assume(w.isValidMembershipRateLimit(membershipRateLimit));
        vm.resumeGasMetering();

        assertEq(w.isInMembershipSet(idCommitment), false);
        token.approve(address(w), price);
        w.register(idCommitment, membershipRateLimit, noIdCommitmentsToErase);
        uint256 rateCommitment = PoseidonT3.hash([idCommitment, membershipRateLimit]);

        (uint32 fetchedMembershipRateLimit, uint32 index, uint256 fetchedRateCommitment) =
            w.getMembershipInfo(idCommitment);
        assertEq(fetchedMembershipRateLimit, membershipRateLimit);
        assertEq(index, 0);
        assertEq(fetchedRateCommitment, rateCommitment);

        assertEq(token.balanceOf(address(w)), price);
        assertEq(w.currentTotalRateLimit(), membershipRateLimit);
    }

    function test__LinearPriceCalculation(uint32 membershipRateLimit) external view {
        IPriceCalculator priceCalculator = w.priceCalculator();
        uint256 pricePerMessagePerPeriod = LinearPriceCalculator(address(priceCalculator)).pricePerMessagePerEpoch();
        assertNotEq(pricePerMessagePerPeriod, 0);
        uint256 expectedPrice = uint256(membershipRateLimit) * pricePerMessagePerPeriod;
        (, uint256 price) = w.priceCalculator().calculate(membershipRateLimit);
        assertEq(price, expectedPrice);
    }

    function test__InvalidTokenAmount(uint256 idCommitment, uint32 membershipRateLimit) external {
        vm.pauseGasMetering();
        uint256 minMembershipRateLimit = w.minMembershipRateLimit();
        uint256 maxMembershipRateLimit = w.maxMembershipRateLimit();
        vm.assume(minMembershipRateLimit <= membershipRateLimit && membershipRateLimit <= maxMembershipRateLimit);
        vm.assume(w.isValidIdCommitment(idCommitment) && w.isValidMembershipRateLimit(membershipRateLimit));
        (, uint256 price) = w.priceCalculator().calculate(membershipRateLimit);
        vm.resumeGasMetering();

        token.approve(address(w), price - 1);
        vm.expectRevert(bytes("ERC20: insufficient allowance"));
        w.register(idCommitment, membershipRateLimit, noIdCommitmentsToErase);
    }

    function test__IdCommitmentToMetadata__DoesntExist() external view {
        uint256 idCommitment = 2;
        (uint32 membershipRateLimit, uint32 index, uint256 rateCommitment) = w.getMembershipInfo(idCommitment);
        assertEq(membershipRateLimit, 0);
        assertEq(index, 0);
        assertEq(rateCommitment, 0);
    }

    function test__InvalidRegistration__InvalidIdCommitment__Zero() external {
        vm.pauseGasMetering();
        uint256 idCommitment = 0;
        uint32 membershipRateLimit = 2;
        (, uint256 price) = w.priceCalculator().calculate(membershipRateLimit);
        vm.resumeGasMetering();

        token.approve(address(w), price);
        vm.expectRevert(abi.encodeWithSelector(InvalidIdCommitment.selector, 0));
        w.register(idCommitment, membershipRateLimit, noIdCommitmentsToErase);
    }

    function test__InvalidRegistration__InvalidIdCommitment__LargerThanField() external {
        vm.pauseGasMetering();
        uint32 membershipRateLimit = 20;
        (, uint256 price) = w.priceCalculator().calculate(membershipRateLimit);
        vm.resumeGasMetering();

        uint256 idCommitment = w.Q() + 1;
        token.approve(address(w), price);
        vm.expectRevert(abi.encodeWithSelector(InvalidIdCommitment.selector, idCommitment));
        w.register(idCommitment, membershipRateLimit, noIdCommitmentsToErase);
    }

    function test__InvalidRegistration__InvalidMembershipRateLimit__MinMax() external {
        uint256 idCommitment = 2;

        uint32 invalidMin = w.minMembershipRateLimit() - 1;
        uint32 invalidMax = w.maxMembershipRateLimit() + 1;

        vm.expectRevert(abi.encodeWithSelector(InvalidMembershipRateLimit.selector));
        w.register(idCommitment, invalidMin, noIdCommitmentsToErase);

        vm.expectRevert(abi.encodeWithSelector(InvalidMembershipRateLimit.selector));
        w.register(idCommitment, invalidMax, noIdCommitmentsToErase);
    }

    function test__ValidRegistrationExtend(uint32 membershipRateLimit) external {
        vm.pauseGasMetering();
        uint256 idCommitment = 2;
        (, uint256 price) = w.priceCalculator().calculate(membershipRateLimit);
        vm.assume(
            w.minMembershipRateLimit() <= membershipRateLimit && membershipRateLimit <= w.maxMembershipRateLimit()
        );
        vm.assume(w.isValidMembershipRateLimit(membershipRateLimit));
        vm.resumeGasMetering();

        token.approve(address(w), price);
        w.register(idCommitment, membershipRateLimit, noIdCommitmentsToErase);
        (,, uint256 gracePeriodStartTimestamp,,,,,) = w.memberships(idCommitment);

        assertFalse(w.isInGracePeriod(idCommitment));
        assertFalse(w.isExpired(idCommitment));

        vm.warp(gracePeriodStartTimestamp);

        assertTrue(w.isInGracePeriod(idCommitment));
        assertFalse(w.isExpired(idCommitment));

        uint256[] memory commitmentsToExtend = new uint256[](1);
        commitmentsToExtend[0] = idCommitment;

        // Attempt to extend the membership (but it is not owned by us)
        address randomAddress = vm.addr(block.timestamp);
        vm.prank(randomAddress);
        vm.expectRevert(abi.encodeWithSelector(NonHolderCannotExtend.selector, commitmentsToExtend[0]));
        w.extendMemberships(commitmentsToExtend);

        // Attempt to extend the membership (but now we are the owner)
        vm.expectEmit(true, false, false, false); // only check the first parameter of the event (the idCommitment)
        emit MembershipUpgradeable.MembershipExtended(idCommitment, 0, 0, 0);

        (, uint256 oldActiveDuration, uint256 oldGracePeriodStartTimestamp, uint32 oldGracePeriodDuration,,,,) =
            w.memberships(idCommitment);
        w.extendMemberships(commitmentsToExtend);
        (, uint256 newActiveDuration, uint256 newGracePeriodStartTimestamp, uint32 newGracePeriodDuration,,,,) =
            w.memberships(idCommitment);

        assertEq(oldActiveDuration, newActiveDuration);
        assertEq(oldGracePeriodDuration, newGracePeriodDuration);
        assertEq(
            oldGracePeriodStartTimestamp + oldGracePeriodDuration + newActiveDuration, newGracePeriodStartTimestamp
        );
        assertFalse(w.isInGracePeriod(idCommitment));
        assertFalse(w.isExpired(idCommitment));

        // Attempt to extend a non grace period membership
        token.approve(address(w), price);
        w.register(idCommitment + 1, membershipRateLimit, noIdCommitmentsToErase);
        commitmentsToExtend[0] = idCommitment + 1;
        vm.expectRevert(abi.encodeWithSelector(CannotExtendNonGracePeriodMembership.selector, commitmentsToExtend[0]));
        w.extendMemberships(commitmentsToExtend);
    }

    function test__ValidRegistrationNoGracePeriod(uint32 membershipRateLimit) external {
        vm.pauseGasMetering();
        uint256 idCommitment = 2;
        (, uint256 price) = w.priceCalculator().calculate(membershipRateLimit);
        vm.assume(
            w.minMembershipRateLimit() <= membershipRateLimit && membershipRateLimit <= w.maxMembershipRateLimit()
        );
        vm.assume(w.isValidMembershipRateLimit(membershipRateLimit));

        vm.startPrank(w.owner());
        w.setGracePeriodDuration(0);
        vm.stopPrank();

        vm.resumeGasMetering();

        token.approve(address(w), price);
        w.register(idCommitment, membershipRateLimit, noIdCommitmentsToErase);

        (,, uint256 gracePeriodStartTimestamp, uint32 gracePeriodDuration,,,,) = w.memberships(idCommitment);

        assertEq(gracePeriodDuration, 0);

        assertFalse(w.isInGracePeriod(idCommitment));
        assertFalse(w.isExpired(idCommitment));

        uint256 expectedExpirationTimestamp = gracePeriodStartTimestamp + uint256(gracePeriodDuration);
        uint256 membershipExpirationTimestamp = w.membershipExpirationTimestamp(idCommitment);

        assertEq(expectedExpirationTimestamp, membershipExpirationTimestamp);

        vm.warp(membershipExpirationTimestamp);

        assertFalse(w.isInGracePeriod(idCommitment));
        assertTrue(w.isExpired(idCommitment));
    }

    function test__ValidRegistrationExtendSingleMembership(uint32 membershipRateLimit) external {
        vm.pauseGasMetering();
        uint256 idCommitment = 2;
        (, uint256 price) = w.priceCalculator().calculate(membershipRateLimit);
        vm.assume(
            w.minMembershipRateLimit() <= membershipRateLimit && membershipRateLimit <= w.maxMembershipRateLimit()
        );
        vm.assume(w.isValidMembershipRateLimit(membershipRateLimit));
        vm.resumeGasMetering();

        token.approve(address(w), price);
        w.register(idCommitment, membershipRateLimit, noIdCommitmentsToErase);
        uint256 ogExpirationTimestamp = w.membershipExpirationTimestamp(idCommitment);
        (,, uint256 gracePeriodStartTimestamp,,,,,) = w.memberships(idCommitment);

        vm.warp(gracePeriodStartTimestamp);

        uint256[] memory commitmentsToExtend = new uint256[](1);
        commitmentsToExtend[0] = idCommitment;

        // Extend the membership
        vm.expectEmit(true, false, false, false); // only check the first parameter of the event (the idCommitment)
        emit MembershipUpgradeable.MembershipExtended(idCommitment, 0, 0, 0);
        w.extendMemberships(commitmentsToExtend);

        (,, uint256 newGracePeriodStartTimestamp, uint32 newGracePeriodDuration,,,,) = w.memberships(idCommitment);
        uint256 expectedExpirationTimestamp = newGracePeriodStartTimestamp + uint256(newGracePeriodDuration);
        uint256 membershipExpirationTimestamp = w.membershipExpirationTimestamp(idCommitment);
        assertEq(expectedExpirationTimestamp, membershipExpirationTimestamp);
        assertTrue(expectedExpirationTimestamp > ogExpirationTimestamp);
    }

    function test__ValidRegistrationExpiry(uint32 membershipRateLimit) external {
        vm.pauseGasMetering();
        uint256 idCommitment = 2;
        (, uint256 price) = w.priceCalculator().calculate(membershipRateLimit);
        vm.assume(
            w.minMembershipRateLimit() <= membershipRateLimit && membershipRateLimit <= w.maxMembershipRateLimit()
        );
        vm.assume(w.isValidMembershipRateLimit(membershipRateLimit));
        vm.resumeGasMetering();

        token.approve(address(w), price);
        w.register(idCommitment, membershipRateLimit, noIdCommitmentsToErase);

        (,, uint256 fetchedgracePeriodStartTimestamp, uint32 fetchedGracePeriod,,,,) = w.memberships(idCommitment);

        uint256 expectedExpirationTimestamp = fetchedgracePeriodStartTimestamp + uint256(fetchedGracePeriod);
        uint256 membershipExpirationTimestamp = w.membershipExpirationTimestamp(idCommitment);

        assertEq(expectedExpirationTimestamp, membershipExpirationTimestamp);

        vm.warp(membershipExpirationTimestamp);

        assertFalse(w.isInGracePeriod(idCommitment));
        assertTrue(w.isExpired(idCommitment));
    }

    function test__ValidRegistrationWithEraseList() external {
        vm.pauseGasMetering();
        vm.startPrank(w.owner());
        w.setMinMembershipRateLimit(20);
        w.setMaxMembershipRateLimit(100);
        w.setMaxTotalRateLimit(100);
        vm.stopPrank();
        vm.resumeGasMetering();

        (, uint256 priceA) = w.priceCalculator().calculate(20);

        for (uint256 i = 1; i <= 5; i++) {
            token.approve(address(w), priceA);
            w.register(i, 20, noIdCommitmentsToErase);
            // Make sure they're expired
            vm.warp(w.membershipExpirationTimestamp(i));
        }

        // Time travel to a point in which the last membership is active
        (,, uint256 gracePeriodStartTimestamp,,,,,) = w.memberships(5);
        vm.warp(gracePeriodStartTimestamp - 1);

        // Ensure that this is the case
        assertTrue(w.isExpired(4));
        assertFalse(w.isExpired(5));
        assertFalse(w.isInGracePeriod(5));

        (, uint256 priceB) = w.priceCalculator().calculate(60);
        token.approve(address(w), priceB);

        // Should fail. There's not enough free rate limit
        vm.expectRevert(abi.encodeWithSelector(CannotExceedMaxTotalRateLimit.selector));
        w.register(6, 60, noIdCommitmentsToErase);

        // Attempt to erase 3 memberships including one that can't be erased (the last one)
        uint256[] memory commitmentsToErase = new uint256[](3);
        commitmentsToErase[0] = 1;
        commitmentsToErase[1] = 2;
        commitmentsToErase[2] = 5; // This one is still active
        token.approve(address(w), priceB);
        vm.expectRevert(abi.encodeWithSelector(CannotEraseActiveMembership.selector, 5));
        w.register(6, 60, commitmentsToErase);

        // Attempt to erase 3 memberships that can be erased
        commitmentsToErase[2] = 4;
        vm.expectEmit(true, false, false, false);
        emit MembershipUpgradeable.MembershipExpired(1, 0, 0);
        vm.expectEmit(true, false, false, false);
        emit MembershipUpgradeable.MembershipExpired(2, 0, 0);
        vm.expectEmit(true, false, false, false);
        emit MembershipUpgradeable.MembershipExpired(4, 0, 0);
        w.register(6, 60, commitmentsToErase);

        // Ensure that the chosen memberships were erased and others unaffected
        address holder;
        (,,,,,, holder,) = w.memberships(1);
        assertEq(holder, address(0));
        (,,,,,, holder,) = w.memberships(2);
        assertEq(holder, address(0));
        (,,,,,, holder,) = w.memberships(3);
        assertEq(holder, address(this));
        (,,,,,, holder,) = w.memberships(4);
        assertEq(holder, address(0));
        (,,,,,, holder,) = w.memberships(5);
        assertEq(holder, address(this));
        (,,,,,, holder,) = w.memberships(6);
        assertEq(holder, address(this));

        // The balance available for withdrawal should match the amount of the expired membership
        uint256 availableBalance = w.depositsToWithdraw(address(this), address(token));
        assertEq(availableBalance, priceA * 3);
    }

    function test__RegistrationWhenMaxRateLimitIsReached() external {
        vm.pauseGasMetering();
        vm.startPrank(w.owner());
        w.setMinMembershipRateLimit(1);
        w.setMaxMembershipRateLimit(5);
        w.setMaxTotalRateLimit(5);
        vm.stopPrank();
        vm.resumeGasMetering();

        bool isValid = w.isValidMembershipRateLimit(6);
        assertFalse(isValid);

        // Exceeds the max rate limit per membership
        uint32 membershipRateLimit = 10;
        (, uint256 price) = w.priceCalculator().calculate(membershipRateLimit);
        token.approve(address(w), price);
        vm.expectRevert(abi.encodeWithSelector(InvalidMembershipRateLimit.selector));
        w.register(1, membershipRateLimit, noIdCommitmentsToErase);

        // Should register succesfully
        membershipRateLimit = 4;
        (, price) = w.priceCalculator().calculate(membershipRateLimit);
        token.approve(address(w), price);
        w.register(2, membershipRateLimit, noIdCommitmentsToErase);

        // Exceeds the rate limit
        membershipRateLimit = 2;
        (, price) = w.priceCalculator().calculate(membershipRateLimit);
        token.approve(address(w), price);
        vm.expectRevert(abi.encodeWithSelector(CannotExceedMaxTotalRateLimit.selector));
        w.register(3, membershipRateLimit, noIdCommitmentsToErase);

        // Should register succesfully
        membershipRateLimit = 1;
        (, price) = w.priceCalculator().calculate(membershipRateLimit);
        token.approve(address(w), price);
        w.register(3, membershipRateLimit, noIdCommitmentsToErase);

        // We ran out of rate limit again
        membershipRateLimit = 1;
        (, price) = w.priceCalculator().calculate(membershipRateLimit);
        token.approve(address(w), price);
        vm.expectRevert(abi.encodeWithSelector(CannotExceedMaxTotalRateLimit.selector));
        w.register(4, membershipRateLimit, noIdCommitmentsToErase);
    }

    function test__indexReuse_eraseMemberships(uint32 idCommitmentsLength) external {
        vm.assume(0 < idCommitmentsLength && idCommitmentsLength < 50);

        (, uint256 price) = w.priceCalculator().calculate(20);
        uint32 index;
        uint256[] memory commitmentsToErase = new uint256[](idCommitmentsLength);
        uint256 time = block.timestamp;
        for (uint256 i = 1; i <= idCommitmentsLength; i++) {
            token.approve(address(w), price);
            w.register(i, 20, noIdCommitmentsToErase);
            (,,,,, index,,) = w.memberships(i);
            assertEq(index, w.nextFreeIndex() - 1);
            commitmentsToErase[i - 1] = i;
            time += 100;
            vm.warp(time);
        }

        // None of the commitments can be deleted because they're still active
        uint256[] memory singleCommitmentToErase = new uint256[](1);
        for (uint256 i = 1; i <= idCommitmentsLength; i++) {
            singleCommitmentToErase[0] = i;
            vm.expectRevert(abi.encodeWithSelector(CannotEraseActiveMembership.selector, i));
            w.eraseMemberships(singleCommitmentToErase);
        }

        // Fastfwd to commitment grace period, and try to erase it without being the owner
        (,, uint256 gracePeriodStartTimestamp,,,,,) = w.memberships(1);
        vm.warp(gracePeriodStartTimestamp);
        assertTrue(w.isInGracePeriod(1));
        singleCommitmentToErase[0] = 1;
        address randomAddress = vm.addr(block.timestamp);
        vm.prank(randomAddress);
        vm.expectRevert(abi.encodeWithSelector(NonHolderCannotEraseGracePeriodMembership.selector, 1));
        w.eraseMemberships(singleCommitmentToErase);

        // time travel to the moment we can erase all expired memberships
        uint256 membershipExpirationTimestamp = w.membershipExpirationTimestamp(idCommitmentsLength);
        vm.warp(membershipExpirationTimestamp);
        w.eraseMemberships(commitmentsToErase);

        // Verify that expired indices match what we expect
        for (uint32 i = 0; i < idCommitmentsLength; i++) {
            assertEq(i, w.indicesOfLazilyErasedMemberships(i));
        }

        uint32 expectedNextFreeIndex = w.nextFreeIndex();
        for (uint256 i = 1; i <= idCommitmentsLength; i++) {
            uint256 idCommitment = i + 10;
            uint256 expectedindexReusedPos = idCommitmentsLength - i;
            uint32 expectedReusedIndex = w.indicesOfLazilyErasedMemberships(expectedindexReusedPos);
            token.approve(address(w), price);
            w.register(idCommitment, 20, noIdCommitmentsToErase);
            (,,,,, index,,) = w.memberships(idCommitment);
            assertEq(expectedReusedIndex, index);
            // Should have been removed from the list
            vm.expectRevert();
            w.indicesOfLazilyErasedMemberships(expectedindexReusedPos);
            // Should not have been affected
            assertEq(expectedNextFreeIndex, w.nextFreeIndex());
        }

        // No indices should be available for reuse
        vm.expectRevert();
        w.indicesOfLazilyErasedMemberships(0);

        // Should use a new index since we got rid of all reusable indexes
        token.approve(address(w), price);
        w.register(100, 20, noIdCommitmentsToErase);
        (,,,,, index,,) = w.memberships(100);
        assertEq(index, expectedNextFreeIndex);
        assertEq(expectedNextFreeIndex + 1, w.nextFreeIndex());
    }

    function test__RemoveExpiredMemberships(uint32 membershipRateLimit) external {
        vm.pauseGasMetering();
        uint256 idCommitment = 2;
        (, uint256 price) = w.priceCalculator().calculate(membershipRateLimit);
        vm.assume(
            w.minMembershipRateLimit() <= membershipRateLimit && membershipRateLimit <= w.maxMembershipRateLimit()
        );
        vm.assume(w.isValidMembershipRateLimit(membershipRateLimit));
        vm.resumeGasMetering();

        uint256 time = block.timestamp;
        for (uint256 i = 0; i < 5; i++) {
            token.approve(address(w), price);
            w.register(idCommitment + i, membershipRateLimit, noIdCommitmentsToErase);
            time += 100;
            vm.warp(time);
        }

        // Expiring the first 3 memberships
        uint256 membershipExpirationTimestamp = w.membershipExpirationTimestamp(idCommitment + 2);
        vm.warp(membershipExpirationTimestamp);
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
        emit MembershipUpgradeable.MembershipExpired(commitmentsToErase[0], 0, 0);
        vm.expectEmit(true, false, false, false); // only check the first parameter of the event (the idCommitment)
        emit MembershipUpgradeable.MembershipExpired(commitmentsToErase[0], 0, 0);
        w.eraseMemberships(commitmentsToErase);

        address holder;

        (,,,,,, holder,) = w.memberships(idCommitment + 1);
        assertEq(holder, address(0));

        (,,,,,, holder,) = w.memberships(idCommitment + 2);
        assertEq(holder, address(0));

        // Attempting to call erase when some of the commitments can't be erased yet
        // idCommitment can be erased (in grace period), but idCommitment + 4 is still active
        (,, uint256 gracePeriodStartTimestamp,,,,,) = w.memberships(idCommitment + 4);
        vm.warp(gracePeriodStartTimestamp - 1);
        commitmentsToErase[0] = idCommitment;
        commitmentsToErase[1] = idCommitment + 4;
        vm.expectRevert(abi.encodeWithSelector(CannotEraseActiveMembership.selector, idCommitment + 4));
        w.eraseMemberships(commitmentsToErase);
    }

    function test__RemoveAllExpiredMemberships(uint32 idCommitmentsLength) external {
        vm.pauseGasMetering();
        vm.assume(1 < idCommitmentsLength && idCommitmentsLength <= 100);
        uint32 membershipRateLimit = w.minMembershipRateLimit();
        (, uint256 price) = w.priceCalculator().calculate(membershipRateLimit);
        vm.resumeGasMetering();

        uint256 time = block.timestamp;
        for (uint256 i = 1; i <= idCommitmentsLength; i++) {
            token.approve(address(w), price);
            w.register(i, membershipRateLimit, noIdCommitmentsToErase);
            time += 100;
            vm.warp(time);
        }

        uint256 membershipExpirationTimestamp = w.membershipExpirationTimestamp(idCommitmentsLength);
        vm.warp(membershipExpirationTimestamp);
        for (uint256 i = 1; i <= 5; i++) {
            assertTrue(w.isExpired(i));
        }

        uint256[] memory commitmentsToErase = new uint256[](idCommitmentsLength);
        for (uint256 i = 0; i < idCommitmentsLength; i++) {
            commitmentsToErase[i] = i + 1;
            vm.expectEmit(true, false, false, false); // only check the first parameter of the event (the idCommitment)
            emit MembershipUpgradeable.MembershipExpired(i + 1, 0, 0);
        }

        w.eraseMemberships(commitmentsToErase);

        // Erased memberships are gone!
        for (uint256 i = 0; i < commitmentsToErase.length; i++) {
            (,,,, uint32 fetchedMembershipRateLimit,,,) = w.memberships(commitmentsToErase[i]);
            assertEq(fetchedMembershipRateLimit, 0);
        }
    }

    function test__WithdrawToken(uint32 membershipRateLimit) external {
        vm.pauseGasMetering();
        uint256 idCommitment = 2;
        LinearPriceCalculator priceCalculator = LinearPriceCalculator(address(w.priceCalculator()));
        vm.prank(priceCalculator.owner());
        priceCalculator.setTokenAndPrice(address(token), 5 wei);
        (, uint256 price) = w.priceCalculator().calculate(membershipRateLimit);
        token.mint(address(this), price);
        vm.assume(
            w.minMembershipRateLimit() <= membershipRateLimit && membershipRateLimit <= w.maxMembershipRateLimit()
        );
        vm.assume(w.isValidMembershipRateLimit(membershipRateLimit));
        vm.resumeGasMetering();

        token.approve(address(w), price);
        w.register(idCommitment, membershipRateLimit, noIdCommitmentsToErase);

        (,, uint256 gracePeriodStartTimestamp,,,,,) = w.memberships(idCommitment);

        vm.warp(gracePeriodStartTimestamp);

        uint256[] memory commitmentsToErase = new uint256[](1);
        commitmentsToErase[0] = idCommitment;
        w.eraseMemberships(commitmentsToErase);

        uint256 availableBalance = w.depositsToWithdraw(address(this), address(token));

        assertEq(availableBalance, price);
        assertEq(token.balanceOf(address(w)), price);

        uint256 balanceBeforeWithdraw = token.balanceOf(address(this));

        w.withdraw(address(token));

        uint256 balanceAfterWithdraw = token.balanceOf(address(this));

        availableBalance = w.depositsToWithdraw(address(this), address(token));
        assertEq(availableBalance, 0);
        assertEq(token.balanceOf(address(w)), 0);
        assertEq(balanceBeforeWithdraw + price, balanceAfterWithdraw);
    }

    function test__InvalidRegistration__DuplicateIdCommitment() external {
        vm.pauseGasMetering();
        uint256 idCommitment = 2;
        uint32 membershipRateLimit = w.minMembershipRateLimit();
        (, uint256 price) = w.priceCalculator().calculate(membershipRateLimit);
        vm.resumeGasMetering();

        token.approve(address(w), price);
        w.register(idCommitment, membershipRateLimit, noIdCommitmentsToErase);

        token.approve(address(w), price);
        vm.expectRevert(bytes("Duplicate idCommitment: membership already exists"));
        w.register(idCommitment, membershipRateLimit, noIdCommitmentsToErase);
    }

    function test__InvalidRegistration__FullTree() external {
        vm.pauseGasMetering();
        uint32 membershipRateLimit = 20;
        (, uint256 price) = w.priceCalculator().calculate(membershipRateLimit);
        vm.resumeGasMetering();

        // we progress the tree to the last leaf

        /*| Name                | Type                                                | Slot | Offset | Bytes |
          |---------------------|-----------------------------------------------------|------|--------|-------|
          | nextFreeIndex       | uint32                                              | 206  | 0      | 4     | */
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

        // we set nextFreeIndex to 4294967295 (1 << 20) = 0x00100000
        vm.store(address(w), bytes32(uint256(206)), 0x0000000000000000000000000000000000000000000000000000000000100000);
        token.approve(address(w), price);
        vm.expectRevert(bytes("Membership set is full"));
        w.register(1, membershipRateLimit, noIdCommitmentsToErase);
    }

    function test__InvalidPaginationQuery__StartIndexGTEndIndex() external {
        vm.expectRevert(abi.encodeWithSelector(InvalidPaginationQuery.selector, 1, 0));
        w.getRateCommitmentsInRangeBoundsInclusive(1, 0);
    }

    function test__InvalidPaginationQuery__EndIndexGTNextFreeIndex() external {
        vm.expectRevert(abi.encodeWithSelector(InvalidPaginationQuery.selector, 0, 2));
        w.getRateCommitmentsInRangeBoundsInclusive(0, 2);
    }

    function test__ValidPaginationQuery__OneElement() external {
        vm.pauseGasMetering();
        uint256 idCommitment = 1;
        uint32 membershipRateLimit = w.minMembershipRateLimit();
        (, uint256 price) = w.priceCalculator().calculate(membershipRateLimit);
        vm.resumeGasMetering();

        token.approve(address(w), price);
        w.register(idCommitment, membershipRateLimit, noIdCommitmentsToErase);
        uint256[] memory commitments = w.getRateCommitmentsInRangeBoundsInclusive(0, 0);
        assertEq(commitments.length, 1);
        uint256 rateCommitment = PoseidonT3.hash([idCommitment, membershipRateLimit]);
        assertEq(commitments[0], rateCommitment);
    }

    function test__ValidPaginationQuery(uint32 idCommitmentsLength) external {
        vm.pauseGasMetering();
        vm.assume(0 < idCommitmentsLength && idCommitmentsLength <= 100);
        uint32 membershipRateLimit = w.minMembershipRateLimit();
        (, uint256 price) = w.priceCalculator().calculate(membershipRateLimit);

        for (uint256 i = 0; i <= idCommitmentsLength; i++) {
            token.approve(address(w), price);
            w.register(i + 1, membershipRateLimit, noIdCommitmentsToErase);
        }
        vm.resumeGasMetering();

        uint256[] memory rateCommitments = w.getRateCommitmentsInRangeBoundsInclusive(0, idCommitmentsLength - 1);
        assertEq(rateCommitments.length, idCommitmentsLength);
        for (uint256 i = 0; i < idCommitmentsLength; i++) {
            uint256 rateCommitment = PoseidonT3.hash([i + 1, membershipRateLimit]);
            assertEq(rateCommitments[i], rateCommitment);
        }
    }

    function test__TestStableToken__OnlyOwnerCanMint() external {
        address nonOwner = vm.addr(1);
        uint256 mintAmount = 1000 ether;

        vm.prank(nonOwner);
        vm.expectRevert("Ownable: caller is not the owner");
        token.mint(nonOwner, mintAmount);
    }

    function test__TestStableToken__OwnerMintsTransfersAndRegisters() external {
        address recipient = vm.addr(2);
        uint256 idCommitment = 3;
        uint32 membershipRateLimit = w.minMembershipRateLimit();
        (, uint256 price) = w.priceCalculator().calculate(membershipRateLimit);

        // Owner (test contract) mints tokens to recipient
        token.mint(recipient, price);
        assertEq(token.balanceOf(recipient), price);

        // Recipient uses tokens to register
        vm.startPrank(recipient);
        token.approve(address(w), price);
        w.register(idCommitment, membershipRateLimit, noIdCommitmentsToErase);
        vm.stopPrank();

        // Verify registration succeeded
        assertTrue(w.isInMembershipSet(idCommitment));
        (,,,, uint32 fetchedMembershipRateLimit, uint32 index, address holder,) = w.memberships(idCommitment);
        assertEq(fetchedMembershipRateLimit, membershipRateLimit);
        assertEq(holder, recipient);
        assertEq(index, 0);
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
