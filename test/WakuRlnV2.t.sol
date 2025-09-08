// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.8.19 <0.9.0;

import "../src/Membership.sol";
import "../src/WakuRlnV2.sol";
import "forge-std/console.sol"; // solhint-disable-line
import "forge-std/Vm.sol";
import { DeployPriceCalculator, DeployWakuRlnV2, DeployProxy } from "../script/Deploy.s.sol"; // solhint-disable-line
import { DeployTokenWithProxy } from "../script/DeployTokenWithProxy.s.sol";
import { ECDSA } from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import { ERC1967Proxy } from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import { IPriceCalculator } from "../src/IPriceCalculator.sol";
import { LinearPriceCalculator } from "../src/LinearPriceCalculator.sol";
import { PoseidonT3 } from "poseidon-solidity/PoseidonT3.sol";
import { Test } from "forge-std/Test.sol"; // For signature manipulation
import { TestStableToken } from "./TestStableToken.sol";
import { UUPSUpgradeable } from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";

contract MaliciousToken is TestStableToken {
    address public target;
    bool public failTransferEnabled;

    function initialize(address _target, bool _failTransferEnabled) public initializer {
        super.initialize();
        target = _target;
        failTransferEnabled = _failTransferEnabled;
    }

    function setFailTransferEnabled(bool _enabled) external onlyOwner {
        failTransferEnabled = _enabled;
    }

    function transferFrom(address from, address to, uint256 amount) public override returns (bool) {
        if (failTransferEnabled) {
            revert("Malicious transfer failure");
        }
        return super.transferFrom(from, to, amount);
    }

    function transfer(address to, uint256 amount) public override returns (bool) {
        if (failTransferEnabled) {
            revert("Malicious transfer failure");
        }
        return super.transfer(to, amount);
    }

    function failTransfer() external pure {
        revert("Malicious transfer failure");
    }
}

contract MockPriceCalculator is IPriceCalculator {
    address public token;
    uint256 public price;

    constructor(address _token, uint256 _price) {
        token = _token;
        price = _price;
    }

    function calculate(uint32 _rateLimit) external view returns (address, uint256) {
        return (token, uint256(_rateLimit) * price);
    }
}

contract WakuRlnV2Test is Test {
    WakuRlnV2 internal w;
    TestStableToken internal token;
    DeployTokenWithProxy internal tokenDeployer;

    address internal deployer;

    uint256[] internal noIdCommitmentsToErase = new uint256[](0);

    function setUp() public virtual {
        // Deploy TestStableToken through proxy using deployment script
        tokenDeployer = new DeployTokenWithProxy();
        ERC1967Proxy tokenProxy = tokenDeployer.deploy();
        token = TestStableToken(address(tokenProxy));

        IPriceCalculator priceCalculator = (new DeployPriceCalculator()).deploy(address(token));
        WakuRlnV2 wakuRlnV2 = (new DeployWakuRlnV2()).deploy();
        ERC1967Proxy proxy = (new DeployProxy()).deploy(address(priceCalculator), address(wakuRlnV2));

        w = WakuRlnV2(address(proxy));

        // Log owner for debugging
        console.log("WakuRlnV2 owner: ", w.owner());

        // Transfer ownership to address(this)
        vm.prank(w.owner());
        try w.transferOwnership(address(this)) {
            console.log("Ownership transferred to: ", w.owner());
        } catch {
            console.log("Failed to transfer ownership");
        }

        // Minting a large number of tokens to not have to worry about
        // Not having enough balance
        vm.prank(address(tokenDeployer));
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
        vm.prank(address(tokenDeployer));
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

    function test__ErasingNonExistentMembership() external {
        uint256[] memory ids = new uint256[](1);
        ids[0] = 999; // Non-existent
        assertFalse(w.isInMembershipSet(999), "ID should not exist");
        uint256 initialRoot = w.root();
        uint256 initialNextFreeIndex = w.nextFreeIndex();

        vm.expectRevert(abi.encodeWithSelector(MembershipDoesNotExist.selector, 999));
        w.eraseMemberships(ids);

        assertEq(w.root(), initialRoot, "Merkle root should not change");
        assertEq(w.nextFreeIndex(), initialNextFreeIndex, "Next free index should not change");
    }

    function test__GracePeriodExtensionEdgeCases() external {
        uint256 idCommitment = 1;
        uint32 rateLimit = w.minMembershipRateLimit();
        (, uint256 price) = w.priceCalculator().calculate(rateLimit);

        token.approve(address(w), price);
        w.register(idCommitment, rateLimit, noIdCommitmentsToErase);

        // Destructure the memberships mapping tuple, skipping unused fields
        (
            , // depositAmount
            uint32 activeDuration,
            uint256 gracePeriodStart,
            uint32 gracePeriodDuration,
            uint32 rateLimitFetched,
            uint32 indexFetched,
            address holderFetched,
            // tokenFetched
        ) = w.memberships(idCommitment);
        assertEq(rateLimitFetched, rateLimit);
        assertEq(holderFetched, address(this));
        assertEq(indexFetched, 0);

        // Before grace period (still active)
        vm.warp(gracePeriodStart - 1);
        uint256[] memory ids = new uint256[](1);
        ids[0] = idCommitment;
        vm.expectRevert(abi.encodeWithSelector(CannotExtendNonGracePeriodMembership.selector, idCommitment));
        w.extendMemberships(ids);

        // At start of grace period
        vm.warp(gracePeriodStart);
        assertTrue(w.isInGracePeriod(idCommitment));
        vm.expectEmit(true, true, true, true);
        emit MembershipUpgradeable.MembershipExtended(
            idCommitment, rateLimit, 0, gracePeriodStart + gracePeriodDuration + activeDuration
        );
        w.extendMemberships(ids);

        // Verify updated grace period start
        (,, uint256 newGracePeriodStart,,,,,) = w.memberships(idCommitment);
        assertEq(newGracePeriodStart, gracePeriodStart + gracePeriodDuration + activeDuration);

        // Non-holder attempt
        vm.warp(newGracePeriodStart);
        vm.prank(vm.addr(1));
        vm.expectRevert(abi.encodeWithSelector(NonHolderCannotExtend.selector, idCommitment));
        w.extendMemberships(ids);

        // After grace period (expired)
        vm.warp(newGracePeriodStart + gracePeriodDuration + 1);
        vm.expectRevert(abi.encodeWithSelector(CannotExtendNonGracePeriodMembership.selector, idCommitment));
        w.extendMemberships(ids);
    }

    function test__MaxTotalRateLimitEdgeCases() external {
        vm.startPrank(w.owner());
        w.setMinMembershipRateLimit(1); // Ensure minMembershipRateLimit <= 10
        w.setMaxMembershipRateLimit(10); // Ensure maxMembershipRateLimit <= 100
        w.setMaxTotalRateLimit(100);
        vm.stopPrank();

        uint32 minRateLimit = w.minMembershipRateLimit();
        (, uint256 price) = w.priceCalculator().calculate(minRateLimit);

        // Register until just below max
        for (uint32 i = 1; i <= 99; i++) {
            token.approve(address(w), price);
            w.register(i, minRateLimit, noIdCommitmentsToErase);
        }
        assertEq(w.currentTotalRateLimit(), 99);

        // Register to reach max
        token.approve(address(w), price);
        w.register(100, minRateLimit, noIdCommitmentsToErase);
        assertEq(w.currentTotalRateLimit(), 100);

        // Attempt to exceed
        token.approve(address(w), price);
        vm.expectRevert(CannotExceedMaxTotalRateLimit.selector);
        w.register(101, minRateLimit, noIdCommitmentsToErase);

        // Destructure memberships to get gracePeriodStartTimestamp and gracePeriodDuration
        (
            , // depositAmount
            , // activeDuration
            uint256 graceStart,
            uint32 gracePeriodDuration,
            , // rateLimit
            , // index
            , // holder
                // token
        ) = w.memberships(100);
        vm.warp(graceStart + gracePeriodDuration + 1); // Expire one

        uint256[] memory toErase = new uint256[](1);
        toErase[0] = 100;
        w.eraseMemberships(toErase);
        assertEq(w.currentTotalRateLimit(), 99);

        token.approve(address(w), price);
        w.register(101, minRateLimit, noIdCommitmentsToErase);
        assertEq(w.currentTotalRateLimit(), 100);
    }

    function test__MerkleTreeUpdateAfterErasureAndReuse() external {
        uint256 idCommitment1 = 1;
        uint32 rateLimit = w.minMembershipRateLimit();
        (, uint256 price) = w.priceCalculator().calculate(rateLimit);

        token.approve(address(w), price);
        w.register(idCommitment1, rateLimit, noIdCommitmentsToErase);

        uint256 initialRoot = w.root();
        uint256 rateCommitment1 = PoseidonT3.hash([idCommitment1, rateLimit]);
        uint256[] memory commitments = w.getRateCommitmentsInRangeBoundsInclusive(0, 0);
        assertEq(commitments[0], rateCommitment1);

        // Erase lazily
        (
            , // depositAmount
            , // activeDuration
            uint256 graceStart,
            , // gracePeriodDuration
            , // rateLimit
            , // index
            , // holder
                // token
        ) = w.memberships(idCommitment1);
        vm.warp(graceStart);
        uint256[] memory toErase = new uint256[](1);
        toErase[0] = idCommitment1;
        w.eraseMemberships(toErase, false); // Lazy

        // Root unchanged since lazy
        assertEq(w.root(), initialRoot);

        // Reuse index 0 with new commitment
        uint256 idCommitment2 = 2;
        token.approve(address(w), price);
        w.register(idCommitment2, rateLimit, noIdCommitmentsToErase);

        uint256 rateCommitment2 = PoseidonT3.hash([idCommitment2, rateLimit]);
        commitments = w.getRateCommitmentsInRangeBoundsInclusive(0, 0);
        assertEq(commitments[0], rateCommitment2);
        assertNotEq(w.root(), initialRoot); // Root updated

        // Verify proof
        uint256[20] memory proof = w.getMerkleProof(0);
        uint256 updatedRoot = w.root();
        uint256 leaf = commitments[0];
        uint256 computedRoot = leaf;
        uint256 index = 0;
        for (uint8 i = 0; i < 20; i++) {
            uint256 sibling = proof[i];
            if (index % 2 == 0) {
                computedRoot = PoseidonT3.hash([computedRoot, sibling]);
            } else {
                computedRoot = PoseidonT3.hash([sibling, computedRoot]);
            }
            index >>= 1;
        }
        assertEq(computedRoot, updatedRoot);
    }

    function test__ZeroGracePeriodDuration() external {
        // Deploy new instance with zero grace period
        IPriceCalculator priceCalculator = (new DeployPriceCalculator()).deploy(address(token));
        WakuRlnV2 wakuRlnV2 = (new DeployWakuRlnV2()).deploy();
        ERC1967Proxy proxy = new ERC1967Proxy(
            address(wakuRlnV2),
            abi.encodeCall(WakuRlnV2.initialize, (address(priceCalculator), 100, 1, 10, 10 minutes, 0))
        );
        WakuRlnV2 wZeroGrace = WakuRlnV2(address(proxy));

        uint256 idCommitment = 1;
        uint32 rateLimit = wZeroGrace.minMembershipRateLimit();
        (, uint256 price) = wZeroGrace.priceCalculator().calculate(rateLimit);

        token.approve(address(wZeroGrace), price);
        wZeroGrace.register(idCommitment, rateLimit, noIdCommitmentsToErase);

        (
            , // depositAmount
            , // activeDuration
            uint256 gracePeriodStart,
            , // gracePeriodDuration
            , // rateLimit
            , // index
            , // holder
                // token
        ) = wZeroGrace.memberships(idCommitment);

        // Warp just after active period
        vm.warp(gracePeriodStart + 1);
        assertTrue(wZeroGrace.isExpired(idCommitment));
        assertFalse(wZeroGrace.isInGracePeriod(idCommitment));

        uint256[] memory ids = new uint256[](1);
        ids[0] = idCommitment;
        vm.expectRevert(abi.encodeWithSelector(CannotExtendNonGracePeriodMembership.selector, idCommitment));
        wZeroGrace.extendMemberships(ids);

        // Erase and check event
        vm.expectEmit(true, true, true, true);
        emit MembershipUpgradeable.MembershipExpired(idCommitment, rateLimit, 0);
        wZeroGrace.eraseMemberships(ids);

        (,,,, uint32 fetchedRateLimit,,,) = wZeroGrace.memberships(idCommitment);
        assertEq(fetchedRateLimit, 0);
    }

    function test__FullCleanUpErasure() external {
        uint256 idCommitment = 1;
        uint32 rateLimit = w.minMembershipRateLimit();
        (, uint256 price) = w.priceCalculator().calculate(rateLimit);

        token.approve(address(w), price);
        w.register(idCommitment, rateLimit, noIdCommitmentsToErase);

        uint256 initialRoot = w.root();

        (
            , // depositAmount
            , // activeDuration
            uint256 graceStart,
            uint32 gracePeriodDuration,
            , // rateLimit
            , // index
            , // holder
                // token
        ) = w.memberships(idCommitment);

        vm.warp(graceStart + gracePeriodDuration + 1); // Expire

        uint256[] memory toErase = new uint256[](1);
        toErase[0] = idCommitment;
        w.eraseMemberships(toErase, true); // Full clean-up

        // Use public function to get rate commitment at index 0
        uint256[] memory commitments = w.getRateCommitmentsInRangeBoundsInclusive(0, 0);
        assertEq(commitments[0], 0);

        assertNotEq(w.root(), initialRoot); // Root changed

        // Count the length of indicesOfLazilyErasedMemberships
        uint256 erasedLength = 0;
        while (true) {
            try w.indicesOfLazilyErasedMemberships(erasedLength) {
                erasedLength++;
            } catch {
                break;
            }
        }
        assertEq(erasedLength, 1);
        assertEq(w.nextFreeIndex(), 1); // Unchanged
    }

    function test__TokenTransferFailures() external {
        // Deploy MaliciousToken implementation
        MaliciousToken maliciousTokenImpl = new MaliciousToken();

        // Deploy proxy with no reentrancy (enables failTransfer)
        ERC1967Proxy proxy =
            new ERC1967Proxy(address(maliciousTokenImpl),
                abi.encodeCall(MaliciousToken.initialize, (address(0), true)));
        MaliciousToken maliciousToken = MaliciousToken(address(proxy));

        // Mint tokens
        maliciousToken.mint(address(this), 100_000_000 ether);

        // Set price calculator
        vm.prank(w.owner());
        w.setPriceCalculator(address(new DeployPriceCalculator().deploy(address(maliciousToken))));

        uint32 rateLimit = w.minMembershipRateLimit();
        (, uint256 price) = w.priceCalculator().calculate(rateLimit);

        // Approve tokens
        maliciousToken.approve(address(w), price);

        // Expect transfer failure
        vm.expectRevert("Malicious transfer failure");
        w.register(1, rateLimit, noIdCommitmentsToErase);
    }

    struct ReinitSnap {
        address owner;
        address priceCalculator;
        uint32 maxTotalRateLimit;
        uint32 minMembershipRateLimit;
        uint32 maxMembershipRateLimit;
        uint32 activeDurationForNewMemberships;
        uint32 gracePeriodDurationForNewMemberships;
        uint32 MAX_MEMBERSHIP_SET_SIZE;
        uint32 deployedBlockNumber;
        uint32 nextFreeIndex;
        uint256 currentTotalRateLimit;
        uint256 merkleRoot;
    }

    function _snapshot() internal view returns (ReinitSnap memory s) {
        s.owner = w.owner();
        s.priceCalculator = address(w.priceCalculator());
        s.maxTotalRateLimit = w.maxTotalRateLimit();
        s.minMembershipRateLimit = w.minMembershipRateLimit();
        s.maxMembershipRateLimit = w.maxMembershipRateLimit();
        s.activeDurationForNewMemberships = w.activeDurationForNewMemberships();
        s.gracePeriodDurationForNewMemberships = w.gracePeriodDurationForNewMemberships();
        s.MAX_MEMBERSHIP_SET_SIZE = w.MAX_MEMBERSHIP_SET_SIZE();
        s.deployedBlockNumber = w.deployedBlockNumber();
        s.nextFreeIndex = w.nextFreeIndex();
        s.currentTotalRateLimit = w.currentTotalRateLimit();
        s.merkleRoot = w.root();
    }

    function test__ReinitializationProtection() external {
        // 1) Snapshot before
        ReinitSnap memory before_ = _snapshot();

        // 2) Prepare args BEFORE expectRevert (to avoid consuming it with view calls)
        address calc = before_.priceCalculator;
        uint32 maxTotal = before_.maxTotalRateLimit;
        uint32 minRate = before_.minMembershipRateLimit;
        uint32 maxRate = before_.maxMembershipRateLimit;
        uint32 activeDur = 15;
        uint32 graceDur = 5;

        // 3) Second initialization must revert (use a loose matcher for OZ v4/v5 compatibility)
        vm.expectRevert("Initializable: contract is already initialized");
        w.initialize(calc, maxTotal, minRate, maxRate, activeDur, graceDur);

        // 4) Snapshot after and compare
        ReinitSnap memory after_ = _snapshot();

        assertEq(after_.owner, before_.owner, "owner changed");
        assertEq(after_.priceCalculator, before_.priceCalculator, "priceCalculator changed");
        assertEq(after_.maxTotalRateLimit, before_.maxTotalRateLimit, "maxTotalRateLimit changed");
        assertEq(after_.minMembershipRateLimit, before_.minMembershipRateLimit, "minMembershipRateLimit changed");
        assertEq(after_.maxMembershipRateLimit, before_.maxMembershipRateLimit, "maxMembershipRateLimit changed");
        assertEq(
            after_.activeDurationForNewMemberships, before_.activeDurationForNewMemberships, "activeDuration changed"
        );
        assertEq(
            after_.gracePeriodDurationForNewMemberships,
            before_.gracePeriodDurationForNewMemberships,
            "gracePeriod changed"
        );
        assertEq(after_.MAX_MEMBERSHIP_SET_SIZE, before_.MAX_MEMBERSHIP_SET_SIZE, "MAX_MEMBERSHIP_SET_SIZE changed");
        assertEq(after_.deployedBlockNumber, before_.deployedBlockNumber, "deployedBlockNumber changed");
        assertEq(after_.nextFreeIndex, before_.nextFreeIndex, "nextFreeIndex changed");
        assertEq(after_.currentTotalRateLimit, before_.currentTotalRateLimit, "currentTotalRateLimit changed");
        assertEq(after_.merkleRoot, before_.merkleRoot, "merkle root changed");
    }

    function test__PriceCalculatorReconfiguration() external {
        LinearPriceCalculator newCalc = new LinearPriceCalculator(address(token), 10 wei); // Different price

        // Non-owner
        vm.prank(vm.addr(1));
        vm.expectRevert("Ownable: caller is not the owner");
        w.setPriceCalculator(address(newCalc));

        // Owner
        vm.prank(w.owner());
        w.setPriceCalculator(address(newCalc));

        assertEq(address(w.priceCalculator()), address(newCalc));

        uint32 rateLimit = w.minMembershipRateLimit();
        (, uint256 newPrice) = w.priceCalculator().calculate(rateLimit);
        assertEq(newPrice, uint256(rateLimit) * 10 wei);

        token.approve(address(w), newPrice);
        w.register(1, rateLimit, noIdCommitmentsToErase);
        assertEq(token.balanceOf(address(w)), newPrice);
    }

    function test__ZeroPriceEdgeCase() external {
        MockPriceCalculator zeroPriceCalc = new MockPriceCalculator(address(token), 0);

        vm.prank(w.owner());
        w.setPriceCalculator(address(zeroPriceCalc));

        uint32 rateLimit = w.minMembershipRateLimit();
        (, uint256 price) = w.priceCalculator().calculate(rateLimit);
        assertEq(price, 0);

        // No approval needed since price=0
        w.register(1, rateLimit, noIdCommitmentsToErase);

        (,,,, uint32 fetchedRateLimit, uint32 index,,) = w.memberships(1);
        assertEq(fetchedRateLimit, rateLimit);
        assertEq(index, 0);
        assertEq(
            w.root(),
            13_301_394_660_502_635_912_556_179_583_660_948_983_063_063_326_359_792_688_871_878_654_796_186_320_104
        ); // expected root after insert
        assertEq(token.balanceOf(address(w)), 0); // No transfer
    }
}
