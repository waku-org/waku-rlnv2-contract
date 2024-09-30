// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import { IPriceCalculator } from "./IPriceCalculator.sol";
import { IERC20 } from "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import { SafeERC20 } from "openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";
import { Initializable } from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";

// The specified rate limit was not correct or within the expected limits
error InvalidMembershipRateLimit();

// It's not possible to acquire the rate limit due to exceeding the expected limits
// even after attempting to erase expired memberships
error ExceededMaxTotalRateLimit();

// This membership is not in grace period
error NotInGracePeriod(uint256 idCommitment);

// The sender is not the holder of the membership
error AttemptedExtensionByNonHolder(uint256 idCommitment);

// This membership cannot be erased
error CannotEraseMembership(uint256 idCommitment);

abstract contract MembershipUpgradeable is Initializable {
    using SafeERC20 for IERC20;

    /// @notice Address of the Price Calculator used to calculate the price of a new membership
    IPriceCalculator public depositAmountCalculator;

    /// @notice Maximum total rate limit of all memberships in the membership set (messages per epoch)
    uint32 public maxTotalRateLimit;

    /// @notice Maximum rate limit of one membership
    uint32 public maxMembershipRateLimit;

    /// @notice Minimum rate limit of one membership
    uint32 public minMembershipRateLimit;

    /// @notice Membership active period duration (A in the spec)
    uint32 public activeStateDuration;

    /// @notice Membership grace period duration (G in the spec)
    uint32 public gracePeriodDurationForNewMemberships;

    /// @notice deposits available for withdrawal
    /// Deposits unavailable for withdrawal are stored in MembershipInfo.
    mapping(address holder => mapping(address token => uint256 balance)) public depositsToWithdraw;

    /// @notice Current total rate limit of all memberships in the membership set (messages per epoch)
    uint256 public totalRateLimit;

    /// @notice List of memberships in the membership set
    mapping(uint256 idCommitment => MembershipInfo membership) public memberships;

    /// @notice The index in the membership set for the next membership to be registered
    uint32 public nextFreeIndex;

    /// @notice indices of memberships (expired or grace-period marked for erasure) that can be reused
    uint32[] public reusableIndicesOfErasedMemberships;

    struct MembershipInfo {
        /// @notice deposit amount (in tokens) to register this membership
        uint256 depositAmount;
        /// @notice timestamp of when the grace period starts for this membership
        uint256 gracePeriodStartTimestamp;
        /// @notice duration of the grace period for this membership
        uint32 gracePeriodDuration;
        /// @notice the membership rate limit
        uint32 rateLimit;
        /// @notice the index of the membership in the membership set
        uint32 index;
        /// @notice address of the holder of this membership
        address holder;
        /// @notice token used to make the deposit to register this membership
        address token;
    }

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
    /// @param _activeStateDuration Active state duration of each membership
    /// @param _gracePeriodDuration Grace period duration of each membership
    function __MembershipUpgradeable_init(
        address _priceCalculator,
        uint32 _maxTotalRateLimit,
        uint32 _minMembershipRateLimit,
        uint32 _maxMembershipRateLimit,
        uint32 _activeStateDuration,
        uint32 _gracePeriodDuration
    )
        internal
        onlyInitializing
    {
        __MembershipUpgradeable_init_unchained(
            _priceCalculator,
            _maxTotalRateLimit,
            _minMembershipRateLimit,
            _maxMembershipRateLimit,
            _activeStateDuration,
            _gracePeriodDuration
        );
    }

    function __MembershipUpgradeable_init_unchained(
        address _priceCalculator,
        uint32 _maxTotalRateLimit,
        uint32 _minMembershipRateLimit,
        uint32 _maxMembershipRateLimit,
        uint32 _activeStateDuration,
        uint32 _gracePeriodDuration
    )
        internal
        onlyInitializing
    {
        require(0 < _minMembershipRateLimit);
        require(_minMembershipRateLimit <= _maxMembershipRateLimit);
        require(_maxMembershipRateLimit <= _maxTotalRateLimit);
        require(_activeStateDuration > 0);
        // Note: grace period duration may be equal to zero

        depositAmountCalculator = IPriceCalculator(_priceCalculator);
        maxTotalRateLimit = _maxTotalRateLimit;
        minMembershipRateLimit = _minMembershipRateLimit;
        maxMembershipRateLimit = _maxMembershipRateLimit;
        activeStateDuration = _activeStateDuration;
        gracePeriodDurationForNewMemberships = _gracePeriodDuration;
    }

    /// @notice Checks if a rate limit is within the allowed bounds
    /// @param rateLimit The rate limit
    /// @return true if the rate limit is within the allowed bounds, false otherwise
    function isValidMembershipRateLimit(uint32 rateLimit) public view returns (bool) {
        return minMembershipRateLimit <= rateLimit && rateLimit <= maxMembershipRateLimit;
    }

    /// @dev acquire a membership and trasnfer the deposit to the contract
    /// @param _sender address of the holder of the new membership  // FIXME: keeper?
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

        // Determine if we exceed the total rate limit
        totalRateLimit += _rateLimit;
        if (totalRateLimit > maxTotalRateLimit) {
            revert ExceededMaxTotalRateLimit();
        }

        (address token, uint256 depositAmount) = depositAmountCalculator.calculate(_rateLimit);

        // Possibly reuse an index of an available erased membership
        (index, indexReused) = _getFreeIndex();

        memberships[_idCommitment] = MembershipInfo({
            holder: _sender, // FIXME: keeper?
            gracePeriodStartTimestamp: block.timestamp + uint256(activeStateDuration),
            gracePeriodDuration: gracePeriodDurationForNewMemberships,
            token: token,
            depositAmount: depositAmount,
            rateLimit: _rateLimit,
            index: index
        });

        IERC20(token).safeTransferFrom(_sender, address(this), depositAmount);
    }

    /// @dev Get a free index (possibly from reusing an index of an erased membership)
    /// @return index index to be used for another membership registration
    /// @return indexReused indicates whether index was reused from an erased membership
    function _getFreeIndex() internal returns (uint32 index, bool indexReused) {
        // Reuse the last erased membership
        uint256 numIndices = reusableIndicesOfErasedMemberships.length;
        if (numIndices != 0) {
            index = reusableIndicesOfErasedMemberships[numIndices - 1];
            reusableIndicesOfErasedMemberships.pop();
            indexReused = true;
        } else {
            index = nextFreeIndex;
        }
    }

    /// @dev Extend the expiration date of a grace-period membership
    /// @param _sender the address of the holder of the membership
    /// @param _idCommitment the idCommitment of the membership
    function _extendMembership(address _sender, uint256 _idCommitment) public {
        MembershipInfo storage membership = memberships[_idCommitment];

        if (!_isInGracePeriod(membership.gracePeriodStartTimestamp, membership.gracePeriodDuration)) {
            revert NotInGracePeriod(_idCommitment);
        }

        if (_sender != membership.holder) revert AttemptedExtensionByNonHolder(_idCommitment);

        // Note: we add the new active period to the end of the ongoing grace period
        uint256 newGracePeriodStartTimestamp = (
            membership.gracePeriodStartTimestamp + membership.gracePeriodDuration
            // FIXME: we must use this membership's activeStateDuration, not global default
            + uint256(activeStateDuration)
        );

        membership.gracePeriodStartTimestamp = newGracePeriodStartTimestamp;

        emit MembershipExtended(
            _idCommitment, membership.rateLimit, membership.index, membership.gracePeriodStartTimestamp
        );
    }

    /// @dev Determine whether a grace period has passed (the membership is expired)
    /// @param _gracePeriodStartTimestamp timestamp in which the grace period starts
    /// @param _gracePeriodDuration duration of the grace period
    function _isExpired(uint256 _gracePeriodStartTimestamp, uint32 _gracePeriodDuration) internal view returns (bool) {
        return block.timestamp > _gracePeriodStartTimestamp + uint256(_gracePeriodDuration);
    }

    /// @notice Determine if a membership is expired
    /// @param _idCommitment the idCommitment of the membership
    function isExpired(uint256 _idCommitment) public view returns (bool) {
        MembershipInfo memory membership = memberships[_idCommitment];
        return _isExpired(membership.gracePeriodStartTimestamp, membership.gracePeriodDuration);
    }

    /// @notice Returns the timestamp on which a membership can be considered expired
    /// @param _idCommitment the idCommitment of the membership
    function membershipExpirationTimestamp(uint256 _idCommitment) public view returns (uint256) {
        MembershipInfo memory membership = memberships[_idCommitment];
        return membership.gracePeriodStartTimestamp + uint256(membership.gracePeriodDuration) + 1;
    }

    /// @dev Determine whether the current timestamp is in a given grace period
    /// @param _gracePeriodStartTimestamp timestamp in which the grace period starts
    /// @param _gracePeriodDuration duration of the grace period
    function _isInGracePeriod(
        uint256 _gracePeriodStartTimestamp,
        uint32 _gracePeriodDuration
    )
        internal
        view
        returns (bool)
    {
        uint256 timeNow = block.timestamp;
        return (
            _gracePeriodStartTimestamp <= timeNow
                && timeNow <= _gracePeriodStartTimestamp + uint256(_gracePeriodDuration)
        );
    }

    /// @notice Determine if a membership is in grace period now
    /// @param _idCommitment the idCommitment of the membership
    function isInGracePeriod(uint256 _idCommitment) public view returns (bool) {
        MembershipInfo memory membership = memberships[_idCommitment];
        return _isInGracePeriod(membership.gracePeriodStartTimestamp, membership.gracePeriodDuration);
    }

    /// @dev Erase expired memberships or owned grace-period memberships.
    /// @param _sender address of the sender of transaction (will be used to check memberships in grace period)
    /// @param _idCommitment idCommitment of the membership to erase
    function _eraseMembershipAndSaveSlotToReuse(
        address _sender,
        uint256 _idCommitment,
        MembershipInfo memory _membership
    )
        internal
    {
        bool membershipExpired = _isExpired(_membership.gracePeriodStartTimestamp, _membership.gracePeriodDuration);
        bool membershipIsInGracePeriod =
            _isInGracePeriod(_membership.gracePeriodStartTimestamp, _membership.gracePeriodDuration);
        bool isHolder = (_membership.holder == _sender);

        if (!membershipExpired && !(membershipIsInGracePeriod && isHolder)) {
            revert CannotEraseMembership(_idCommitment);
        }

        // Move deposit balance from the membership to be erased to holder deposit balance
        depositsToWithdraw[_membership.holder][_membership.token] += _membership.depositAmount;

        // Deduct the rate limit of this membership from the total rate limit
        totalRateLimit -= _membership.rateLimit;

        // Mark this membership as reusable
        reusableIndicesOfErasedMemberships.push(_membership.index);

        // Erase this membership from the memberships mapping
        // Note: the Merkle tree data will be erased when the index is reused
        delete memberships[_idCommitment];

        if (membershipExpired) {
            emit MembershipExpired(_idCommitment, _membership.rateLimit, _membership.index);
        }
        emit MembershipErased(_idCommitment, _membership.rateLimit, _membership.index);
    }

    /// @dev Withdraw any available deposit balance in tokens after a membership is erased.
    /// @param _sender the address of the owner of the tokens
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
