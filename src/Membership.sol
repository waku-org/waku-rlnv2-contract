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
error ExceedAvailableMaxRateLimitPerEpoch();

// This membership is not in grace period yet
error NotInGracePeriod(uint256 idCommitment);

// The sender is not the holder of the membership
error NotHolder(uint256 idCommitment);

// This membership cannot be erased (either it is not expired or not in grace period and/or not the owner)
error CantEraseMembership(uint256 idCommitment);

abstract contract MembershipUpgradeable is Initializable {
    using SafeERC20 for IERC20;

    /// @notice Address of the Price Calculator used to calculate the price of a new membership
    IPriceCalculator public priceCalculator;

    /// @notice Maximum total rate limit of all memberships in the tree
    uint32 public maxTotalRateLimitPerEpoch;

    /// @notice Maximum rate limit of one membership
    uint32 public maxRateLimitPerMembership;

    /// @notice Minimum rate limit of one membership
    uint32 public minRateLimitPerMembership;

    /// @notice Membership billing period
    uint32 public expirationTerm;

    /// @notice Membership grace period
    uint32 public gracePeriod;

    /// @notice balances available to withdraw
    mapping(address holder => mapping(address token => uint256 balance)) public balancesToWithdraw;

    /// @notice Total rate limit of all memberships in the tree
    uint256 public totalRateLimitPerEpoch;

    /// @notice List of registered memberships
    mapping(uint256 idCommitment => MembershipInfo member) public members;

    /// @notice The index on the merkle tree for the next member to be registered
    uint32 public nextCommitmentIndex;

    /// @notice track available indices that are available due to expired memberships being removed
    uint32[] public availableExpiredIndices;

    struct MembershipInfo {
        /// @notice amount of the token used to acquire this membership
        uint256 amount;
        /// @notice timestamp of when the grace period starts for this membership
        uint256 gracePeriodStartDate;
        /// @notice duration of the grace period
        uint32 gracePeriod;
        /// @notice the user message limit of each member
        uint32 userMessageLimit;
        /// @notice the index of the member in the set
        uint32 index;
        /// @notice address of the owner of this membership
        address holder;
        /// @notice token used to acquire this membership
        address token;
    }

    /// @notice Emitted when a membership is erased due to having exceeded the grace period or the owner having chosen
    /// to not extend it
    /// @param idCommitment the idCommitment of the member
    /// @param userMessageLimit the rate limit of this membership
    /// @param index the index of the membership in the merkle tree
    event MemberExpired(uint256 idCommitment, uint32 userMessageLimit, uint32 index);

    /// @notice Emitted when a membership in grace period is extended
    /// @param idCommitment the idCommitment of the member
    /// @param userMessageLimit the rate limit of this membership
    /// @param index the index of the membership in the merkle tree
    /// @param newExpirationDate the new expiration date of this membership
    event MemberExtended(uint256 idCommitment, uint32 userMessageLimit, uint32 index, uint256 newExpirationDate);

    /// @dev contract initializer
    /// @param _priceCalculator Address of an instance of IPriceCalculator
    /// @param _maxTotalRateLimitPerEpoch Maximum total rate limit of all memberships in the tree
    /// @param _minRateLimitPerMembership Minimum rate limit of one membership
    /// @param _maxRateLimitPerMembership Maximum rate limit of one membership
    /// @param _expirationTerm Membership expiration term
    /// @param _gracePeriod Membership grace period
    function __MembershipUpgradeable_init(
        address _priceCalculator,
        uint32 _maxTotalRateLimitPerEpoch,
        uint32 _minRateLimitPerMembership,
        uint32 _maxRateLimitPerMembership,
        uint32 _expirationTerm,
        uint32 _gracePeriod
    )
        internal
        onlyInitializing
    {
        __MembershipUpgradeable_init_unchained(
            _priceCalculator,
            _maxTotalRateLimitPerEpoch,
            _minRateLimitPerMembership,
            _maxRateLimitPerMembership,
            _expirationTerm,
            _gracePeriod
        );
    }

    function __MembershipUpgradeable_init_unchained(
        address _priceCalculator,
        uint32 _maxTotalRateLimitPerEpoch,
        uint32 _minRateLimitPerMembership,
        uint32 _maxRateLimitPerMembership,
        uint32 _expirationTerm,
        uint32 _gracePeriod
    )
        internal
        onlyInitializing
    {
        require(_maxTotalRateLimitPerEpoch >= maxRateLimitPerMembership);
        require(_maxRateLimitPerMembership > minRateLimitPerMembership);
        require(_minRateLimitPerMembership > 0);
        require(_expirationTerm > 0);

        priceCalculator = IPriceCalculator(_priceCalculator);
        maxTotalRateLimitPerEpoch = _maxTotalRateLimitPerEpoch;
        maxRateLimitPerMembership = _maxRateLimitPerMembership;
        minRateLimitPerMembership = _minRateLimitPerMembership;
        expirationTerm = _expirationTerm;
        gracePeriod = _gracePeriod;
    }

    /// @notice Checks if a user message limit is valid. This does not take into account whether we the total
    /// memberships have reached already the `maxTotalRateLimitPerEpoch`
    /// @param userMessageLimit The user message limit
    /// @return true if the user message limit is valid, false otherwise
    function isValidUserMessageLimit(uint32 userMessageLimit) external view returns (bool) {
        return userMessageLimit >= minRateLimitPerMembership && userMessageLimit <= maxRateLimitPerMembership;
    }

    /// @dev acquire a membership and trasnfer the fees to the contract
    /// @param _sender address of the owner of the new membership
    /// @param _idCommitment the idcommitment of the new membership
    /// @param _rateLimit the user message limit
    /// @return index the index in the merkle tree
    /// @return reusedIndex indicates whether a new leaf is being used or if using an existing leaf in the merkle tree
    function _acquireMembership(
        address _sender,
        uint256 _idCommitment,
        uint32 _rateLimit
    )
        internal
        returns (uint32 index, bool reusedIndex)
    {
        (address token, uint256 amount) = priceCalculator.calculate(_rateLimit);
        (index, reusedIndex) = _setupMembershipDetails(_sender, _idCommitment, _rateLimit, token, amount);
        _transferFees(_sender, token, amount);
    }

    function _transferFees(address _from, address _token, uint256 _amount) internal {
        IERC20(_token).safeTransferFrom(_from, address(this), _amount);
    }

    /// @dev Setup a new membership. If there are not enough remaining rate limit to acquire
    /// a new membership, it will attempt to erase existing memberships and reuse one of the
    /// slots helds by the membership
    /// @param _sender holder of the membership. Generally `msg.sender`
    /// @param _idCommitment IDCommitment
    /// @param _rateLimit User message limit
    /// @param _token Address of the token used to acquire the membership
    /// @param _amount Amount of the token used to acquire the membership
    /// @return index membership index on the merkle tree
    /// @return reusedIndex indicates whether the index returned was a reused slot on the tree or not
    function _setupMembershipDetails(
        address _sender,
        uint256 _idCommitment,
        uint32 _rateLimit,
        address _token,
        uint256 _amount
    )
        internal
        returns (uint32 index, bool reusedIndex)
    {
        if (_rateLimit < minRateLimitPerMembership || _rateLimit > maxRateLimitPerMembership) {
            revert InvalidRateLimit();
        }

        // Determine if we exceed the total rate limit
        totalRateLimitPerEpoch += _rateLimit;
        if (totalRateLimitPerEpoch > maxTotalRateLimitPerEpoch) {
            revert ExceedAvailableMaxRateLimitPerEpoch(); // List is empty or can't
        }

        // Reuse available slots from previously removed expired memberships
        (index, reusedIndex) = _nextIndex();

        members[_idCommitment] = MembershipInfo({
            holder: _sender,
            gracePeriodStartDate: block.timestamp + uint256(expirationTerm),
            gracePeriod: gracePeriod,
            token: _token,
            amount: _amount,
            userMessageLimit: _rateLimit,
            index: index
        });
    }

    /// @dev reuse available slots from previously removed expired memberships
    /// @return index index to use
    /// @return reusedIndex indicates whether it is reusing an existing index, or using a new one
    function _nextIndex() internal returns (uint32 index, bool reusedIndex) {
        // Reuse available slots from previously removed expired memberships
        uint256 arrLen = availableExpiredIndices.length;
        if (arrLen != 0) {
            index = availableExpiredIndices[arrLen - 1];
            availableExpiredIndices.pop();
            reusedIndex = true;
        } else {
            index = nextCommitmentIndex;
        }
    }

    /// @dev Extend a membership expiration date. Membership must be on grace period
    /// @param _sender the address of the holder of the membership
    /// @param _idCommitment the idCommitment of the membership
    function _extendMembership(address _sender, uint256 _idCommitment) public {
        MembershipInfo storage mdetails = members[_idCommitment];

        if (!_isGracePeriod(mdetails.gracePeriodStartDate, mdetails.gracePeriod)) {
            revert NotInGracePeriod(_idCommitment);
        }

        if (_sender != mdetails.holder) revert NotHolder(_idCommitment);

        uint256 gracePeriodStartDate = block.timestamp + uint256(expirationTerm);

        mdetails.gracePeriodStartDate = gracePeriodStartDate;
        mdetails.gracePeriod = gracePeriod;

        emit MemberExtended(_idCommitment, mdetails.userMessageLimit, mdetails.index, gracePeriodStartDate);
    }

    /// @dev Determine whether a timestamp is considered to be expired or not after exceeding the grace period
    /// @param _gracePeriodStartDate timestamp in which the grace period starts
    /// @param _gracePeriod duration of the grace period
    function _isExpired(uint256 _gracePeriodStartDate, uint32 _gracePeriod) internal view returns (bool) {
        return block.timestamp > _gracePeriodStartDate + uint256(_gracePeriod);
    }

    /// @notice Determine if a membership is expired (has exceeded the grace period)
    /// @param _idCommitment the idCommitment of the membership
    function isExpired(uint256 _idCommitment) public view returns (bool) {
        MembershipInfo memory m = members[_idCommitment];
        return _isExpired(m.gracePeriodStartDate, m.gracePeriod);
    }

    /// @notice Returns the timestamp on which a membership can be considered expired
    /// @param _idCommitment the idCommitment of the membership
    function expirationDate(uint256 _idCommitment) public view returns (uint256) {
        MembershipInfo memory m = members[_idCommitment];
        return m.gracePeriodStartDate + uint256(m.gracePeriod) + 1;
    }

    /// @dev Determine whether a timestamp is considered to be in grace period or not
    /// @param _gracePeriodStartDate timestamp in which the grace period starts
    /// @param _gracePeriod duration of the grace period
    function _isGracePeriod(uint256 _gracePeriodStartDate, uint32 _gracePeriod) internal view returns (bool) {
        uint256 blockTimestamp = block.timestamp;
        return
            blockTimestamp >= _gracePeriodStartDate && blockTimestamp <= _gracePeriodStartDate + uint256(_gracePeriod);
    }

    /// @notice Determine if a membership is in grace period
    /// @param _idCommitment the idCommitment of the membership
    function isGracePeriod(uint256 _idCommitment) public view returns (bool) {
        MembershipInfo memory m = members[_idCommitment];
        return _isGracePeriod(m.gracePeriodStartDate, m.gracePeriod);
    }

    /// @dev Remove expired memberships or owned memberships in grace period.
    /// @param _sender address of the sender of transaction (will be used to check memberships in grace period)
    /// @param _idCommitment IDCommitment of the membership to erase
    function _eraseMembership(address _sender, uint256 _idCommitment, MembershipInfo memory _mdetails) internal {
        bool membershipExpired = _isExpired(_mdetails.gracePeriodStartDate, _mdetails.gracePeriod);
        bool isGracePeriodAndOwned =
            _isGracePeriod(_mdetails.gracePeriodStartDate, _mdetails.gracePeriod) && _mdetails.holder == _sender;

        if (!membershipExpired && !isGracePeriodAndOwned) revert CantEraseMembership(_idCommitment);

        emit MemberExpired(_idCommitment, _mdetails.userMessageLimit, _mdetails.index);

        // Move balance from expired membership to holder balance
        balancesToWithdraw[_mdetails.holder][_mdetails.token] += _mdetails.amount;

        // Deduct the expired membership rate limit
        totalRateLimitPerEpoch -= _mdetails.userMessageLimit;

        availableExpiredIndices.push(_mdetails.index);

        delete members[_idCommitment];
    }

    /// @dev Withdraw any available balance in tokens after a membership is erased.
    /// @param _sender the address of the owner of the tokens
    /// @param _token the address of the token to withdraw.
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
