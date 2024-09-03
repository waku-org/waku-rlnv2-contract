// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.8.19 <=0.9.0;

import { WakuRlnV2 } from "../src/WakuRlnV2.sol";
import { LinearPriceCalculator } from "../src/LinearPriceCalculator.sol";
import { PoseidonT3 } from "poseidon-solidity/PoseidonT3.sol";
import { LazyIMT } from "@zk-kit/imt.sol/LazyIMT.sol";
import { ERC1967Proxy } from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import { UUPSUpgradeable } from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";

import { BaseScript } from "./Base.s.sol";

contract Deploy is BaseScript {
    function run() public broadcast returns (WakuRlnV2 w, address impl) {
        // TODO: Use the correct values when deploying to mainnet
        address priceCalcAddr = address(new LinearPriceCalculator(address(0), 0.05 ether));
        // TODO: set DAI address 0x6B175474E89094C44Da98b954EedeAC495271d0F
        impl = address(new WakuRlnV2());
        bytes memory data = abi.encodeCall(WakuRlnV2.initialize, (priceCalcAddr, 160_000, 20, 600, 30 days, 5 days));
        // (priceCalcAddr,  160000, 20, 600, 30 days, 5 days)
        address proxy = address(new ERC1967Proxy(impl, data));
        w = WakuRlnV2(proxy);
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
