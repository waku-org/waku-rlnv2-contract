// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import { IPriceCalculator } from "./IPriceCalculator.sol";
import { IERC20 } from "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import { SafeERC20 } from "openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";
import { Initializable } from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";

// The rate limit is outside the expected limits
error InvalidMembershipRateLimit();

// Cannot acquire the rate limit for a new membership due to exceeding the expected limits
// even after attempting to erase expired memberships
error ExceededMaxTotalRateLimit();

// This membership is not in its grace period
error NotInGracePeriod(uint256 idCommitment);

// The sender is not the holder of this membership
error AttemptedExtensionByNonHolder(uint256 idCommitment);

// This membership cannot be erased
error CannotEraseMembership(uint256 idCommitment);

// This membership does not exist
error MembershipDoesNotExist(uint256 idCommitment);

abstract contract MembershipUpgradeable is Initializable {
    using SafeERC20 for IERC20;

    /// @notice Address of the Price Calculator used to calculate the price of a new membership
    IPriceCalculator public priceCalculator;

    /// @notice Maximum total rate limit of all memberships in the membership set (messages per epoch)
    uint32 public maxTotalRateLimit;

    /// @notice Maximum rate limit of one membership
    uint32 public maxMembershipRateLimit;

    /// @notice Minimum rate limit of one membership
    uint32 public minMembershipRateLimit;

    /// @notice Membership active period duration (A in the spec)
    uint32 public activeDurationForNewMemberships;

    /// @notice Membership grace period duration (G in the spec)
    uint32 public gracePeriodDurationForNewMemberships;

    /// @notice Deposits available for withdrawal
    /// Note: amount of deposits unavailable for withdrawal are stored in MembershipInfo elements.
    mapping(address holder => mapping(address token => uint256 balance)) public depositsToWithdraw;

    /// @notice Current total rate limit of all memberships in the membership set (messages per epoch)
    uint256 public currentTotalRateLimit;

    /// @notice List of memberships in the membership set
    mapping(uint256 idCommitment => MembershipInfo membership) public memberships;

    /// @notice The index in the membership set for the next membership to be registered
    uint32 public nextFreeIndex;

    /// @notice Indices of erased memberships that can be reused for new registrations
    uint32[] public indicesOfLazilyErasedMemberships;

    struct MembershipInfo {
        /// @notice the deposit amount (in tokens) to register this membership
        uint256 depositAmount;
        /// @notice the duration of the active period of this membership
        uint32 activeDuration;
        /// @notice the start of the grace period (= the end of the active period)
        uint256 gracePeriodStartTimestamp;
        /// @notice the duration of the grace period of this membership
        uint32 gracePeriodDuration;
        /// @notice the membership rate limit
        uint32 rateLimit;
        /// @notice the index of the membership in the membership set
        uint32 index;
        /// @notice the address of the holder of this membership
        address holder;
        /// @notice the token used to make the deposit to register this membership
        address token;
    }

    /// Emitted when a new membership is added to the membership set // FIXME: rateCommitment or membershipRateLimit?
    /// @param rateCommitment The rateCommitment of the membership
    /// @param index The index of the membership in the membership set
    event MembershipRegistered(uint256 idCommitment, uint256 rateCommitment, uint32 index);

    /// @notice Emitted when a membership is expired (exceeded its grace period and not extended)
    /// @param idCommitment the idCommitment of the membership
    /// @param membershipRateLimit the rate limit of this membership
    /// @param index the index of the membership in the membership set
    event MembershipExpired(uint256 idCommitment, uint32 membershipRateLimit, uint32 index);

    /// @notice Emitted when a membership is erased by its holder during grace period
    /// @param idCommitment the idCommitment of the membership
    /// @param membershipRateLimit the rate limit of this membership
    /// @param index the index of the membership in the membership set
    event MembershipErased(uint256 idCommitment, uint32 membershipRateLimit, uint32 index);

    /// @notice Emitted when a membership in its grace period is extended (i.e., is back to Active state)
    /// @param idCommitment the idCommitment of the membership
    /// @param membershipRateLimit the rate limit of this membership
    /// @param index the index of the membership in the membership set
    /// @param newGracePeriodStartTimestamp the new grace period start timestamp of this membership
    event MembershipExtended(
        uint256 idCommitment, uint32 membershipRateLimit, uint32 index, uint256 newGracePeriodStartTimestamp
    );

    /// @dev contract initializer
    /// @param _priceCalculator Address of an instance of IPriceCalculator
    /// @param _maxTotalRateLimit Maximum total rate limit of all memberships in the membership set
    /// @param _minMembershipRateLimit Minimum rate limit of each membership
    /// @param _maxMembershipRateLimit Maximum rate limit of each membership
    /// @param _activeDurationForNewMemberships Active state duration of each membership
    /// @param _gracePeriodDurationForNewMemberships Grace period duration of each membership
    function __MembershipUpgradeable_init(
        address _priceCalculator,
        uint32 _maxTotalRateLimit,
        uint32 _minMembershipRateLimit,
        uint32 _maxMembershipRateLimit,
        uint32 _activeDurationForNewMemberships,
        uint32 _gracePeriodDurationForNewMemberships
    )
        internal
        onlyInitializing
    {
        __MembershipUpgradeable_init_unchained(
            _priceCalculator,
            _maxTotalRateLimit,
            _minMembershipRateLimit,
            _maxMembershipRateLimit,
            _activeDurationForNewMemberships,
            _gracePeriodDurationForNewMemberships
        );
    }

    function __MembershipUpgradeable_init_unchained(
        address _priceCalculator,
        uint32 _maxTotalRateLimit,
        uint32 _minMembershipRateLimit,
        uint32 _maxMembershipRateLimit,
        uint32 _activeDurationForNewMemberships,
        uint32 _gracePeriodDurationForNewMemberships
    )
        internal
        onlyInitializing
    {
        require(0 < _minMembershipRateLimit);
        require(_minMembershipRateLimit <= _maxMembershipRateLimit);
        require(_maxMembershipRateLimit <= _maxTotalRateLimit);
        require(_activeDurationForNewMemberships > 0);
        // Note: grace period duration may be equal to zero

        priceCalculator = IPriceCalculator(_priceCalculator);
        maxTotalRateLimit = _maxTotalRateLimit;
        minMembershipRateLimit = _minMembershipRateLimit;
        maxMembershipRateLimit = _maxMembershipRateLimit;
        activeDurationForNewMemberships = _activeDurationForNewMemberships;
        gracePeriodDurationForNewMemberships = _gracePeriodDurationForNewMemberships;
    }

    /// @dev acquire a membership and trasnfer the deposit to the contract
    /// @param _sender the address of the transaction sender
    /// @param _idCommitment the idCommitment of the new membership
    /// @param _rateLimit the membership rate limit
    /// @return index the index of the new membership in the membership set
    /// @return indexReused true if the index was reused, false otherwise
    function _acquireMembership(
        address _sender,
        uint256 _idCommitment,
        uint32 _rateLimit
    )
        internal
        returns (uint32 index, bool indexReused)
    {
        // Check if the rate limit is valid
        if (!isValidMembershipRateLimit(_rateLimit)) {
            revert InvalidMembershipRateLimit();
        }

        currentTotalRateLimit += _rateLimit;

        // Determine if we exceed the total rate limit
        if (currentTotalRateLimit > maxTotalRateLimit) {
            revert ExceededMaxTotalRateLimit();
        }

        (address token, uint256 depositAmount) = priceCalculator.calculate(_rateLimit);

        // Possibly reuse an index of an erased membership
        (index, indexReused) = _getFreeIndex();

        memberships[_idCommitment] = MembershipInfo({
            holder: _sender,
            activeDuration: activeDurationForNewMemberships,
            gracePeriodStartTimestamp: block.timestamp + uint256(activeDurationForNewMemberships),
            gracePeriodDuration: gracePeriodDurationForNewMemberships,
            token: token,
            depositAmount: depositAmount,
            rateLimit: _rateLimit,
            index: index
        });

        IERC20(token).safeTransferFrom(_sender, address(this), depositAmount);
    }

    /// @notice Checks if a rate limit is within the allowed bounds
    /// @param rateLimit The rate limit
    /// @return true if the rate limit is within the allowed bounds, false otherwise
    function isValidMembershipRateLimit(uint32 rateLimit) public view returns (bool) {
        return minMembershipRateLimit <= rateLimit && rateLimit <= maxMembershipRateLimit;
    }

    /// @dev Get a free index (possibly reuse an index of an erased membership)
    /// @return index index to be used for the new membership registration
    /// @return indexReused indicates whether the index was reused from an erased membership
    function _getFreeIndex() internal returns (uint32 index, bool indexReused) {
        uint256 numIndices = indicesOfLazilyErasedMemberships.length;
        if (numIndices != 0) {
            // Reuse the index of the latest erased membership
            index = indicesOfLazilyErasedMemberships[numIndices - 1];
            indicesOfLazilyErasedMemberships.pop();
            indexReused = true;
        } else {
            index = nextFreeIndex;
        }
    }

    /// @dev Extend a grace-period membership
    /// @param _sender the address of the transaction sender
    /// @param _idCommitment the idCommitment of the membership
    function _extendMembership(address _sender, uint256 _idCommitment) public {
        MembershipInfo storage membership = memberships[_idCommitment];

        if (!_isInPeriod(membership.gracePeriodStartTimestamp, membership.gracePeriodDuration)) {
            revert NotInGracePeriod(_idCommitment);
        }

        if (_sender != membership.holder) revert AttemptedExtensionByNonHolder(_idCommitment);

        // Note: we add the new active period to the end of the ongoing grace period
        uint256 newGracePeriodStartTimestamp =
            (membership.gracePeriodStartTimestamp + membership.gracePeriodDuration + uint256(membership.activeDuration));

        membership.gracePeriodStartTimestamp = newGracePeriodStartTimestamp;

        emit MembershipExtended(
            _idCommitment, membership.rateLimit, membership.index, membership.gracePeriodStartTimestamp
        );
    }

    /// @dev Erase expired memberships or owned grace-period memberships.
    /// @param _sender the address of the transaction sender
    /// @param _idCommitment idCommitment of the membership to erase
    function _eraseMembershipLazily(address _sender, uint256 _idCommitment) internal returns (uint32 index) {
        MembershipInfo memory membership = memberships[_idCommitment];

        if (membership.rateLimit == 0) revert MembershipDoesNotExist(_idCommitment);

        bool membershipExpired = _isAfterPeriod(membership.gracePeriodStartTimestamp, membership.gracePeriodDuration);
        bool membershipIsInGracePeriod =
            _isInPeriod(membership.gracePeriodStartTimestamp, membership.gracePeriodDuration);
        bool isHolder = (membership.holder == _sender);

        if (!membershipExpired && !(membershipIsInGracePeriod && isHolder)) {
            revert CannotEraseMembership(_idCommitment);
        }

        // Move deposit balance from the membership to be erased to holder deposit balance
        depositsToWithdraw[membership.holder][membership.token] += membership.depositAmount;

        // Deduct the rate limit of this membership from the total rate limit
        currentTotalRateLimit -= membership.rateLimit;

        // Mark this membership as reusable
        indicesOfLazilyErasedMemberships.push(membership.index);

        // Erase this membership from the memberships mapping
        delete memberships[_idCommitment];

        if (membershipExpired) {
            emit MembershipExpired(_idCommitment, membership.rateLimit, membership.index);
        }
        emit MembershipErased(_idCommitment, membership.rateLimit, membership.index);

        // This index will be used to erase the data from the Merkle tree that represents the membership set
        return membership.index;
    }

    /// @notice Determine if a membership is in its grace period
    /// @param _idCommitment the idCommitment of the membership
    function isInGracePeriod(uint256 _idCommitment) public view returns (bool) {
        MembershipInfo memory membership = memberships[_idCommitment];
        return _isInPeriod(membership.gracePeriodStartTimestamp, membership.gracePeriodDuration);
    }

    /// @dev Determine whether the current timestamp is within a given period
    /// @param _start timestamp in which the period starts
    /// @param _duration duration of the period
    function _isInPeriod(uint256 _start, uint32 _duration) internal view returns (bool) {
        uint256 timeNow = block.timestamp;
        return (_start <= timeNow && timeNow <= _start + uint256(_duration));
    }

    /// @notice Determine if a membership is expired
    /// @param _idCommitment the idCommitment of the membership
    function isExpired(uint256 _idCommitment) public view returns (bool) {
        MembershipInfo memory membership = memberships[_idCommitment];
        return _isAfterPeriod(membership.gracePeriodStartTimestamp, membership.gracePeriodDuration);
    }

    /// @dev Determine whether the current timestamp is after a given period
    /// @param _start timestamp in which the period starts
    /// @param _duration duration of the period
    function _isAfterPeriod(uint256 _start, uint32 _duration) internal view returns (bool) {
        uint256 timeNow = block.timestamp;
        return (_start + uint256(_duration) < timeNow);
    }

    /// @notice Returns the timestamp on which a membership can be considered expired (i.e. when its grace period ends)
    /// @param _idCommitment the idCommitment of the membership
    function membershipExpirationTimestamp(uint256 _idCommitment) public view returns (uint256) {
        MembershipInfo memory membership = memberships[_idCommitment];
        return _timestampAfterPeriod(membership.gracePeriodStartTimestamp, membership.gracePeriodDuration);
    }

    /// @dev Returns the first timestamp after a specified period
    /// @param _start timestamp in which the period starts
    /// @param _duration duration of the period
    function _timestampAfterPeriod(uint256 _start, uint32 _duration) internal pure returns (uint256) {
        return _start + uint256(_duration) + 1;
    }

    /// @dev Withdraw any available deposit balance in tokens after a membership is erased.
    /// @param _sender the address of the transaction sender (who withdraws their tokens)
    /// @param _token the address of the token to withdraw
    function _withdraw(address _sender, address _token) internal {
        require(_token != address(0), "ETH is not allowed");

        uint256 amount = depositsToWithdraw[_sender][_token];
        require(amount > 0, "Insufficient deposit balance");

        depositsToWithdraw[_sender][_token] = 0;
        IERC20(_token).safeTransfer(_sender, amount);
    }

    /**
     * @dev This empty reserved space is put in place to allow future versions to add new
     * variables without shifting down storage in the inheritance chain.
     * See https://docs.openzeppelin.com/contracts/4.x/upgradeable#storage_gaps
     */
    uint256[50] private __gap;
}
