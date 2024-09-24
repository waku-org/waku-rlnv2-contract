// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import { IPriceCalculator } from "./IPriceCalculator.sol";
import { IERC20 } from "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import { SafeERC20 } from "openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";
import { Initializable } from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";

// The specified rate limit was not correct or within the expected limits
error InvalidRateLimit();

// It's not possible to acquire the rate limit due to exceeding the expected limits
// even after attempting to erase expired memberships
error ExceededMaxTotalRateLimit();

// This membership is not in grace period yet // FIXME: yet or also already?
error NotInGracePeriod(uint256 idCommitment);

// The sender is not the holder of the membership
error AttemptedExtensionByNonHolder(uint256 idCommitment);

// This membership cannot be erased (either it is not expired or not in grace period and/or not the owner) // FIXME:
// separate into two errors?
error CantEraseMembership(uint256 idCommitment);

abstract contract MembershipUpgradeable is Initializable {
    using SafeERC20 for IERC20;

    /// @notice Address of the Price Calculator used to calculate the price of a new membership
    IPriceCalculator public priceCalculator; // FIXME: naming: price vs deposit?

    /// @notice Maximum total rate limit of all memberships in the membership set (messages per epoch)
    uint32 public maxTotalRateLimit;

    /// @notice Maximum rate limit of one membership
    uint32 public maxMembershipRateLimit;

    /// @notice Minimum rate limit of one membership
    uint32 public minMembershipRateLimit;

    /// @notice Membership expiration term (T in the spec)
    uint32 public expirationTerm;

    /// @notice Membership grace period (G in the spec)
    uint32 public gracePeriodDuration;

    /// @notice deposit balances available to withdraw  // FIXME: are balances unavailable for withdrawal stored
    /// elsewhere?
    mapping(address holder => mapping(address token => uint256 balance)) public balancesToWithdraw;

    /// @notice Total rate limit of all memberships in the membership set (messages per epoch)
    uint256 public totalRateLimit;

    /// @notice List of registered memberships
    mapping(uint256 idCommitment => MembershipInfo membership) public memberships;

    /// @notice The index in the membership set for the next membership to be registered
    uint32 public nextFreeIndex;

    /// @notice indices of expired memberships (can be erased)
    uint32[] public availableExpiredMembershipsIndices;

    struct MembershipInfo {
        /// @notice amount of the token used to make the deposit to register this membership
        uint256 depositAmount;
        /// @notice timestamp of when the grace period starts for this membership
        uint256 gracePeriodStartTimestamp;
        /// @notice duration of the grace period
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

    /// @notice Emitted when a membership is erased due to having exceeded the grace period or the owner having chosen
    /// to not extend it // FIXME: expired or erased?
    /// @param idCommitment the idCommitment of the membership
    /// @param membershipRateLimit the rate limit of this membership
    /// @param index the index of the membership in the membership set
    event MembershipExpired(uint256 idCommitment, uint32 membershipRateLimit, uint32 index);

    /// @notice Emitted when a membership in its grace period is extended
    /// @param idCommitment the idCommitment of the membership
    /// @param membershipRateLimit the rate limit of this membership
    /// @param index the index of the membership in the membership set
    /// @param newExpirationTime the new expiration timestamp of this membership
    event MembershipExtended(uint256 idCommitment, uint32 membershipRateLimit, uint32 index, uint256 newExpirationTime);

    /// @dev contract initializer
    /// @param _priceCalculator Address of an instance of IPriceCalculator
    /// @param _maxTotalRateLimit Maximum total rate limit of all memberships in the membership set
    /// @param _minMembershipRateLimit Minimum rate limit of each membership
    /// @param _maxMembershipRateLimit Maximum rate limit of each membership
    /// @param _expirationTerm Expiration term of each membership
    /// @param _gracePeriodDuration Grace period duration for each membership
    function __MembershipUpgradeable_init(
        address _priceCalculator,
        uint32 _maxTotalRateLimit,
        uint32 _minMembershipRateLimit,
        uint32 _maxMembershipRateLimit,
        uint32 _expirationTerm,
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
            _expirationTerm,
            _gracePeriodDuration
        );
    }

    function __MembershipUpgradeable_init_unchained(
        address _priceCalculator,
        uint32 _maxTotalRateLimit,
        uint32 _minMembershipRateLimit,
        uint32 _maxMembershipRateLimit,
        uint32 _expirationTerm,
        uint32 _gracePeriodDuration
    )
        internal
        onlyInitializing
    {
        require(_maxTotalRateLimit >= maxMembershipRateLimit);
        require(_maxMembershipRateLimit > minMembershipRateLimit); // FIXME: > or >=?
        require(_minMembershipRateLimit > 0);
        require(_expirationTerm > 0); // FIXME: also _gracePeriodDuration > 0?

        priceCalculator = IPriceCalculator(_priceCalculator);
        maxTotalRateLimit = _maxTotalRateLimit;
        maxMembershipRateLimit = _maxMembershipRateLimit;
        minMembershipRateLimit = _minMembershipRateLimit;
        expirationTerm = _expirationTerm;
        gracePeriodDuration = _gracePeriodDuration;
    }

    /// @notice Checks if a membership rate limit is valid. This does not take into account whether the total
    /// memberships have reached already the `maxTotalRateLimit` // FIXME: clarify
    /// @param membershipRateLimit The membership rate limit
    /// @return true if the membership rate limit is valid, false otherwise
    function isValidMembershipRateLimit(uint32 membershipRateLimit) external view returns (bool) {
        return membershipRateLimit >= minMembershipRateLimit && membershipRateLimit <= maxMembershipRateLimit;
    }

    /// @dev acquire a membership and trasnfer the fees to the contract // FIXME: fees == deposit?
    /// @param _sender address of the owner of the new membership
    /// @param _idCommitment the idCommitment of the new membership
    /// @param _rateLimit the membership rate limit
    /// @return index the index in the membership set
    /// @return indexReused indicates whether using a new Merkle tree leaf or an existing one
    function _acquireMembership(
        address _sender,
        uint256 _idCommitment,
        uint32 _rateLimit
    )
        internal
        returns (uint32 index, bool indexReused)
    {
        (address token, uint256 amount) = priceCalculator.calculate(_rateLimit);
        (index, indexReused) = _setupMembershipDetails(_sender, _idCommitment, _rateLimit, token, amount);
        _transferFees(_sender, token, amount);
    }

    function _transferFees(address _from, address _token, uint256 _amount) internal {
        IERC20(_token).safeTransferFrom(_from, address(this), _amount);
    }

    /// @dev Setup a new membership. If there are not enough remaining rate limit to acquire
    /// a new membership, it will attempt to erase existing expired memberships
    /// and reuse one of their slots
    /// @param _sender holder of the membership. Generally `msg.sender` // FIXME: rename to holder?
    /// @param _idCommitment idCommitment
    /// @param _rateLimit membership rate limit
    /// @param _token Address of the token used to acquire the membership
    /// @param _depositAmount Amount of the tokens used to acquire the membership
    /// @return index membership index in the membership set
    /// @return indexReused indicates whether the index returned was a reused slot on the tree or not
    function _setupMembershipDetails(
        address _sender,
        uint256 _idCommitment,
        uint32 _rateLimit,
        address _token,
        uint256 _depositAmount
    )
        internal
        returns (uint32 index, bool indexReused)
    {
        if (_rateLimit < minMembershipRateLimit || _rateLimit > maxMembershipRateLimit) {
            revert InvalidRateLimit();
        }

        // Determine if we exceed the total rate limit
        totalRateLimit += _rateLimit;
        if (totalRateLimit > maxTotalRateLimit) {
            revert ExceededMaxTotalRateLimit();
        }

        // Reuse available slots from previously removed (FIXME: clarify "removed") expired memberships
        (index, indexReused) = _getFreeIndex();

        memberships[_idCommitment] = MembershipInfo({
            holder: _sender,
            gracePeriodStartTimestamp: block.timestamp + uint256(expirationTerm),
            gracePeriodDuration: gracePeriodDuration,
            token: _token,
            depositAmount: _depositAmount,
            rateLimit: _rateLimit,
            index: index
        });
    }

    /// @dev Get a free index (possibly from reusing a slot of an expired membership)
    /// @return index index to be used for another membership registration
    /// @return indexReused indicates whether index comes form reusing a slot of an expired membership
    function _getFreeIndex() internal returns (uint32 index, bool indexReused) {
        // Reuse available slots from previously removed (FIXME: clarify "removed") expired memberships
        uint256 arrLen = availableExpiredMembershipsIndices.length;
        if (arrLen != 0) {
            index = availableExpiredMembershipsIndices[arrLen - 1];
            availableExpiredMembershipsIndices.pop();
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

        if (!_isInGracePeriodNow(membership.gracePeriodStartTimestamp, membership.gracePeriodDuration)) {
            revert NotInGracePeriod(_idCommitment);
        }

        if (_sender != membership.holder) revert AttemptedExtensionByNonHolder(_idCommitment); // FIXME: turn into a
            // modifier?
        // FIXME: see spec: should extension depend on the current block.timestamp?
        uint256 newGracePeriodStartTimestamp = block.timestamp + uint256(expirationTerm);

        membership.gracePeriodStartTimestamp = newGracePeriodStartTimestamp;
        membership.gracePeriodDuration = gracePeriodDuration; // FIXME: redundant: just assigns old value

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
    function _isInGracePeriodNow(
        uint256 _gracePeriodStartTimestamp,
        uint32 _gracePeriodDuration
    )
        internal
        view
        returns (bool)
    {
        uint256 blockTimestamp = block.timestamp;
        return blockTimestamp >= _gracePeriodStartTimestamp
            && blockTimestamp <= _gracePeriodStartTimestamp + uint256(_gracePeriodDuration);
    }

    /// @notice Determine if a membership is in grace period now
    /// @param _idCommitment the idCommitment of the membership
    function isInGracePeriodNow(uint256 _idCommitment) public view returns (bool) {
        MembershipInfo memory membership = memberships[_idCommitment];
        return _isInGracePeriodNow(membership.gracePeriodStartTimestamp, membership.gracePeriodDuration);
    }

    /// @dev Erase expired memberships or owned grace-period memberships.
    /// @param _sender address of the sender of transaction (will be used to check memberships in grace period)
    /// @param _idCommitment idCommitment of the membership to erase
    function _eraseMembership(address _sender, uint256 _idCommitment, MembershipInfo memory _membership) internal {
        bool membershipExpired = _isExpired(_membership.gracePeriodStartTimestamp, _membership.gracePeriodDuration);
        bool isInGracePeriodAndOwned = // FIXME: separate into two checks? cf. short-circuit
        _isInGracePeriodNow(_membership.gracePeriodStartTimestamp, _membership.gracePeriodDuration)
            && _membership.holder == _sender;
        // FIXME: we already had a non-holder check: reuse it here as a modifier
        if (!membershipExpired && !isInGracePeriodAndOwned) revert CantEraseMembership(_idCommitment);

        emit MembershipExpired(_idCommitment, _membership.rateLimit, _membership.index);

        // Move balance from expired membership to holder balance
        balancesToWithdraw[_membership.holder][_membership.token] += _membership.depositAmount;

        // Deduct the expired membership rate limit
        totalRateLimit -= _membership.rateLimit;

        // Note: the Merkle tree data will be erased lazily later  // FIXME: when?
        availableExpiredMembershipsIndices.push(_membership.index);

        delete memberships[_idCommitment];
    }

    /// @dev Withdraw any available balance in tokens after a membership is erased.
    /// @param _sender the address of the owner of the tokens
    /// @param _token the address of the token to withdraw
    function _withdraw(address _sender, address _token) internal {
        require(_token != address(0), "ETH is not allowed");

        uint256 amount = balancesToWithdraw[_sender][_token];
        require(amount > 0, "Insufficient balance");

        balancesToWithdraw[_sender][_token] = 0;
        IERC20(_token).safeTransfer(_sender, amount);
    }

    /**
     * @dev This empty reserved space is put in place to allow future versions to add new
     * variables without shifting down storage in the inheritance chain.
     * See https://docs.openzeppelin.com/contracts/4.x/upgradeable#storage_gaps
     */
    uint256[50] private __gap;
}
