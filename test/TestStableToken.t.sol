// SPDX-License-Identifier: MIT
pragma solidity >=0.8.19 <0.9.0;

import { Test } from "forge-std/Test.sol";
import { TestStableToken, AccountNotMinter, AccountAlreadyMinter, AccountNotInMinterList } from "./TestStableToken.sol";
import { ERC1967Proxy } from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

contract TestStableTokenTest is Test {
    TestStableToken internal token;
    address internal owner;
    address internal user1;
    address internal user2;
    address internal nonMinter;

    function setUp() public {
        // Deploy implementation
        TestStableToken implementation = new TestStableToken();
        
        // Deploy proxy with initialization
        bytes memory data = abi.encodeCall(TestStableToken.initialize, ());
        ERC1967Proxy proxy = new ERC1967Proxy(address(implementation), data);
        
        // Wrap proxy in TestStableToken interface
        token = TestStableToken(address(proxy));
        
        owner = address(this);
        user1 = vm.addr(1);
        user2 = vm.addr(2);
        nonMinter = vm.addr(3);
    }

    function test__OwnerCanAddMinterRole() external {
        assertFalse(token.isMinter(user1));

        token.addMinter(user1);

        assertTrue(token.isMinter(user1));
    }

    function test__OwnerCanRemoveMinterRole() external {
        token.addMinter(user1);
        assertTrue(token.isMinter(user1));

        token.removeMinter(user1);

        assertFalse(token.isMinter(user1));
    }

    function test__OwnerCanMintWithoutMinterRole() external {
        uint256 mintAmount = 1000 ether;

        token.mint(user1, mintAmount);

        assertEq(token.balanceOf(user1), mintAmount);
    }

    function test__NonOwnerCannotAddMinterRole() external {
        vm.prank(user1);
        vm.expectRevert();
        token.addMinter(user1);
    }

    function test__NonOwnerCannotRemoveMinterRole() external {
        token.addMinter(user1);

        vm.prank(user1);
        vm.expectRevert();
        token.removeMinter(user1);
    }

    function test__CannotAddAlreadyMinterRole() external {
        token.addMinter(user1);

        vm.expectRevert(abi.encodeWithSelector(AccountAlreadyMinter.selector));
        token.addMinter(user1);
    }

    function test__CannotRemoveNonMinterRole() external {
        vm.expectRevert(abi.encodeWithSelector(AccountNotInMinterList.selector));
        token.removeMinter(user1);
    }

    function test__MinterRoleCanMint() external {
        uint256 mintAmount = 1000 ether;
        token.addMinter(user1);

        vm.prank(user1);
        token.mint(user2, mintAmount);

        assertEq(token.balanceOf(user2), mintAmount);
    }

    function test__NonMinterNonOwnerAccountCannotMint() external {
        uint256 mintAmount = 1000 ether;

        vm.prank(nonMinter);
        vm.expectRevert(abi.encodeWithSelector(AccountNotMinter.selector));
        token.mint(user1, mintAmount);
    }

    function test__MultipleMinterRolesCanMint() external {
        uint256 mintAmount = 500 ether;
        token.addMinter(user1);
        token.addMinter(user2);

        vm.prank(user1);
        token.mint(owner, mintAmount);

        vm.prank(user2);
        token.mint(owner, mintAmount);

        assertEq(token.balanceOf(owner), mintAmount * 2);
    }

    function test__RemovedMinterRoleCannotMint() external {
        uint256 mintAmount = 1000 ether;
        token.addMinter(user1);
        token.removeMinter(user1);

        vm.prank(user1);
        vm.expectRevert(abi.encodeWithSelector(AccountNotMinter.selector));
        token.mint(user2, mintAmount);
    }

    function test__OwnerCanAlwaysMintEvenWithoutMinterRole() external {
        uint256 mintAmount = 500 ether;

        // Owner is not in minter role but should still be able to mint
        assertFalse(token.isMinter(address(this)));
        token.mint(user1, mintAmount);
        assertEq(token.balanceOf(user1), mintAmount);
    }

    function test__CheckMinterRoleMapping() external {
        assertFalse(token.isMinter(user1));
        assertFalse(token.isMinter(user2));

        token.addMinter(user1);
        assertTrue(token.isMinter(user1));
        assertFalse(token.isMinter(user2));

        token.addMinter(user2);
        assertTrue(token.isMinter(user1));
        assertTrue(token.isMinter(user2));

        token.removeMinter(user1);
        assertFalse(token.isMinter(user1));
        assertTrue(token.isMinter(user2));
    }

    function test__ERC20BasicFunctionality() external {
        token.addMinter(user1);
        uint256 mintAmount = 1000 ether;

        vm.prank(user1);
        token.mint(user2, mintAmount);

        assertEq(token.balanceOf(user2), mintAmount);
        assertEq(token.totalSupply(), mintAmount);

        vm.prank(user2);
        token.transfer(owner, 200 ether);

        assertEq(token.balanceOf(user2), 800 ether);
        assertEq(token.balanceOf(owner), 200 ether);
    }

    function test__MinterAddedEventEmitted() external {
        vm.expectEmit(true, true, false, false);
        emit MinterAdded(user1);

        token.addMinter(user1);
    }

    function test__MinterRemovedEventEmitted() external {
        token.addMinter(user1);

        vm.expectEmit(true, true, false, false);
        emit MinterRemoved(user1);

        token.removeMinter(user1);
    }

    event MinterAdded(address indexed account);
    event MinterRemoved(address indexed account);
}
