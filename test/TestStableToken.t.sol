// SPDX-License-Identifier: MIT
pragma solidity >=0.8.19 <0.9.0;

import { Test } from "forge-std/Test.sol";
import {
    TestStableToken,
    AccountNotMinter,
    AccountAlreadyMinter,
    AccountNotInMinterList,
    InsufficientETH,
    ExceedsCap
} from "./TestStableToken.sol";
import { ERC1967Proxy } from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import { DeployTokenWithProxy } from "../script/DeployTokenWithProxy.s.sol";

contract TestStableTokenTest is Test {
    TestStableToken internal token;
    DeployTokenWithProxy internal deployer;
    address internal owner;
    address internal user1;
    address internal user2;
    address internal nonMinter;

    event MinterAdded(address indexed account);
    event MinterRemoved(address indexed account);
    event ETHBurned(uint256 amount, address indexed minter, address indexed to, uint256 tokensMinted);
    event CapSet(uint256 oldCap, uint256 newCap);

    function setUp() public {
        // Deploy using the deployment script
        deployer = new DeployTokenWithProxy();
        ERC1967Proxy proxy = deployer.deploy();

        // Wrap proxy in TestStableToken interface
        token = TestStableToken(address(proxy));

        owner = address(deployer);
        user1 = vm.addr(1);
        user2 = vm.addr(2);
        nonMinter = vm.addr(3);
    }

    function test__OwnerCanAddMinterRole() external {
        assertFalse(token.isMinter(user1));

        vm.prank(owner);
        token.addMinter(user1);

        assertTrue(token.isMinter(user1));
    }

    function test__OwnerCanRemoveMinterRole() external {
        vm.prank(owner);
        token.addMinter(user1);
        assertTrue(token.isMinter(user1));

        vm.prank(owner);
        token.removeMinter(user1);

        assertFalse(token.isMinter(user1));
    }

    function test__OwnerCanMintWithoutMinterRole() external {
        uint256 mintAmount = 1000 ether;

        // Owner is not in minter role but should still be able to mint
        assertFalse(token.isMinter(owner));

        vm.prank(owner);
        token.mint(user1, mintAmount);

        assertEq(token.balanceOf(user1), mintAmount);
    }

    function test__NonOwnerCannotAddMinterRole() external {
        vm.prank(user1);
        vm.expectRevert("Ownable: caller is not the owner");
        token.addMinter(user1);
    }

    function test__NonOwnerCannotRemoveMinterRole() external {
        vm.prank(owner);
        token.addMinter(user1);

        vm.prank(user1);
        vm.expectRevert("Ownable: caller is not the owner");
        token.removeMinter(user1);
    }

    function test__CannotAddAlreadyMinterRole() external {
        vm.prank(owner);
        token.addMinter(user1);

        vm.expectRevert(abi.encodeWithSelector(AccountAlreadyMinter.selector));
        vm.prank(owner);
        token.addMinter(user1);
    }

    function test__CannotRemoveNonMinterRole() external {
        vm.expectRevert(abi.encodeWithSelector(AccountNotInMinterList.selector));
        vm.prank(owner);
        token.removeMinter(user1);
    }

    function test__MinterRoleCanMint() external {
        uint256 mintAmount = 1000 ether;
        vm.prank(owner);
        token.addMinter(user1);

        vm.prank(user1);
        token.mint(user2, mintAmount);

        assertEq(token.balanceOf(user2), mintAmount);
    }

    function test__NonMinterNonOwnerAccountCannotMint() external {
        uint256 mintAmount = 1000 ether;

        vm.prank(nonMinter);
        vm.expectRevert("AccountNotMinter");
        token.mint(user1, mintAmount);
    }

    function test__MultipleMinterRolesCanMint() external {
        uint256 mintAmount = 500 ether;
        vm.prank(owner);
        token.addMinter(user1);
        vm.prank(owner);
        token.addMinter(user2);

        vm.prank(user1);
        token.mint(owner, mintAmount);

        vm.prank(user2);
        token.mint(owner, mintAmount);

        assertEq(token.balanceOf(owner), mintAmount * 2);
    }

    function test__RemovedMinterRoleCannotMint() external {
        uint256 mintAmount = 1000 ether;
        vm.prank(owner);
        token.addMinter(user1);
        vm.prank(owner);
        token.removeMinter(user1);

        vm.prank(user1);
        vm.expectRevert("AccountNotMinter");
        token.mint(user2, mintAmount);
    }

    function test__CheckMinterRoleMapping() external {
        assertFalse(token.isMinter(user1));
        assertFalse(token.isMinter(user2));

        vm.prank(owner);
        token.addMinter(user1);
        assertTrue(token.isMinter(user1));
        assertFalse(token.isMinter(user2));

        vm.prank(owner);
        token.addMinter(user2);
        assertTrue(token.isMinter(user1));
        assertTrue(token.isMinter(user2));

        vm.prank(owner);
        token.removeMinter(user1);
        assertFalse(token.isMinter(user1));
        assertTrue(token.isMinter(user2));
    }

    function test__MinterAddedEventEmitted() external {
        vm.expectEmit(true, true, false, false);
        emit MinterAdded(user1);

        vm.prank(owner);
        token.addMinter(user1);
    }

    function test__MinterRemovedEventEmitted() external {
        vm.prank(owner);
        token.addMinter(user1);

        vm.expectEmit(true, true, false, false);
        emit MinterRemoved(user1);

        vm.prank(owner);
        token.removeMinter(user1);
    }

    function test__MintRequiresETH() external {
        vm.prank(owner);
        vm.expectRevert(abi.encodeWithSelector(InsufficientETH.selector));
        token.mintWithETH(user1);
    }

    function test__ERC20BasicFunctionality() external {
        uint256 ethAmount = 0.1 ether;

        vm.deal(user1, ethAmount);
        vm.prank(user1);
        token.mintWithETH{ value: ethAmount }(user2);

        assertEq(token.balanceOf(user2), ethAmount);
        assertEq(token.totalSupply(), ethAmount);

        vm.prank(user2);
        assertTrue(token.transfer(owner, 0.05 ether));

        assertEq(token.balanceOf(user2), 0.05 ether);
        assertEq(token.balanceOf(owner), 0.05 ether);
    }

    function test__ETHBurnedEventEmitted() external {
        uint256 ethAmount = 0.1 ether;

        vm.deal(owner, ethAmount);

        vm.expectEmit(true, true, true, true);
        emit ETHBurned(ethAmount, owner, user1, ethAmount);

        vm.prank(owner);
        token.mintWithETH{ value: ethAmount }(user1);
    }

    function test__ETHIsBurnedToZeroAddress() external {
        uint256 ethAmount = 0.1 ether;
        address zeroAddress = address(0);

        uint256 zeroBalanceBefore = zeroAddress.balance;

        vm.deal(owner, ethAmount);
        vm.prank(owner);
        token.mintWithETH{ value: ethAmount }(user1);

        // ETH should be burned to zero address
        assertEq(zeroAddress.balance, zeroBalanceBefore + ethAmount);
    }

    function test__ContractDoesNotHoldETHAfterMint() external {
        uint256 ethAmount = 0.1 ether;

        uint256 contractBalanceBefore = address(token).balance;

        vm.deal(owner, ethAmount);
        vm.prank(owner);
        token.mintWithETH{ value: ethAmount }(user1);

        // Contract should not hold any ETH after mint
        assertEq(address(token).balance, contractBalanceBefore);
    }

    function test__MintWithDifferentETHAmounts() external {
        uint256[] memory ethAmounts = new uint256[](3);
        ethAmounts[0] = 0.01 ether;
        ethAmounts[1] = 1 ether;
        ethAmounts[2] = 10 ether;

        for (uint256 i = 0; i < ethAmounts.length; i++) {
            address user = vm.addr(i + 10);
            vm.deal(owner, ethAmounts[i]);

            vm.expectEmit(true, true, true, true);
            emit ETHBurned(ethAmounts[i], owner, user, ethAmounts[i]);

            vm.prank(owner);
            token.mintWithETH{ value: ethAmounts[i] }(user);

            assertEq(token.balanceOf(user), ethAmounts[i]);
        }
    }

    function test__CannotMintWithZeroETH() external {
        // Anyone can call mintWithETH (public function), but it requires ETH
        vm.prank(user1);
        vm.expectRevert(abi.encodeWithSelector(InsufficientETH.selector));
        token.mintWithETH{ value: 0 }(user2);
    }

    function test__CapIsSetCorrectly() external {
        // Cap should be set to 1000000 * 10^18 by deployment script
        uint256 expectedCap = 1_000_000 * 10 ** 18;
        assertEq(token.cap(), expectedCap);
    }

    function test__CannotMintExceedingCap() external {
        uint256 currentCap = token.cap();

        // Try to mint more than cap
        vm.prank(owner);
        vm.expectRevert(abi.encodeWithSelector(ExceedsCap.selector));
        token.mint(user1, currentCap + 1);
    }

    function test__CannotMintWithETHExceedingCap() external {
        uint256 currentCap = token.cap();
        // Send an amount of ETH that would exceed cap when minted as tokens
        uint256 ethAmount = currentCap + 1;

        // Try to mint more than cap with ETH
        vm.deal(owner, ethAmount);
        vm.prank(owner);
        vm.expectRevert(abi.encodeWithSelector(ExceedsCap.selector));
        token.mintWithETH{ value: ethAmount }(user1);
    }

    function test__OwnerCanSetCap() external {
        uint256 newCap = 2_000_000 * 10 ** 18;
        uint256 oldCap = token.cap();

        vm.expectEmit(true, true, false, false);
        emit CapSet(oldCap, newCap);

        vm.prank(owner);
        token.setCap(newCap);

        assertEq(token.cap(), newCap);
    }

    function test__CannotSetCapBelowTotalSupply() external {
        // First mint some tokens
        uint256 mintAmount = 1000 ether;
        vm.prank(owner);
        token.mint(user1, mintAmount);

        // Try to set cap below current totalSupply
        vm.prank(owner);
        vm.expectRevert(abi.encodeWithSelector(ExceedsCap.selector));
        token.setCap(mintAmount - 1);
    }

    function test__NonOwnerCannotSetCap() external {
        uint256 newCap = 2_000_000 * 10 ** 18;

        vm.prank(user1);
        vm.expectRevert("Ownable: caller is not the owner");
        token.setCap(newCap);
    }
}
