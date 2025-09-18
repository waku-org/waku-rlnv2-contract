// SPDX-License-Identifier: MIT
pragma solidity >=0.8.19 <0.9.0;

import { BaseScript } from "../script/Base.s.sol";
import { ERC20Upgradeable } from "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";
import { ERC20PermitUpgradeable } from
    "@openzeppelin/contracts-upgradeable/token/ERC20/extensions/ERC20PermitUpgradeable.sol";
import { ERC20CappedUpgradeable } from
    "@openzeppelin/contracts-upgradeable/token/ERC20/extensions/ERC20CappedUpgradeable.sol";
import { OwnableUpgradeable } from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import { Initializable } from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import { UUPSUpgradeable } from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import { ERC1967Proxy } from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

error AccountNotMinter();
error AccountAlreadyMinter();
error AccountNotInMinterList();
error InsufficientETH();
error ExceedsCap();

contract TestStableToken is
    Initializable,
    ERC20CappedUpgradeable,
    ERC20PermitUpgradeable,
    OwnableUpgradeable,
    UUPSUpgradeable
{
    mapping(address account => bool allowed) public isMinter;

    // mutable cap storage ( override cap() from ERC20CappedUpgradeable to return this)
    uint256 private _mutableCap;

    event MinterAdded(address indexed account);
    event MinterRemoved(address indexed account);
    event ETHBurned(uint256 amount, address indexed minter, address indexed to, uint256 tokensMinted);
    event CapSet(uint256 oldCap, uint256 newCap);

    modifier onlyOwnerOrMinter() {
        if (msg.sender != owner() && !isMinter[msg.sender]) revert("AccountNotMinter");
        _;
    }

    constructor() {
        _disableInitializers();
    }

    function initialize(uint256 initialCap) public initializer {
        __ERC20_init("TestStableToken", "TST");
        __ERC20Permit_init("TestStableToken");
        __Ownable_init();
        __UUPSUpgradeable_init();
        // initialize capped supply (parent init does internal checks)
        __ERC20Capped_init(initialCap);

        // our mutable cap storage (used by the overridden cap())
        _mutableCap = initialCap;
    }

    function _authorizeUpgrade(address newImplementation) internal override onlyOwner { }

    function addMinter(address account) external onlyOwner {
        if (isMinter[account]) revert AccountAlreadyMinter();
        isMinter[account] = true;
        emit MinterAdded(account);
    }

    function removeMinter(address account) external onlyOwner {
        if (!isMinter[account]) revert AccountNotInMinterList();
        isMinter[account] = false;
        emit MinterRemoved(account);
    }

    function mint(address to, uint256 amount) external onlyOwnerOrMinter {
        // pre-check so we use custom error
        if (totalSupply() + amount > cap()) revert ExceedsCap();
        // ERC20CappedUpgradeable::_mint will still enforce the cap as a safety
        _mint(to, amount);
    }

    function mintWithETH(address to) external payable {
        if (msg.value == 0) revert InsufficientETH();
        if (totalSupply() + msg.value > cap()) revert ExceedsCap();

        // Burn ETH by sending to zero address
        payable(address(0)).transfer(msg.value);

        _mint(to, msg.value);

        emit ETHBurned(msg.value, msg.sender, to, msg.value);
    }

    // Returns the configured cap - override to use a mutable storage slot.
    function cap() public view virtual override returns (uint256) {
        return _mutableCap;
    }

    function setCap(uint256 newCap) external onlyOwner {
        if (newCap < totalSupply()) revert ExceedsCap();
        uint256 old = _mutableCap;
        _mutableCap = newCap;
        emit CapSet(old, newCap);
    }

    // Solidity requires an explicit override when multiple base classes in the
    // linearized inheritance chain declare the same function signature. Here
    // both ERC20Upgradeable (base) and ERC20CappedUpgradeable (overrider) are
    // present in the chain, so provide the override that forwards to super.
    function _mint(
        address account,
        uint256 amount
    )
        internal
        virtual
        override(ERC20CappedUpgradeable, ERC20Upgradeable)
    {
        super._mint(account, amount);
    }
}

contract TestStableTokenFactory is BaseScript {
    // Use the returned implementation address with a proxy upgrade call (e.g. `upgradeToAndCall`) to atomically point a
    // proxy to the new implementation and initialize it.
    function run() public broadcast returns (address) {
        return address(new TestStableToken());
    }
}
