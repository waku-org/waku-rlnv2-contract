// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import { LazyIMT, LazyIMTData } from "@zk-kit/imt.sol/LazyIMT.sol";
import { PoseidonT3 } from "poseidon-solidity/PoseidonT3.sol";

import { OwnableUpgradeable } from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import { Initializable } from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import { UUPSUpgradeable } from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";

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

contract WakuRlnV2 is Initializable, OwnableUpgradeable, UUPSUpgradeable {
    /// @notice The Field
    uint256 public constant Q =
        21_888_242_871_839_275_222_246_405_745_257_275_088_548_364_400_416_034_343_698_204_186_575_808_495_617;

    /// @notice The max message limit per epoch
    uint32 public MAX_MESSAGE_LIMIT;

    /// @notice The depth of the merkle tree
    uint8 public constant DEPTH = 20;

    /// @notice The size of the merkle tree, i.e 2^depth
    uint32 public SET_SIZE;

    /// @notice The index of the next member to be registered
    uint32 public commitmentIndex;

    /// @notice the membership metadata of the member
    struct MembershipInfo {
        /// @notice the user message limit of each member
        uint32 userMessageLimit;
        /// @notice the index of the member in the set
        uint32 index;
    }

    /// @notice the member metadata
    mapping(uint256 => MembershipInfo) public memberInfo;

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

    /// @notice the modifier to check if the userMessageLimit is valid
    /// @param userMessageLimit The user message limit
    modifier onlyValidUserMessageLimit(uint32 userMessageLimit) {
        if (!isValidUserMessageLimit(userMessageLimit)) revert InvalidUserMessageLimit(userMessageLimit);
        _;
    }

    constructor() {
        _disableInitializers();
    }

    function initialize(address initialOwner, uint32 maxMessageLimit) public initializer {
        __Ownable_init(initialOwner);
        __UUPSUpgradeable_init();
        MAX_MESSAGE_LIMIT = maxMessageLimit;
        SET_SIZE = uint32(1 << DEPTH);
        deployedBlockNumber = uint32(block.number);
        LazyIMT.init(imtData, DEPTH);
        commitmentIndex = 0;
    }

    function _authorizeUpgrade(address newImplementation) internal override onlyOwner { } // solhint-disable-line

    /// @notice Checks if a commitment is valid
    /// @param idCommitment The idCommitment of the member
    /// @return true if the commitment is valid, false otherwise
    function isValidCommitment(uint256 idCommitment) public pure returns (bool) {
        return idCommitment != 0 && idCommitment < Q;
    }

    /// @notice Checks if a user message limit is valid
    /// @param userMessageLimit The user message limit
    /// @return true if the user message limit is valid, false otherwise
    function isValidUserMessageLimit(uint32 userMessageLimit) public view returns (bool) {
        return userMessageLimit > 0 && userMessageLimit <= MAX_MESSAGE_LIMIT;
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
        MembershipInfo memory member = memberInfo[idCommitment];
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

    /// Allows a user to register as a member
    /// @param idCommitment The idCommitment of the member
    /// @param userMessageLimit The message limit of the member
    function register(
        uint256 idCommitment,
        uint32 userMessageLimit
    )
        external
        onlyValidIdCommitment(idCommitment)
        onlyValidUserMessageLimit(userMessageLimit)
    {
        _register(idCommitment, userMessageLimit);
    }

    /// Registers a member
    /// @param idCommitment The idCommitment of the member
    /// @param userMessageLimit The message limit of the member
    function _register(uint256 idCommitment, uint32 userMessageLimit) internal {
        if (memberExists(idCommitment)) revert DuplicateIdCommitment();
        if (commitmentIndex >= SET_SIZE) revert FullTree();

        uint256 rateCommitment = PoseidonT3.hash([idCommitment, userMessageLimit]);
        MembershipInfo memory member = MembershipInfo({ userMessageLimit: userMessageLimit, index: commitmentIndex });
        LazyIMT.insert(imtData, rateCommitment);
        memberInfo[idCommitment] = member;

        emit MemberRegistered(rateCommitment, commitmentIndex);
        commitmentIndex += 1;
    }

    /// @notice Returns the commitments of a range of members
    /// @param startIndex The start index of the range
    /// @param endIndex The end index of the range
    /// @return The commitments of the members
    function getCommitments(uint32 startIndex, uint32 endIndex) public view returns (uint256[] memory) {
        if (startIndex > endIndex) revert InvalidPaginationQuery(startIndex, endIndex);
        if (endIndex > commitmentIndex) revert InvalidPaginationQuery(startIndex, endIndex);

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
}
