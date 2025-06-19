// SPDX-License-Identifier: MIT
pragma solidity >=0.8.19 <0.9.0;

import { BaseScript } from "../script/Base.s.sol";
import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { ERC20Permit } from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Permit.sol";

contract TestToken is ERC20, ERC20Permit {
    bytes32 public DAI_DOMAIN_SEPARATOR;
    bytes32 public constant PERMIT_TYPEHASH = 0xea2aa0a1be11a07ed86d755c93467f4f82362b452371d1ba94d1715123511acb;

    constructor() ERC20("TestToken", "TTT") ERC20Permit("TestToken") {
        DAI_DOMAIN_SEPARATOR = keccak256(
            abi.encode(
                keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)"),
                keccak256(bytes("TestToken")),
                keccak256(bytes("1")),
                block.chainid,
                address(this)
            )
        );
    }

    function mint(address to, uint256 amount) public {
        _mint(to, amount);
    }

    function permit(
        address holder,
        address spender,
        uint256 nonce,
        uint256 expiry,
        bool allowed,
        uint8 v,
        bytes32 r,
        bytes32 s
    )
        external
    {
        bytes32 digest = keccak256(
            abi.encodePacked(
                "\x19\x01",
                DAI_DOMAIN_SEPARATOR,
                keccak256(abi.encode(PERMIT_TYPEHASH, holder, spender, nonce, expiry, allowed))
            )
        );

        require(holder != address(0));
        require(holder == ecrecover(digest, v, r, s));
        require(expiry == 0 || block.timestamp <= expiry);
        require(nonce == _useNonce(holder));

        uint256 value = allowed ? type(uint256).max : 0;

        _approve(holder, spender, value);
    }
}

contract TestTokenFactory is BaseScript {
    function run() public broadcast returns (address) {
        return address(new TestToken());
    }
}
