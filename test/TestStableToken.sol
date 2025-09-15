// SPDX-License-Identifier: MIT
pragma solidity >=0.8.19 <0.9.0;

import { BaseScript } from "../script/Base.s.sol";
import { ERC20Upgradeable } from "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";
import { ERC20PermitUpgradeable } from
    "@openzeppelin/contracts-upgradeable/token/ERC20/extensions/ERC20PermitUpgradeable.sol";
import { OwnableUpgradeable } from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import { Initializable } from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import { UUPSUpgradeable } from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";

error AccountNotMinter();
error AccountAlreadyMinter();
error AccountNotInMinterList();
error InsufficientETH();
error ExceedsMaxSupply();

contract TestStableToken is
    Initializable,
    ERC20Upgradeable,
    ERC20PermitUpgradeable,
    OwnableUpgradeable,
    UUPSUpgradeable
{
    mapping(address => bool) public isMinter;
    uint256 public maxSupply;

    event MinterAdded(address indexed account);
    event MinterRemoved(address indexed account);
    event ETHBurned(uint256 amount, address indexed minter, address indexed to, uint256 tokensMinted);
    event MaxSupplySet(uint256 oldMaxSupply, uint256 newMaxSupply);

    modifier onlyOwnerOrMinter() {
        if (msg.sender != owner() && !isMinter[msg.sender]) revert("AccountNotMinter");
        _;
    }

    constructor() {
        _disableInitializers();
    }

    function initialize(uint256 _maxSupply) public initializer {
        __ERC20_init("TestStableToken", "TST");
        __ERC20Permit_init("TestStableToken");
        __Ownable_init();
        __UUPSUpgradeable_init();

        maxSupply = _maxSupply;
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
        if (totalSupply() + amount > maxSupply) revert ExceedsMaxSupply();
        _mint(to, amount);
    }

    function mintWithETH(address to) external payable {
        if (msg.value == 0) revert InsufficientETH();
        if (totalSupply() + msg.value > maxSupply) revert ExceedsMaxSupply();

        // Burn ETH by sending to zero address
        payable(address(0)).transfer(msg.value);

        _mint(to, msg.value);

        emit ETHBurned(msg.value, msg.sender, to, msg.value);
    }

    function setMaxSupply(uint256 _maxSupply) external onlyOwner {
        if (_maxSupply < totalSupply()) revert ExceedsMaxSupply();

        uint256 oldMaxSupply = maxSupply;
        maxSupply = _maxSupply;

        emit MaxSupplySet(oldMaxSupply, _maxSupply);
    }
}

contract TestStableTokenFactory is BaseScript {
    function run() public broadcast returns (address) {
        return address(new TestStableToken());
    }
}
