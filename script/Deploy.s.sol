// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.8.19 <=0.9.0;

import { WakuRlnV2 } from "../src/WakuRlnV2.sol";
import { IPriceCalculator } from "../src/IPriceCalculator.sol";
import { LinearPriceCalculator } from "../src/LinearPriceCalculator.sol";
import { PoseidonT3 } from "poseidon-solidity/PoseidonT3.sol";
import { LazyIMT } from "@zk-kit/imt.sol/LazyIMT.sol";
import { ERC1967Proxy } from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import { DevOpsTools } from "lib/foundry-devops/src/DevOpsTools.sol";
import { BaseScript } from "./Base.s.sol";
import { console } from "forge-std/console.sol";

contract DeployPriceCalculator is BaseScript {
    function run() public broadcast returns (address) {
        address _token = _getTokenAddress();
        return address(deploy(_token));
    }

    function deploy(address _token) public returns (IPriceCalculator) {
        LinearPriceCalculator priceCalculator = new LinearPriceCalculator(_token, 0.05 ether);
        return IPriceCalculator(priceCalculator);
    }

    function _getTokenAddress() internal view returns (address) {
        try vm.envAddress("TOKEN_ADDRESS") returns (address passedAddress) {
            return passedAddress;
        } catch {
            if (block.chainid == 1) {
                return 0x6B175474E89094C44Da98b954EedeAC495271d0F; // DAI address on mainnet
            } else {
                revert("no TOKEN_ADDRESS was specified");
            }
        }
    }
}

contract DeployWakuRlnV2 is BaseScript {
    function run() public broadcast returns (address) {
        return address(deploy());
    }

    function deploy() public returns (WakuRlnV2) {
        return new WakuRlnV2();
    }
}

contract DeployProxy is BaseScript {
    uint32 public constant MAX_TOTAL_RATELIMIT_PER_EPOCH = 160_000;
    uint32 public constant MIN_RATELIMIT_PER_MEMBERSHIP = 20;
    uint32 public constant MAX_RATELIMIT_PER_MEMBERSHIP = 600;
    uint32 public constant ACTIVE_DURATION = 180 days;
    uint32 public constant GRACE_PERIOD_DURATION = 30 days;

    function run() public broadcast returns (address) {
        address priceCalcAddr;
        address wakuRlnV2ImplAddr;

        try vm.envAddress("PRICE_CALCULATOR_ADDRESS") returns (address envPriceCalcAddress) {
            console.log("Loading price calculator address from environment variable");
            priceCalcAddr = envPriceCalcAddress;
        } catch {
            console.log("Loading price calculator address from broadcast directory");
            priceCalcAddr = DevOpsTools.get_most_recent_deployment("LinearPriceCalculator", block.chainid);
        }

        try vm.envAddress("WAKURLNV2_ADDRESS") returns (address envWakuRlnV2ImplAddr) {
            console.log("Loading WakuRlnV2 address from environment variable");
            wakuRlnV2ImplAddr = envWakuRlnV2ImplAddr;
        } catch {
            console.log("Loading WakuRlnV2 address from broadcast directory");
            wakuRlnV2ImplAddr = DevOpsTools.get_most_recent_deployment("WakuRlnV2", block.chainid);
        }

        console.log("Using price calculator address: %s", priceCalcAddr);
        console.log("Using WakuRLNV2 address: %s", wakuRlnV2ImplAddr);

        return address(deploy(priceCalcAddr, wakuRlnV2ImplAddr));
    }

    function deploy(address _priceCalcAddr, address _wakuRlnV2ImplAddr) public returns (ERC1967Proxy) {
        bytes memory data = abi.encodeCall(
            WakuRlnV2.initialize,
            (
                _priceCalcAddr,
                MAX_TOTAL_RATELIMIT_PER_EPOCH,
                MIN_RATELIMIT_PER_MEMBERSHIP,
                MAX_RATELIMIT_PER_MEMBERSHIP,
                ACTIVE_DURATION,
                GRACE_PERIOD_DURATION
            )
        );
        return new ERC1967Proxy(_wakuRlnV2ImplAddr, data);
    }
}

contract DeployLibs is BaseScript {
    function run() public broadcast returns (address poseidonT3, address lazyImt) {
        bytes memory poseidonT3Bytecode = type(PoseidonT3).creationCode;
        assembly {
            poseidonT3 := create(0, add(poseidonT3Bytecode, 0x20), mload(poseidonT3Bytecode))
        }

        bytes memory lazyImtBytecode = type(LazyIMT).creationCode;
        assembly {
            lazyImt := create(0, add(lazyImtBytecode, 0x20), mload(lazyImtBytecode))
        }
    }
}
