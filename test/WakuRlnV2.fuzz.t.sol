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
        uint256 uint256Max = type(uint256).max;

        // Prevent overflow in block.timestamp + timeDelta
        vm.assume(timeDelta <= uint256Max - block.timestamp);

        // Constrain to invalid scenarios with focus on extreme values
        uint256 active = uint256(w.activeDurationForNewMemberships());
        uint256 grace = uint256(w.gracePeriodDurationForNewMemberships());
        vm.assume(
            // Case 1: During active (cannot extend) - extremes: start, near/end of active
            (timeDelta < active && (timeDelta == 0 || timeDelta == 1 || timeDelta == active - 1))
            // Case 2: After expiration (cannot extend expired) - extremes: just after, next, far future
            || (
                timeDelta >= active + grace
                    && (timeDelta == active + grace || timeDelta == active + grace + 1 || timeDelta == uint256Max)
            )
            // Case 3: Non-holder sender - extremes: zero addr, low, max addr
            || (
                sender != address(this)
                    && (sender == address(0) || sender == address(1) || sender == address(type(uint160).max))
            )
            // Case 4: Invalid/non-existent ID - extremes: zero, near Q, at/over Q, max uint
            || (
                invalidId != validId
                    && (invalidId == 0 || invalidId == w.Q() - 1 || invalidId == w.Q() || invalidId == uint256Max)
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

    // Fuzz Test: Owner Sets Max Total Rate Limit with Extremes
    function testFuzz_SetMaxTotalRateLimit(uint32 newMaxTotal, bool registerBefore) external {
        // Prank as owner for all calls
        address owner = w.owner();
        vm.startPrank(owner);

        // Optionally register a membership before to test impact on current total
        uint32 minRate = w.minMembershipRateLimit();
        if (registerBefore && minRate <= w.maxTotalRateLimit()) {
            vm.stopPrank(); // Temporarily switch to test contract for registration
            _registerMembership(1, minRate);
            vm.startPrank(owner);
        }
        uint256 currentTotal = w.currentTotalRateLimit();

        // Fuzz constraints: Focus on extremes (0, min, max uint32, boundaries around current/max membership)
        uint32 maxMembership = w.maxMembershipRateLimit();
        vm.assume(
            newMaxTotal == 0 || newMaxTotal == 1 || newMaxTotal == maxMembership - 1 || newMaxTotal == maxMembership
                || newMaxTotal == maxMembership + 1 || newMaxTotal == type(uint32).max - 1
                || newMaxTotal == type(uint32).max
        );

        // Expect revert if invalid (newMaxTotal < maxMembership), else succeed
        if (newMaxTotal < maxMembership) {
            vm.expectRevert(); // Invalid (require maxMembership <= newMaxTotal)
            w.setMaxTotalRateLimit(newMaxTotal);
        } else {
            w.setMaxTotalRateLimit(newMaxTotal);
            assertEq(w.maxTotalRateLimit(), newMaxTotal); // Getter matches
        }

        // Invariant: Existing memberships unaffected
        if (registerBefore) {
            assertEq(w.currentTotalRateLimit(), currentTotal); // Total unchanged
            (,,,, uint32 rl,,,) = w.memberships(1);
            assertEq(rl, minRate); // Rate limit immutable
        }

        // Chain: Attempt new registration to test DoS/overflow effects
        vm.stopPrank();
        uint256 newMax = w.maxTotalRateLimit(); // Use updated
        uint256 newCurrent = w.currentTotalRateLimit();
        if (minRate <= newMax && newCurrent + minRate <= newMax) {
            _registerMembership(2, minRate); // Succeed if valid
        } else {
            vm.expectRevert(CannotExceedMaxTotalRateLimit.selector);
            _registerMembership(2, minRate); // Revert if exceeds
        }

        vm.stopPrank();
    }

    // Fuzz Test: Owner Sets Active Duration with Extremes
    function testFuzz_SetActiveDuration(uint32 newActiveDur, bool registerBefore) external {
        // Prank as owner
        address owner = w.owner();
        vm.startPrank(owner);

        // Optionally register before to test no impact on existing
        uint32 minRate = w.minMembershipRateLimit();
        uint32 originalActiveDur;
        uint256 originalGraceStart;
        if (registerBefore && minRate <= w.maxTotalRateLimit()) {
            vm.stopPrank();
            _registerMembership(1, minRate);
            (,, originalGraceStart,,,,,) = w.memberships(1);
            (, originalActiveDur,,,,,,) = w.memberships(1);
            vm.startPrank(owner);
        }

        // Fuzz constraints: Extremes (0, 1, max uint32, etc.)
        vm.assume(
            newActiveDur == 0 || newActiveDur == 1 || newActiveDur == type(uint32).max - 1
                || newActiveDur == type(uint32).max
        );

        // Expect revert if invalid (==0)
        if (newActiveDur == 0) {
            vm.expectRevert(); // require >0
            w.setActiveDuration(newActiveDur);
        } else {
            w.setActiveDuration(newActiveDur);
            assertEq(w.activeDurationForNewMemberships(), newActiveDur); // Getter matches
        }

        // Invariant: Existing memberships unaffected (durations immutable)
        if (registerBefore) {
            (,, uint256 graceStart,,,,,) = w.memberships(1);
            assertEq(graceStart, originalGraceStart); // Grace start unchanged
            (, uint32 activeDur,,,,,,) = w.memberships(1);
            assertEq(activeDur, originalActiveDur); // Existing keeps original duration
        }

        // Chain: New registration uses new duration, test extremes
        vm.stopPrank();
        if (newActiveDur > 0 && minRate <= w.maxTotalRateLimit()) {
            _registerMembership(2, minRate);
            (, uint32 activeDur, uint256 newGraceStart,,,,,) = w.memberships(2);
            assertEq(activeDur, newActiveDur); // New uses updated
            assertEq(newGraceStart, block.timestamp + uint256(newActiveDur)); // Correct start
        }

        vm.stopPrank();
    }

    // Helper: Verify Merkle Proof Manually (since lib lacks verify)
    function _verifyMerkleProof(
        uint256[20] memory proof,
        uint256 root,
        uint32 index,
        uint256 leaf,
        uint8 depth
    )
        internal
        pure
        returns (bool)
    {
        uint256 current = leaf;
        uint32 idx = index;
        for (uint8 level = 0; level < depth; level++) {
            bool isLeft = (idx & 1) == 0;
            uint256 sibling = proof[level];
            uint256[2] memory inputs;
            if (isLeft) {
                inputs[0] = current;
                inputs[1] = sibling;
            } else {
                inputs[0] = sibling;
                inputs[1] = current;
            }
            current = PoseidonT3.hash(inputs);
            idx >>= 1;
        }
        return current == root;
    }

    // Merkle Tree Insertions and Proofs via Registrations
    function testFuzz_MerkleInserts(uint8 numInserts) external {
        vm.assume(numInserts > 0 && numInserts <= 16);

        uint32 rateLimit = w.minMembershipRateLimit();
        uint256[] memory ids = new uint256[](numInserts);
        uint32[] memory indices = new uint32[](numInserts);

        // Sequence: Fuzz registrations, track indices and commitments
        for (uint8 i = 0; i < numInserts; i++) {
            uint256 id = uint256(keccak256(abi.encodePacked(i, block.timestamp))) % (w.Q() - 1) + 1; // Valid random ID
            ids[i] = id;
            vm.assume(w.currentTotalRateLimit() + rateLimit <= w.maxTotalRateLimit());

            (, uint256 price) = w.priceCalculator().calculate(rateLimit);
            token.approve(address(w), price);
            w.register(id, rateLimit, new uint256[](0));

            // Track index and expected root (incremental)
            (uint32 rl, uint32 idx, uint256 commitment) = w.getMembershipInfo(id);
            indices[i] = idx;
            assertEq(rl, rateLimit);
            assertTrue(commitment != 0); // Inserted

            // Sampled proof verification: Only check every other for gas savings
            if (i % 2 == 0) {
                uint256[20] memory proof = w.getMerkleProof(idx);
                uint256 root = w.root();
                assertTrue(_verifyMerkleProof(proof, root, idx, commitment, 20));
            }
        }

        // Post-sequence invariants: Roots evolved correctly, no overwrites - sampled checks
        assertEq(w.nextFreeIndex(), numInserts); // Filled sequentially
        for (uint8 i = 0; i < numInserts; i += 2) {
            // Sample every other
            (, uint32 idx,) = w.getMembershipInfo(ids[i]);
            assertEq(idx, i); // Sequential indices
            assertEq(
                w.getRateCommitmentsInRangeBoundsInclusive(idx, idx)[0], PoseidonT3.hash([ids[i], uint256(rateLimit)])
            );
        }
    }

    // Merkle Tree Erasures and Reuses (Lazy/Full)
    function testFuzz_MerkleErasures(uint8 numOps, bool fullErase) external {
        vm.assume(numOps > 0 && numOps <= 8); // Low for gas optimization

        uint32 rateLimit = w.minMembershipRateLimit();
        uint256[] memory ids = new uint256[](numOps);
        uint32[] memory indices = new uint32[](numOps);

        // Phase 1: Register fuzz numOps memberships
        for (uint8 i = 0; i < numOps; i++) {
            uint256 id = uint256(keccak256(abi.encodePacked(i, block.timestamp))) % (w.Q() - 1) + 1;
            ids[i] = id;
            vm.assume(w.currentTotalRateLimit() + rateLimit <= w.maxTotalRateLimit());

            (, uint256 price) = w.priceCalculator().calculate(rateLimit);
            token.approve(address(w), price);
            w.register(id, rateLimit, new uint256[](0));

            (, indices[i],) = w.getMembershipInfo(id);
        }

        // Warp to expire all (for erasure eligibility)
        uint256 minDelta =
            uint256(w.activeDurationForNewMemberships()) + uint256(w.gracePeriodDurationForNewMemberships()) + 1;
        vm.warp(block.timestamp + minDelta);

        // Phase 2: Erase all (lazy or full), check proofs/roots - sampled
        w.eraseMemberships(ids, fullErase);

        uint256 postEraseRoot = w.root();
        for (uint8 i = 0; i < numOps; i += 2) {
            // Sample every other
            assertFalse(w.isInMembershipSet(ids[i])); // Erased
            (,, uint256 commitment) = w.getMembershipInfo(ids[i]);
            assertEq(commitment, 0);

            // Invariant: Leaf is 0 (full) or old commitment (lazy), proof still valid for current root
            uint256 expectedLeaf = fullErase ? 0 : PoseidonT3.hash([ids[i], uint256(rateLimit)]);
            assertEq(w.getRateCommitmentsInRangeBoundsInclusive(indices[i], indices[i])[0], expectedLeaf);

            uint256[20] memory proof = w.getMerkleProof(indices[i]);
            assertTrue(_verifyMerkleProof(proof, postEraseRoot, indices[i], expectedLeaf, 20));
        }

        // Phase 3: Reuse erased indices via new registrations, check no overwrite issues - sampled
        for (uint8 i = 0; i < numOps; i += 2) {
            // Sample every other
            uint256 newId = uint256(keccak256(abi.encodePacked(i + numOps, block.timestamp))) % (w.Q() - 1) + 1;
            vm.assume(w.currentTotalRateLimit() + rateLimit <= w.maxTotalRateLimit());

            (, uint256 price) = w.priceCalculator().calculate(rateLimit);
            token.approve(address(w), price);
            w.register(newId, rateLimit, new uint256[](0));

            // Invariant: Reused index, new commitment, proof updates root
            (, uint32 newIdx, uint256 newCommitment) = w.getMembershipInfo(newId);
            assertTrue(newIdx < numOps); // Reused from 0 to numOps-1

            uint256[20] memory newProof = w.getMerkleProof(newIdx);
            uint256 newRoot = w.root();
            assertTrue(_verifyMerkleProof(newProof, newRoot, newIdx, newCommitment, 20));
            assertTrue(newRoot != postEraseRoot); // Root changed
        }

        // Final invariant: Tree size matches ops
        assertEq(w.nextFreeIndex(), numOps);
    }

    // Fuzz Test: Query Rate Commitments in Ranges (Valid/Invalid Pagination)
    function testFuzz_GetRateCommitmentsRange(uint32 startIndex, uint32 endIndex) external {
        // Setup: Register a variable number of memberships for tree population
        uint8 numRegs = 16; // Fixed small for gas; could fuzz if needed
        uint32 rateLimit = w.minMembershipRateLimit();
        uint256[] memory ids = new uint256[](numRegs);

        for (uint8 i = 0; i < numRegs; i++) {
            uint256 id = uint256(keccak256(abi.encodePacked(i, block.timestamp))) % (w.Q() - 1) + 1;
            ids[i] = id;
            vm.assume(w.currentTotalRateLimit() + rateLimit <= w.maxTotalRateLimit());

            (, uint256 price) = w.priceCalculator().calculate(rateLimit);
            token.approve(address(w), price);
            w.register(id, rateLimit, new uint256[](0));
        }

        uint32 nextFree = w.nextFreeIndex();
        assertEq(nextFree, numRegs); // Populated

        // Fuzz constraints: Focus on extremes/invalids (0, max, beyond, start>end)
        vm.assume(
            // Valid: 0 <= start <= end < nextFree
            (startIndex <= endIndex && endIndex < nextFree)
            // Invalid: start > end, or end >= nextFree, or extremes like uint32.max
            || (startIndex > endIndex) || (endIndex >= nextFree) || (startIndex == type(uint32).max)
                || (endIndex == type(uint32).max) || (startIndex == nextFree - 1 && endIndex == nextFree)
        );

        // Expect revert on invalid pagination
        if (startIndex > endIndex || endIndex >= nextFree) {
            vm.expectRevert(abi.encodeWithSelector(InvalidPaginationQuery.selector, startIndex, endIndex));
            w.getRateCommitmentsInRangeBoundsInclusive(startIndex, endIndex);
        } else {
            uint256[] memory commitments = w.getRateCommitmentsInRangeBoundsInclusive(startIndex, endIndex);
            uint256 expectedLen = uint256(endIndex) - uint256(startIndex) + 1;
            assertEq(commitments.length, expectedLen); // Correct length

            // Invariant: Matches expected hashes for IDs at indices
            for (uint32 j = startIndex; j <= endIndex; j++) {
                uint256 expected = PoseidonT3.hash([ids[j], uint256(rateLimit)]);
                assertEq(commitments[j - startIndex], expected);
            }
        }

        // Gas DoS check implicit: Small ranges pass; large would OOM in full tree (but scaled)
    }

    // Fuzz Test: Get Merkle Proofs for Indices (Valid/Invalid)
    function testFuzz_GetMerkleProof(uint32 index) external {
        // Setup: Register small tree
        uint8 numRegs = 16;
        uint32 rateLimit = w.minMembershipRateLimit();
        uint256[] memory ids = new uint256[](numRegs);

        for (uint8 i = 0; i < numRegs; i++) {
            uint256 id = uint256(keccak256(abi.encodePacked(i, block.timestamp))) % (w.Q() - 1) + 1;
            ids[i] = id;
            vm.assume(w.currentTotalRateLimit() + rateLimit <= w.maxTotalRateLimit());

            (, uint256 price) = w.priceCalculator().calculate(rateLimit);
            token.approve(address(w), price);
            w.register(id, rateLimit, new uint256[](0));
        }

        uint32 nextFree = w.nextFreeIndex();
        uint32 maxIndex = nextFree - 1;

        // Fuzz constraints: Valid (0 to maxIndex) or invalid (beyond, extremes)
        vm.assume(
            (index <= maxIndex) // Valid
                || (index > maxIndex) // Beyond nextFree
                || (index == type(uint32).max) // Extreme
                || (index == 0 && nextFree > 0) // Edge valid
        );

        uint256 root = w.root();

        // Expect revert on invalid index (beyond tree size)
        if (index >= nextFree) {
            vm.expectRevert("LazyIMT: leaf must exist");
        }

        // Get proof (may revert for invalid)
        uint256[20] memory proof = w.getMerkleProof(index);

        if (index > maxIndex) {
            // For invalid (if no revert, but per lib it does), skip further asserts or note
            return;
        }

        // Get expected commitment for index
        uint256 expectedCommitment = w.getRateCommitmentsInRangeBoundsInclusive(index, index)[0];

        // Invariant: Proof verifies expected leaf
        assertTrue(_verifyMerkleProof(proof, root, index, expectedCommitment, 20));

        // Mismatch on wrong leaf
        assertFalse(_verifyMerkleProof(proof, root, index, expectedCommitment + 1, 20));
    }
}
