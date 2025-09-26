// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.8.19 <0.9.0;

import "../src/Membership.sol";
import "../src/WakuRlnV2.sol";
import "forge-std/console.sol"; // solhint-disable-line
import "forge-std/Vm.sol";
import { DeployPriceCalculator, DeployWakuRlnV2, DeployProxy } from "../script/Deploy.s.sol"; // solhint-disable-line
import { DeployTokenWithProxy } from "../script/DeployTokenWithProxy.s.sol";
import { ECDSA } from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import { ERC1967Proxy } from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import { IPriceCalculator } from "../src/IPriceCalculator.sol";
import { LinearPriceCalculator } from "../src/LinearPriceCalculator.sol";
import { PoseidonT3 } from "poseidon-solidity/PoseidonT3.sol";
import { Test } from "forge-std/Test.sol"; // For signature manipulation
import { TestStableToken } from "./TestStableToken.sol";
import { UUPSUpgradeable } from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";

contract WakuRlnV2Test is Test {
    WakuRlnV2 internal w;
    TestStableToken internal token;
    DeployTokenWithProxy internal tokenDeployer;

    address internal deployer;

    uint256[] internal noIdCommitmentsToErase = new uint256[](0);

    function setUp() public virtual {
        // Deploy TestStableToken through proxy using deployment script
        tokenDeployer = new DeployTokenWithProxy();
        ERC1967Proxy tokenProxy = tokenDeployer.deploy();
        token = TestStableToken(address(tokenProxy));

        IPriceCalculator priceCalculator = (new DeployPriceCalculator()).deploy(address(token));
        WakuRlnV2 wakuRlnV2 = (new DeployWakuRlnV2()).deploy();
        ERC1967Proxy proxy = (new DeployProxy()).deploy(address(priceCalculator), address(wakuRlnV2));

        w = WakuRlnV2(address(proxy));

        // Log owner for debugging
        console.log("WakuRlnV2 owner: ", w.owner());

        // Minting a large number of tokens to not have to worry about
        // Not having enough balance
        // 900_000 ether is chosen to be well above any test requirements and is within the new max supply constraints.
        vm.prank(address(tokenDeployer));
        token.mint(address(this), 900_000 ether);
    }

    function testFuzz_RegisterInvalid(uint256 idCommitment, uint32 rateLimit) external {
        vm.assume(idCommitment >= w.Q() || idCommitment == 0); // Invalid ID
        (, uint256 price) = w.priceCalculator().calculate(rateLimit);
        token.approve(address(w), price);
        vm.expectRevert(); // Generic or specific error
        w.register(idCommitment, rateLimit, new uint256[](0));
    }

    function testFuzz_MultipleRegisters(uint8 numRegs) external {
        vm.assume(numRegs > 0 && numRegs < 100); // Small for gas
        uint32 rateLimit = w.minMembershipRateLimit();
        uint256 totalExpected = 0;
        for (uint8 i = 1; i <= numRegs; i++) {
            vm.assume(w.currentTotalRateLimit() + rateLimit <= w.maxTotalRateLimit());
            (, uint256 price) = w.priceCalculator().calculate(rateLimit);
            token.approve(address(w), price);
            w.register(i, rateLimit, new uint256[](0));
            totalExpected += rateLimit;
        }
        assertEq(w.currentTotalRateLimit(), totalExpected);
    }
}
