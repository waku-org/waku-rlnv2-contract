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

        // Minting a large number of tokens to not have to worry about
        // Not having enough balance
        // 900_000 ether is chosen to be well above any test requirements and is within the new max supply constraints.
        vm.prank(address(tokenDeployer));
        token.mint(address(this), 900_000 ether);
    }

    function testFuzz_RegisterInvalid(uint256 idCommitment, uint32 rateLimit) external {
        vm.assume(idCommitment >= w.Q() || idCommitment == 0); // Invalid ID
        (, uint256 price) = w.priceCalculator().calculate(rateLimit);
        token.approve(address(w), price);
        vm.expectRevert(); // Generic or specific error
        w.register(idCommitment, rateLimit, new uint256[](0));
    }

    function testFuzz_MultipleRegisters(uint8 numRegs) external {
        vm.assume(numRegs > 0 && numRegs < 100); // Small for gas
        uint32 rateLimit = w.minMembershipRateLimit();
        uint256 totalExpected = 0;
        for (uint8 i = 1; i <= numRegs; i++) {
            vm.assume(w.currentTotalRateLimit() + rateLimit <= w.maxTotalRateLimit());
            (, uint256 price) = w.priceCalculator().calculate(rateLimit);
            token.approve(address(w), price);
            w.register(i, rateLimit, new uint256[](0));
            totalExpected += rateLimit;
        }
        assertEq(w.currentTotalRateLimit(), totalExpected);
    }

    // Helper function to register a single membership (reusable in tests)
    function _registerMembership(uint256 idCommitment, uint32 rateLimit) internal {
        (, uint256 price) = w.priceCalculator().calculate(rateLimit);
        token.approve(address(w), price);
        w.register(idCommitment, rateLimit, new uint256[](0));
    }

    function _buildIdsFromMask(uint8 subsetMask) internal pure returns (uint256[] memory idCommitments) {
        uint256 len = 0;
        for (uint8 bit = 0; bit < 4; bit++) {
            if ((subsetMask & (1 << bit)) != 0) {
                len++;
            }
        }
        idCommitments = new uint256[](len);
        uint256 idx = 0;
        for (uint8 bit = 0; bit < 4; bit++) {
            if ((subsetMask & (1 << bit)) != 0) {
                idCommitments[idx++] = uint256(bit) + 1;
            }
        }
    }

    // Fuzz Test: Erasure with Random IDs and Time Deltas
    function testFuzz_Erasure(bool fullErase, uint8 subsetMask) external {
        vm.assume(subsetMask > 0 && subsetMask < 16);
        // Setup: Register multiple memberships to allow fuzzing various IDs
        uint32 rateLimit = w.minMembershipRateLimit();
        uint256 initialTotal = 0;
        for (uint256 i = 1; i <= 4; i++) {
            // Register up to 4 for <5 constraint
            if (w.currentTotalRateLimit() + rateLimit <= w.maxTotalRateLimit()) {
                _registerMembership(i, rateLimit);
                initialTotal += rateLimit;
            }
        }

        // Fuzz time warp
        uint256 minDelta =
            uint256(w.activeDurationForNewMemberships()) + uint256(w.gracePeriodDurationForNewMemberships()) + 1;
        vm.warp(block.timestamp + minDelta);

        uint256[] memory idCommitments = _buildIdsFromMask(subsetMask);

        // Record indices before erasure
        uint32[] memory indices = new uint32[](idCommitments.length);
        for (uint256 j = 0; j < idCommitments.length; j++) {
            (, indices[j],) = w.getMembershipInfo(idCommitments[j]); // Get original index
        }

        w.eraseMemberships(idCommitments, fullErase);

        // Assert invariants: For each ID, check erased if conditions met
        uint256 erasedTotal = 0;
        uint256 rateLimitCast = uint256(rateLimit);
        for (uint256 j = 0; j < idCommitments.length; j++) {
            assertFalse(w.isInMembershipSet(idCommitments[j]));
            (uint32 rl,, uint256 commitment) = w.getMembershipInfo(idCommitments[j]);
            assertEq(rl, 0);
            assertEq(commitment, 0); // Info returns 0 if erased
            if (indices[j] < w.nextFreeIndex()) {
                // Valid index
                uint256 expectedCommitment = fullErase ? 0 : PoseidonT3.hash([idCommitments[j], rateLimitCast]);
                assertEq(w.getRateCommitmentsInRangeBoundsInclusive(indices[j], indices[j])[0], expectedCommitment);
            }
            erasedTotal += rateLimit; // Assuming all were valid to erase
        }
        assertEq(w.currentTotalRateLimit(), initialTotal - erasedTotal);
    }

    // Fuzz Test: Valid Registration with Invalid Extension Attempts
    function testFuzz_InvalidExtension(uint256 timeDelta, address sender, uint256 invalidId) external {
        // Setup: Register a valid membership
        uint32 rateLimit = w.minMembershipRateLimit();
        uint256 validId = 1;
        _registerMembership(validId, rateLimit);

        // Prevent overflow in block.timestamp + timeDelta
        vm.assume(timeDelta <= type(uint256).max - block.timestamp);

        // Constrain to invalid scenarios with focus on extreme values
        uint256 active = uint256(w.activeDurationForNewMemberships());
        uint256 grace = uint256(w.gracePeriodDurationForNewMemberships());
        vm.assume(
            // Case 1: During active (cannot extend) - extremes: start, near/end of active
            (timeDelta < active && (timeDelta == 0 || timeDelta == 1 || timeDelta == active - 1))
            // Case 2: After expiration (cannot extend expired) - extremes: just after, next, far future
            || (
                timeDelta >= active + grace
                    && (timeDelta == active + grace || timeDelta == active + grace + 1 || timeDelta == type(uint256).max)
            )
            // Case 3: Non-holder sender - extremes: zero addr, low, max addr
            || (
                sender != address(this)
                    && (sender == address(0) || sender == address(1) || sender == address(type(uint160).max))
            )
            // Case 4: Invalid/non-existent ID - extremes: zero, near Q, at/over Q, max uint
            || (
                invalidId != validId
                    && (invalidId == 0 || invalidId == w.Q() - 1 || invalidId == w.Q() || invalidId == type(uint256).max)
            )
        );

        // Warp time if needed
        if (timeDelta > 0) {
            vm.warp(block.timestamp + timeDelta);
        }

        // Prank sender if not this
        if (sender != address(this)) {
            vm.prank(sender);
        }

        // Prepare array with potentially invalid ID
        uint256[] memory toExtend = new uint256[](1);
        toExtend[0] = (invalidId == validId) ? validId : invalidId;

        // Expect revert for invalid extension
        vm.expectRevert(); // Generic, or specify error if known (e.g., CannotExtendNonGracePeriodMembership.selector)

        w.extendMemberships(toExtend);

        // Assert: State unchanged (grace start remains original)
        (,, uint256 graceStart,,,,,) = w.memberships(validId);
        uint256 expectedGraceStart = block.timestamp - timeDelta + active; // Original grace start
        assertEq(graceStart, expectedGraceStart);
        // Additional checks: Still in original state (e.g., expired if timeDelta > active + grace)
        if (timeDelta >= active + grace) {
            assertTrue(w.isExpired(validId));
        } else if (timeDelta < active) {
            assertFalse(w.isInGracePeriod(validId));
            assertFalse(w.isExpired(validId));
        }
    }
}
