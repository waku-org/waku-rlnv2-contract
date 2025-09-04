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
error ETHTransferFailed();

contract TestStableToken is
    Initializable,
    ERC20Upgradeable,
    ERC20PermitUpgradeable,
    OwnableUpgradeable,
    UUPSUpgradeable
{
    mapping(address => bool) public isMinter;

    event MinterAdded(address indexed account);
    event MinterRemoved(address indexed account);
    event ETHBurned(uint256 amount, address indexed minter, address indexed to, uint256 tokensMinted);

    modifier onlyOwnerOrMinter() {
        if (msg.sender != owner() && !isMinter[msg.sender]) revert AccountNotMinter();
        _;
    }

    constructor() {
        _disableInitializers();
    }

    function initialize() public initializer {
        __ERC20_init("TestStableToken", "TST");
        __ERC20Permit_init("TestStableToken");
        __Ownable_init();
        __UUPSUpgradeable_init();
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
        _mint(to, amount);
    }

    function mintWithETH(address to, uint256 amount) external payable {
        if (msg.value == 0) revert InsufficientETH();

        // Burn ETH by sending to zero address
        (bool success,) = payable(address(0)).call{ value: msg.value }("");
        if (!success) revert ETHTransferFailed();

        _mint(to, amount);

        emit ETHBurned(msg.value, msg.sender, to, amount);
    }
}

contract TestStableTokenFactory is BaseScript {
    function run() public broadcast returns (address) {
        return address(new TestStableToken());
    }
}
