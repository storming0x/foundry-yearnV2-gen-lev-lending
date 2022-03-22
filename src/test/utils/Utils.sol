// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.12;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IVault, StrategyParams} from "../../interfaces/Vault.sol";
import {Vm} from "forge-std/Vm.sol";
import {ExtendedDSTest} from "./ExtendedDSTest.sol";
import {Strategy} from "../../Strategy.sol";
import "forge-std/console.sol";

contract Utils is ExtendedDSTest {
    Vm public constant vm_std_cheats =
        Vm(address(uint160(uint256(keccak256("hevm cheat code")))));

    function strategyStatus(IVault _vault, Strategy _strategy) public {
        StrategyParams memory status = _vault.strategies(address(_strategy));
        (uint256 lend, uint256 borrow) = _strategy.getCurrentPosition();
        uint256 ratio = _strategy.getCurrentCollatRatio();

        console.log("--- Strategy", _strategy.name(), " ---");
        console.log("Performance fee", status.performanceFee);
        console.log("Debt Ratio", status.debtRatio);
        console.log("Total Debt", toUnits(_vault, status.totalDebt));
        console.log("Total Gain", toUnits(_vault, status.totalGain));
        console.log("Total Loss", toUnits(_vault, status.totalLoss));
        console.log(
            "Estimated Total Assets",
            toUnits(_vault, _strategy.estimatedTotalAssets())
        );
        console.log(
            "Estimated Total Reward",
            toUnits(_vault, _strategy.estimatedRewardsInWant())
        );
        console.log(
            "Loose Want",
            toUnits(_vault, _strategy.want().balanceOf(address(_strategy)))
        );
        console.log("Current Lend", toUnits(_vault, lend));
        console.log("Current Borrow", toUnits(_vault, borrow));
        // decimals expressed as 5 digit unit
        // 10000 = 1
        console.log("Current LTV Ratio", (ratio * 10000) / 10**18);
        console.log(
            "Target LTV Ratio",
            (_strategy.targetCollatRatio() * 10000) / 10**18
        );
        console.log(
            "Max LTV Ratio",
            (_strategy.maxCollatRatio() * 10000) / 10**18
        );
        console.log(
            "Max Borrow LTV Ratio",
            (_strategy.maxBorrowCollatRatio() * 10000) / 10**18
        );
    }

    function toUnits(IVault _vault, uint256 _amount)
        internal
        returns (uint256)
    {
        return (_amount / (10**_vault.decimals()));
    }
}
