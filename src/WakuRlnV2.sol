// SPDX-License-Identifier: MIT

pragma solidity 0.8.19;

import { LazyIMT, LazyIMTData } from "@zk-kit/imt.sol/LazyIMT.sol";
import { PoseidonT3 } from "poseidon-solidity/PoseidonT3.sol";

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

contract WakuRlnV2 {
    /// @notice The Field
    uint256 public constant Q =
        21_888_242_871_839_275_222_246_405_745_257_275_088_548_364_400_416_034_343_698_204_186_575_808_495_617;

    /// @notice The max message limit per epoch
    uint32 public immutable MAX_MESSAGE_LIMIT;

    /// @notice The depth of the merkle tree
    uint8 public constant DEPTH = 20;

    /// @notice The size of the merkle tree, i.e 2^depth
    uint32 public immutable SET_SIZE;

    /// @notice The index of the next member to be registered
    uint32 public idCommitmentIndex = 0;

    struct MembershipInfo {
        /// @notice the user message limit of each member
        uint32 userMessageLimit;
        /// @notice the index of the member in the set
        uint32 index;
    }

    /// @notice the member metadata
    mapping(uint256 => MembershipInfo) public memberInfo;

    /// @notice the deployed block number
    uint32 public immutable deployedBlockNumber;

    /// @notice the stored imt data
    LazyIMTData public imtData;

    /// Emitted when a new member is added to the set
    /// @param idCommitment The idCommitment of the member
    /// @param userMessageLimit the user message limit of the member
    /// @param index The index of the member in the set
    event MemberRegistered(uint256 idCommitment, uint32 userMessageLimit, uint32 index);

    modifier onlyValidIdCommitment(uint256 idCommitment) {
        if (!isValidCommitment(idCommitment)) revert InvalidIdCommitment(idCommitment);
        _;
    }

    modifier onlyValidUserMessageLimit(uint32 messageLimit) {
        if (messageLimit > MAX_MESSAGE_LIMIT) revert InvalidUserMessageLimit(messageLimit);
        if (messageLimit == 0) revert InvalidUserMessageLimit(messageLimit);
        _;
    }

    constructor(uint32 maxMessageLimit) {
        MAX_MESSAGE_LIMIT = maxMessageLimit;
        SET_SIZE = uint32(1 << DEPTH);
        deployedBlockNumber = uint32(block.number);
        LazyIMT.init(imtData, DEPTH);
    }

    function memberExists(uint256 idCommitment) public view returns (bool) {
        MembershipInfo memory member = memberInfo[idCommitment];
        return member.userMessageLimit > 0 && member.index >= 0;
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
        if (idCommitmentIndex >= SET_SIZE) revert FullTree();

        uint256 rateCommitment = PoseidonT3.hash([idCommitment, userMessageLimit]);
        MembershipInfo memory member = MembershipInfo({ userMessageLimit: userMessageLimit, index: idCommitmentIndex });
        LazyIMT.insert(imtData, rateCommitment);
        memberInfo[idCommitment] = member;

        emit MemberRegistered(idCommitment, userMessageLimit, idCommitmentIndex);
        idCommitmentIndex += 1;
    }

    function isValidCommitment(uint256 idCommitment) public pure returns (bool) {
        return idCommitment != 0 && idCommitment < Q;
    }

    function indexToCommitment(uint32 index) public view returns (uint256) {
        return imtData.elements[LazyIMT.indexForElement(0, index)];
    }

    function getCommitments(uint32 startIndex, uint32 endIndex) public view returns (uint256[] memory) {
        if (startIndex >= endIndex) revert InvalidPaginationQuery(startIndex, endIndex);
        if (endIndex > idCommitmentIndex) revert InvalidPaginationQuery(startIndex, endIndex);

        uint256[] memory commitments = new uint256[](endIndex - startIndex);
        for (uint32 i = startIndex; i < endIndex; i++) {
            commitments[i - startIndex] = indexToCommitment(i);
        }
        return commitments;
    }

    function root() external view returns (uint256) {
        return LazyIMT.root(imtData, DEPTH);
    }

    function merkleProofElements(uint40 index) public view returns (uint256[] memory) {
        return LazyIMT.merkleProofElements(imtData, index, DEPTH);
    }
}
