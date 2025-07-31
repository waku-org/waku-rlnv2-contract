// SPDX-License-Identifier: MIT
pragma solidity >=0.8.19 <0.9.0;

import { Test } from "forge-std/Test.sol";
import { TestStableToken, AccountNotApproved, AccountAlreadyApproved, AccountNotInList } from "./TestStableToken.sol";

contract TestStableTokenTest is Test {
    TestStableToken internal token;
    address internal owner;
    address internal user1;
    address internal user2;
    address internal nonApproved;

    function setUp() public {
        token = new TestStableToken();
        owner = address(this);
        user1 = vm.addr(1);
        user2 = vm.addr(2);
        nonApproved = vm.addr(3);
    }

    function test__OwnerCanAddApprovedAccount() external {
        assertFalse(token.approvedAccounts(user1));
        
        token.addApprovedAccount(user1);
        
        assertTrue(token.approvedAccounts(user1));
    }

    function test__OwnerCanRemoveApprovedAccount() external {
        token.addApprovedAccount(user1);
        assertTrue(token.approvedAccounts(user1));
        
        token.removeApprovedAccount(user1);
        
        assertFalse(token.approvedAccounts(user1));
    }

    function test__OwnerCanMintWithoutApproval() external {
        uint256 mintAmount = 1000 ether;
        
        token.mint(user1, mintAmount);
        
        assertEq(token.balanceOf(user1), mintAmount);
    }

    function test__NonOwnerCannotAddApprovedAccount() external {
        vm.prank(user1);
        vm.expectRevert("Ownable: caller is not the owner");
        token.addApprovedAccount(user1);
    }

    function test__NonOwnerCannotRemoveApprovedAccount() external {
        token.addApprovedAccount(user1);
        
        vm.prank(user1);
        vm.expectRevert("Ownable: caller is not the owner");
        token.removeApprovedAccount(user1);
    }

    function test__CannotAddAlreadyApprovedAccount() external {
        token.addApprovedAccount(user1);
        
        vm.expectRevert(abi.encodeWithSelector(AccountAlreadyApproved.selector));
        token.addApprovedAccount(user1);
    }

    function test__CannotRemoveNonApprovedAccount() external {
        vm.expectRevert(abi.encodeWithSelector(AccountNotInList.selector));
        token.removeApprovedAccount(user1);
    }

    function test__ApprovedAccountCanMint() external {
        uint256 mintAmount = 1000 ether;
        token.addApprovedAccount(user1);
        
        vm.prank(user1);
        token.mint(user2, mintAmount);
        
        assertEq(token.balanceOf(user2), mintAmount);
    }

    function test__NonApprovedNonOwnerAccountCannotMint() external {
        uint256 mintAmount = 1000 ether;
        
        vm.prank(nonApproved);
        vm.expectRevert(abi.encodeWithSelector(AccountNotApproved.selector));
        token.mint(user1, mintAmount);
    }

    function test__MultipleApprovedAccountsCanMint() external {
        uint256 mintAmount = 500 ether;
        token.addApprovedAccount(user1);
        token.addApprovedAccount(user2);
        
        vm.prank(user1);
        token.mint(owner, mintAmount);
        
        vm.prank(user2);
        token.mint(owner, mintAmount);
        
        assertEq(token.balanceOf(owner), mintAmount * 2);
    }

    function test__RemovedAccountCannotMint() external {
        uint256 mintAmount = 1000 ether;
        token.addApprovedAccount(user1);
        token.removeApprovedAccount(user1);
        
        vm.prank(user1);
        vm.expectRevert(abi.encodeWithSelector(AccountNotApproved.selector));
        token.mint(user2, mintAmount);
    }

    function test__OwnerCanAlwaysMintEvenWhenNotApproved() external {
        uint256 mintAmount = 500 ether;
        
        // Owner is not in approved accounts but should still be able to mint
        assertFalse(token.approvedAccounts(address(this)));
        token.mint(user1, mintAmount);
        assertEq(token.balanceOf(user1), mintAmount);
    }

    function test__CheckApprovedAccountsMapping() external {
        assertFalse(token.approvedAccounts(user1));
        assertFalse(token.approvedAccounts(user2));
        
        token.addApprovedAccount(user1);
        assertTrue(token.approvedAccounts(user1));
        assertFalse(token.approvedAccounts(user2));
        
        token.addApprovedAccount(user2);
        assertTrue(token.approvedAccounts(user1));
        assertTrue(token.approvedAccounts(user2));
        
        token.removeApprovedAccount(user1);
        assertFalse(token.approvedAccounts(user1));
        assertTrue(token.approvedAccounts(user2));
    }

    function test__ERC20BasicFunctionality() external {
        token.addApprovedAccount(user1);
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

}