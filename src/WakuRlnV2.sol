// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import { LazyIMT, LazyIMTData } from "@zk-kit/imt.sol/LazyIMT.sol";
import { PoseidonT3 } from "poseidon-solidity/PoseidonT3.sol";

import { Ownable2StepUpgradeable } from "@openzeppelin/contracts-upgradeable/access/Ownable2StepUpgradeable.sol";
import { Initializable } from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import { UUPSUpgradeable } from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";

import { MembershipUpgradeable } from "./Membership.sol";
import { IPriceCalculator } from "./IPriceCalculator.sol";

/// A membership with this idCommitment is already registered
error DuplicateIdCommitment();

/// Invalid idCommitment
error InvalidIdCommitment(uint256 idCommitment);

/// Invalid pagination query
error InvalidPaginationQuery(uint256 startIndex, uint256 endIndex);

contract WakuRlnV2 is Initializable, Ownable2StepUpgradeable, UUPSUpgradeable, MembershipUpgradeable {
    /// @notice The Field
    uint256 public constant Q =
        21_888_242_871_839_275_222_246_405_745_257_275_088_548_364_400_416_034_343_698_204_186_575_808_495_617;

    /// @notice The depth of the Merkle tree that stores rate commitments of memberships
    uint8 public constant MERKLE_TREE_DEPTH = 20;

    /// @notice The maximum membership set size is the size of the Merkle tree (2 ^ depth)
    uint32 public MAX_MEMBERSHIP_SET_SIZE;

    /// @notice The block number at which this contract was deployed
    uint32 public deployedBlockNumber;

    /// @notice The Merkle tree that stores rate commitments of memberships
    LazyIMTData public merkleTree;

    /// @notice the modifier to check if the idCommitment is valid
    /// @param idCommitment The idCommitment of the membership
    modifier onlyValidIdCommitment(uint256 idCommitment) {
        if (!isValidIdCommitment(idCommitment)) revert InvalidIdCommitment(idCommitment);
        _;
    }

    /// @notice the modifier to check that the membership with this idCommitment doesn't already exist
    /// @param idCommitment The idCommitment of the membership
    modifier noDuplicateMembership(uint256 idCommitment) {
        require(!isInMembershipSet(idCommitment), "Duplicate idCommitment: membership already exists");
        _;
    }

    /// @notice the modifier to check that the membership set is not full
    modifier membershipSetNotFull() {
        require(nextFreeIndex < MAX_MEMBERSHIP_SET_SIZE, "Membership set is full");
        _;
    }

    constructor() {
        _disableInitializers();
    }

    /// @dev contract initializer
    /// @param _priceCalculator Address of an instance of IPriceCalculator
    /// @param _maxTotalRateLimit Maximum total rate limit of all memberships in the membership set
    /// @param _minMembershipRateLimit Minimum rate limit of one membership
    /// @param _maxMembershipRateLimit Maximum rate limit of one membership
    /// @param _activeDuration Membership active duration
    /// @param _gracePeriod Membership grace period
    function initialize(
        address _priceCalculator,
        uint32 _maxTotalRateLimit,
        uint32 _minMembershipRateLimit,
        uint32 _maxMembershipRateLimit,
        uint32 _activeDuration,
        uint32 _gracePeriod
    )
        public
        initializer
    {
        __Ownable_init();
        __UUPSUpgradeable_init();
        __MembershipUpgradeable_init(
            _priceCalculator,
            _maxTotalRateLimit,
            _minMembershipRateLimit,
            _maxMembershipRateLimit,
            _activeDuration,
            _gracePeriod
        );

        MAX_MEMBERSHIP_SET_SIZE = uint32(1 << MERKLE_TREE_DEPTH);
        deployedBlockNumber = uint32(block.number);
        LazyIMT.init(merkleTree, MERKLE_TREE_DEPTH);
        nextFreeIndex = 0;
    }

    function _authorizeUpgrade(address newImplementation) internal override onlyOwner { } // solhint-disable-line

    /// @notice Checks if an idCommitment is valid
    /// @param idCommitment The idCommitment of the membership
    /// @return true if the idCommitment is valid, false otherwise
    function isValidIdCommitment(uint256 idCommitment) public pure returns (bool) {
        return idCommitment != 0 && idCommitment < Q;
    }

    /// @notice Checks if a membership is in the membership set
    /// @param idCommitment The idCommitment of the membership
    /// @return true if the membership is in the membership set, false otherwise
    function isInMembershipSet(uint256 idCommitment) public view returns (bool) {
        (,, uint256 rateCommitment) = getMembershipInfo(idCommitment);
        return rateCommitment != 0;
    }

    /// @notice Returns the membership info (rate limit, index, rateCommitment) by its idCommitment
    /// @param idCommitment The idCommitment of the membership
    /// @return The membership info (rateLimit, index, rateCommitment)
    function getMembershipInfo(uint256 idCommitment) public view returns (uint32, uint32, uint256) {
        MembershipInfo memory membership = memberships[idCommitment];
        // we cannot call getRateCommmitment for 0 index if the membership doesn't exist
        if (membership.rateLimit == 0) {
            return (0, 0, 0);
        }
        return (membership.rateLimit, membership.index, _getRateCommmitment(membership.index));
    }

    /// @notice Returns the rateCommitments of memberships within an index range
    /// @param startIndex The start index of the range (inclusive)
    /// @param endIndex The end index of the range (inclusive)
    /// @return The rateCommitments of the memberships
    function getRateCommitmentsInRange(uint32 startIndex, uint32 endIndex) public view returns (uint256[] memory) {
        if (startIndex > endIndex) revert InvalidPaginationQuery(startIndex, endIndex);
        if (endIndex > nextFreeIndex) revert InvalidPaginationQuery(startIndex, endIndex); //FIXME: should it be >=?

        uint256[] memory rateCommitments = new uint256[](endIndex - startIndex + 1);
        for (uint32 i = startIndex; i <= endIndex; i++) {
            rateCommitments[i - startIndex] = _getRateCommmitment(i);
        }
        return rateCommitments;
    }

    /// @notice Returns the rateCommitment of a membership at a given index
    /// @param index The index of the membership in the membership set
    /// @return The rateCommitment of the membership
    function _getRateCommmitment(uint32 index) internal view returns (uint256) {
        return merkleTree.elements[LazyIMT.indexForElement(0, index)];
    }

    /// @notice Register a membership
    /// @param idCommitment The idCommitment of the new membership
    /// @param rateLimit The rate limit of the new membership
    function register(
        uint256 idCommitment,
        uint32 rateLimit
    )
        external
        onlyValidIdCommitment(idCommitment)
        noDuplicateMembership(idCommitment)
        membershipSetNotFull
    {
        _register(idCommitment, rateLimit);
    }

    /// @notice Register a membership
    /// @param idCommitment The idCommitment of the new membership
    /// @param rateLimit The rate limit of the new membership
    /// @param idCommitmentsToErase List of idCommitments of expired memberships to erase
    function register(
        uint256 idCommitment,
        uint32 rateLimit,
        uint256[] calldata idCommitmentsToErase
    )
        external
        onlyValidIdCommitment(idCommitment)
        noDuplicateMembership(idCommitment)
        membershipSetNotFull
    {
        _eraseMemberships(idCommitmentsToErase, false);
        _register(idCommitment, rateLimit);
    }

    /// @dev Registers a membership
    /// @param idCommitment The idCommitment of the membership
    /// @param rateLimit The rate limit of the membership
    function _register(uint256 idCommitment, uint32 rateLimit) internal {
        uint32 index;
        bool indexReused;
        (index, indexReused) = _acquireMembership(_msgSender(), idCommitment, rateLimit);

        uint256 rateCommitment = PoseidonT3.hash([idCommitment, rateLimit]);
        if (indexReused) {
            LazyIMT.update(merkleTree, rateCommitment, index);
        } else {
            LazyIMT.insert(merkleTree, rateCommitment);
            nextFreeIndex += 1;
        }

        emit MembershipRegistered(idCommitment, rateCommitment, index);
    }

    /// @notice Returns the root of the Merkle tree that stores rate commitments of memberships
    /// @return The root of the Merkle tree that stores rate commitments of memberships
    function root() external view returns (uint256) {
        return LazyIMT.root(merkleTree, MERKLE_TREE_DEPTH);
    }

    /// @notice Returns the Merkle proof that a given membership is in the membership set
    /// @param index The index of the membership
    /// @return The Merkle proof (an array of MERKLE_TREE_DEPTH elements)
    function getMerkleProof(uint40 index) public view returns (uint256[MERKLE_TREE_DEPTH] memory) {
        uint256[] memory dynamicSizeProof = LazyIMT.merkleProofElements(merkleTree, index, MERKLE_TREE_DEPTH);
        uint256[MERKLE_TREE_DEPTH] memory fixedSizeProof;
        for (uint8 i = 0; i < MERKLE_TREE_DEPTH; i++) {
            fixedSizeProof[i] = dynamicSizeProof[i];
        }
        return fixedSizeProof;
    }

    /// @notice Extend a grace-period membership
    /// @param idCommitments list of idCommitments of memberships to extend
    function extendMemberships(uint256[] calldata idCommitments) external {
        for (uint256 i = 0; i < idCommitments.length; i++) {
            uint256 idCommitmentToExtend = idCommitments[i];
            _extendMembership(_msgSender(), idCommitmentToExtend);
        }
    }

    /// @notice Erase expired memberships or owned grace-period memberships
    /// The user can select expired memberships offchain,
    /// and proceed to erase them.
    /// This function is also used to erase the user's own grace-period memberships.
    /// The user (i.e. the transaction sender) can then withdraw the deposited tokens.
    /// @param idCommitments list of idCommitments of the memberships to erase
    /// @param eraseFromMembershipSet Indicates whether to erase membership data from the set
    function eraseMemberships(uint256[] calldata idCommitments, bool eraseFromMembershipSet) external {
        // Clean-up: erase memberships from membership array (free up the rate limit),
        // and from the membership set (free up tree indices).
        _eraseMemberships(idCommitments, eraseFromMembershipSet);
    }

    /// @dev Erase memberships from the list of idCommitments
    /// @param idCommitmentsToErase The idCommitments of memberships to erase from storage
    /// @param eraseFromMembershipSet Indicates whether to erase membership data from the set
    function _eraseMemberships(uint256[] calldata idCommitmentsToErase, bool eraseFromMembershipSet) internal {
        for (uint256 i = 0; i < idCommitmentsToErase.length; i++) {
            uint256 idCommitmentToErase = idCommitmentsToErase[i];
            // Erase the membership from the memberships array in contract storage
            uint32 indexToErase = _eraseMembershipLazily(_msgSender(), idCommitmentToErase);
            // Optionally, also erase the rate commitment data from the membership set (the Merkle tree)
            // This does not affect index reusal for new membership registrations
            if (eraseFromMembershipSet) {
                LazyIMT.update(merkleTree, 0, indexToErase);
            }
        }
    }

    /// @notice Withdraw any available deposit balance in tokens after a membership is erased.
    /// @param token The address of the token to withdraw
    function withdraw(address token) external {
        _withdraw(_msgSender(), token);
    }

    /// @notice Set the address of the price calculator
    /// @param _priceCalculator new price calculator address
    function setPriceCalculator(address _priceCalculator) external onlyOwner {
        priceCalculator = IPriceCalculator(_priceCalculator);
    }

    /// @notice Set the maximum total rate limit of all memberships in the membership set
    /// @param _maxTotalRateLimit new maximum total rate limit (messages per epoch)
    function setMaxTotalRateLimit(uint32 _maxTotalRateLimit) external onlyOwner {
        require(_maxTotalRateLimit >= maxMembershipRateLimit);
        maxTotalRateLimit = _maxTotalRateLimit;
    }

    /// @notice Set the maximum rate limit of one membership
    /// @param _maxMembershipRateLimit  new maximum rate limit per membership (messages per epoch)
    function setMaxMembershipRateLimit(uint32 _maxMembershipRateLimit) external onlyOwner {
        require(_maxMembershipRateLimit >= minMembershipRateLimit);
        maxMembershipRateLimit = _maxMembershipRateLimit;
    }

    /// @notice Set the minimum rate limit of one membership
    /// @param _minMembershipRateLimit  new minimum rate limit per membership (messages per epoch)
    function setMinMembershipRateLimit(uint32 _minMembershipRateLimit) external onlyOwner {
        require(_minMembershipRateLimit > 0);
        require(_minMembershipRateLimit <= maxMembershipRateLimit);
        minMembershipRateLimit = _minMembershipRateLimit;
    }

    /// @notice Set the active duration for new memberships (terms of existing memberships don't change)
    /// @param _activeDurationForNewMembership  new active duration
    function setActiveDuration(uint32 _activeDurationForNewMembership) external onlyOwner {
        require(_activeDurationForNewMembership > 0);
        activeDurationForNewMemberships = _activeDurationForNewMembership;
    }

    /// @notice Set the grace period for new memberships (grace periods of existing memberships don't change)
    /// @param _gracePeriodDurationForNewMembership  new grace period duration
    function setGracePeriodDuration(uint32 _gracePeriodDurationForNewMembership) external onlyOwner {
        // Note: grace period duration may be equal to zero
        gracePeriodDurationForNewMemberships = _gracePeriodDurationForNewMembership;
    }
}
