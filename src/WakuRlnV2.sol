// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import { LazyIMT, LazyIMTData } from "@zk-kit/imt.sol/LazyIMT.sol";
import { PoseidonT3 } from "poseidon-solidity/PoseidonT3.sol";

import { Ownable2StepUpgradeable } from "@openzeppelin/contracts-upgradeable/access/Ownable2StepUpgradeable.sol";
import { Initializable } from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import { UUPSUpgradeable } from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";

import { MembershipUpgradeable } from "./Membership.sol";
import { IPriceCalculator } from "./IPriceCalculator.sol";

/// The tree is full
error FullTree();

/// Member is already registered
error DuplicateIdCommitment();

/// Invalid idCommitment
error InvalidIdCommitment(uint256 idCommitment);

/// Invalid userMessageLimit
error InvalidUserMessageLimit(uint32 messageLimit);

/// Invalid pagination query
error InvalidPaginationQuery(uint256 startIndex, uint256 endIndex);

contract WakuRlnV2 is Initializable, Ownable2StepUpgradeable, UUPSUpgradeable, MembershipUpgradeable {
    /// @notice The Field
    uint256 public constant Q =
        21_888_242_871_839_275_222_246_405_745_257_275_088_548_364_400_416_034_343_698_204_186_575_808_495_617;

    /// @notice The depth of the merkle tree
    uint8 public constant DEPTH = 20;

    /// @notice The size of the merkle tree, i.e 2^depth
    uint32 public SET_SIZE;

    /// @notice the deployed block number
    uint32 public deployedBlockNumber;

    /// @notice the stored imt data
    LazyIMTData public imtData;

    /// Emitted when a new member is added to the set
    /// @param rateCommitment the rateCommitment of the member
    /// @param index The index of the member in the set
    event MemberRegistered(uint256 rateCommitment, uint32 index);

    /// @notice the modifier to check if the idCommitment is valid
    /// @param idCommitment The idCommitment of the member
    modifier onlyValidIdCommitment(uint256 idCommitment) {
        if (!isValidCommitment(idCommitment)) revert InvalidIdCommitment(idCommitment);
        _;
    }

    modifier noDuplicateMembers(uint256 idCommitment) {
        if (members[idCommitment].userMessageLimit != 0) revert DuplicateIdCommitment();
        _;
    }

    constructor() {
        _disableInitializers();
    }

    /// @dev contract initializer
    /// @param _priceCalculator Address of an instance of IPriceCalculator
    /// @param _maxTotalRateLimitPerEpoch Maximum total rate limit of all memberships in the tree
    /// @param _minRateLimitPerMembership Minimum rate limit of one membership
    /// @param _maxRateLimitPerMembership Maximum rate limit of one membership
    /// @param _expirationTerm Membership expiration term
    /// @param _gracePeriod Membership grace period
    function initialize(
        address _priceCalculator,
        uint32 _maxTotalRateLimitPerEpoch,
        uint32 _minRateLimitPerMembership,
        uint32 _maxRateLimitPerMembership,
        uint32 _expirationTerm,
        uint32 _gracePeriod
    )
        public
        initializer
    {
        __Ownable_init();
        __UUPSUpgradeable_init();
        __MembershipUpgradeable_init(
            _priceCalculator,
            _maxTotalRateLimitPerEpoch,
            _minRateLimitPerMembership,
            _maxRateLimitPerMembership,
            _expirationTerm,
            _gracePeriod
        );

        SET_SIZE = uint32(1 << DEPTH);
        deployedBlockNumber = uint32(block.number);
        LazyIMT.init(imtData, DEPTH);
        nextCommitmentIndex = 0;
    }

    function _authorizeUpgrade(address newImplementation) internal override onlyOwner { } // solhint-disable-line

    /// @notice Checks if a commitment is valid
    /// @param idCommitment The idCommitment of the member
    /// @return true if the commitment is valid, false otherwise
    function isValidCommitment(uint256 idCommitment) public pure returns (bool) {
        return idCommitment != 0 && idCommitment < Q;
    }

    /// @notice Returns the rateCommitment of a member
    /// @param index The index of the member
    /// @return The rateCommitment of the member
    function indexToCommitment(uint32 index) internal view returns (uint256) {
        return imtData.elements[LazyIMT.indexForElement(0, index)];
    }

    /// @notice Returns the metadata of a member
    /// @param idCommitment The idCommitment of the member
    /// @return The metadata of the member (userMessageLimit, index, rateCommitment)
    function idCommitmentToMetadata(uint256 idCommitment) public view returns (uint32, uint32, uint256) {
        MembershipInfo memory member = members[idCommitment];
        // we cannot call indexToCommitment for 0 index if the member doesn't exist
        if (member.userMessageLimit == 0) {
            return (0, 0, 0);
        }
        return (member.userMessageLimit, member.index, indexToCommitment(member.index));
    }

    /// @notice Checks if a member exists
    /// @param idCommitment The idCommitment of the member
    /// @return true if the member exists, false otherwise
    function memberExists(uint256 idCommitment) public view returns (bool) {
        (,, uint256 rateCommitment) = idCommitmentToMetadata(idCommitment);
        return rateCommitment != 0;
    }

    /// @notice Allows a user to register as a member
    /// @param idCommitment The idCommitment of the member
    /// @param userMessageLimit The message limit of the member
    function register(
        uint256 idCommitment,
        uint32 userMessageLimit
    )
        external
        onlyValidIdCommitment(idCommitment)
        noDuplicateMembers(idCommitment)
    {
        uint32 index;
        bool reusedIndex;
        (index, reusedIndex) = _acquireMembership(_msgSender(), idCommitment, userMessageLimit, true);

        _register(idCommitment, userMessageLimit, index, reusedIndex);
    }

    /// @notice Allows a user to register as a member
    /// @param idCommitment The idCommitment of the member
    /// @param userMessageLimit The message limit of the member
    /// @param membershipsToErase List of expired idCommitments to erase
    function register(
        uint256 idCommitment,
        uint32 userMessageLimit,
        uint256[] calldata membershipsToErase
    )
        external
        onlyValidIdCommitment(idCommitment)
        noDuplicateMembers(idCommitment)
    {
        for (uint256 i = 0; i < membershipsToErase.length; i++) {
            uint256 idCommitmentToErase = membershipsToErase[i];
            MembershipInfo memory mdetails = members[idCommitmentToErase];
            if (mdetails.userMessageLimit == 0) revert InvalidIdCommitment(idCommitmentToErase);
            _eraseMembership(_msgSender(), idCommitmentToErase, mdetails);
            LazyIMT.update(imtData, 0, mdetails.index);
        }

        uint32 index;
        bool reusedIndex;
        (index, reusedIndex) = _acquireMembership(_msgSender(), idCommitment, userMessageLimit, false);

        _register(idCommitment, userMessageLimit, index, reusedIndex);
    }

    /// @dev Registers a member
    /// @param idCommitment The idCommitment of the member
    /// @param userMessageLimit The message limit of the member
    /// @param index Indicates the index in the merkle tree
    /// @param reusedIndex indicates whether we're inserting a new element in the merkle tree or updating a existing
    /// leaf
    function _register(uint256 idCommitment, uint32 userMessageLimit, uint32 index, bool reusedIndex) internal {
        if (nextCommitmentIndex >= SET_SIZE) revert FullTree();

        uint256 rateCommitment = PoseidonT3.hash([idCommitment, userMessageLimit]);
        if (reusedIndex) {
            LazyIMT.update(imtData, rateCommitment, index);
        } else {
            LazyIMT.insert(imtData, rateCommitment);
            nextCommitmentIndex += 1;
        }

        emit MemberRegistered(rateCommitment, index);
    }

    /// @notice Returns the commitments of a range of members
    /// @param startIndex The start index of the range
    /// @param endIndex The end index of the range
    /// @return The commitments of the members
    function getCommitments(uint32 startIndex, uint32 endIndex) public view returns (uint256[] memory) {
        if (startIndex > endIndex) revert InvalidPaginationQuery(startIndex, endIndex);
        if (endIndex > nextCommitmentIndex) revert InvalidPaginationQuery(startIndex, endIndex);

        uint256[] memory commitments = new uint256[](endIndex - startIndex + 1);
        for (uint32 i = startIndex; i <= endIndex; i++) {
            commitments[i - startIndex] = indexToCommitment(i);
        }
        return commitments;
    }

    /// @notice Returns the root of the IMT
    /// @return The root of the IMT
    function root() external view returns (uint256) {
        return LazyIMT.root(imtData, DEPTH);
    }

    /// @notice Returns the merkle proof elements of a given membership
    /// @param index The index of the member
    /// @return The merkle proof elements of the member
    function merkleProofElements(uint40 index) public view returns (uint256[DEPTH] memory) {
        uint256[DEPTH] memory castedProof;
        uint256[] memory proof = LazyIMT.merkleProofElements(imtData, index, DEPTH);
        for (uint8 i = 0; i < DEPTH; i++) {
            castedProof[i] = proof[i];
        }
        return castedProof;
    }

    /// @notice Extend a membership expiration date. Memberships must be on grace period
    /// @param idCommitments list of idcommitments
    function extend(uint256[] calldata idCommitments) external {
        for (uint256 i = 0; i < idCommitments.length; i++) {
            uint256 idCommitment = idCommitments[i];
            _extendMembership(_msgSender(), idCommitment);
        }
    }

    /// @notice Remove expired memberships or owned memberships in grace period.
    /// The user can determine offchain which expired memberships slots
    /// are available, and proceed to free them.
    /// This is also used to erase memberships in grace period if they're
    /// held by the sender. The sender can then withdraw the tokens.
    /// @param idCommitments list of idcommitments of the memberships
    function eraseMemberships(uint256[] calldata idCommitments) external {
        for (uint256 i = 0; i < idCommitments.length; i++) {
            uint256 idCommitment = idCommitments[i];
            MembershipInfo memory mdetails = members[idCommitment];
            if (mdetails.userMessageLimit == 0) revert InvalidIdCommitment(idCommitment);
            _eraseMembership(_msgSender(), idCommitment, mdetails);
            LazyIMT.update(imtData, 0, mdetails.index);
        }
    }

    /// @notice Withdraw any available balance in tokens after a membership is erased.
    /// @param token The address of the token to withdraw. Use 0x000...000 to withdraw ETH
    function withdraw(address token) external {
        _withdraw(_msgSender(), token);
    }

    /// @notice Set the address of the price calculator
    /// @param _priceCalculator new price calculator address
    function setPriceCalculator(address _priceCalculator) external onlyOwner {
        priceCalculator = IPriceCalculator(_priceCalculator);
    }

    /// @notice Set the maximum total rate limit of all memberships in the tree
    /// @param _maxTotalRateLimitPerEpoch new value
    function setMaxTotalRateLimitPerEpoch(uint32 _maxTotalRateLimitPerEpoch) external onlyOwner {
        require(_maxTotalRateLimitPerEpoch >= maxRateLimitPerMembership);
        maxTotalRateLimitPerEpoch = _maxTotalRateLimitPerEpoch;
    }

    /// @notice Set the maximum rate limit of one membership
    /// @param _maxRateLimitPerMembership  new value
    function setMaxRateLimitPerMembership(uint32 _maxRateLimitPerMembership) external onlyOwner {
        require(_maxRateLimitPerMembership >= minRateLimitPerMembership);
        maxRateLimitPerMembership = _maxRateLimitPerMembership;
    }

    /// @notice Set the minimum rate limit of one membership
    /// @param _minRateLimitPerMembership  new value
    function setMinRateLimitPerMembership(uint32 _minRateLimitPerMembership) external onlyOwner {
        require(_minRateLimitPerMembership > 0);
        minRateLimitPerMembership = _minRateLimitPerMembership;
    }

    /// @notice Set the membership expiration term
    /// @param _expirationTerm  new value
    function setExpirationTerm(uint32 _expirationTerm) external onlyOwner {
        require(_expirationTerm > 0);
        expirationTerm = _expirationTerm;
    }

    /// @notice Set the membership grace period
    /// @param _gracePeriod  new value
    function setGracePeriod(uint32 _gracePeriod) external onlyOwner {
        gracePeriod = _gracePeriod;
    }
}
