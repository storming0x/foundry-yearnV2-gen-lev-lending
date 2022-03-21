// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.12;

import {IVault, StrategyParams} from "../../interfaces/Vault.sol";
import {Vm} from "forge-std/Vm.sol";
import {ExtendedDSTest} from "./ExtendedDSTest.sol";
import {Strategy} from "../../Strategy.sol";

contract Checks is ExtendedDSTest {
    Vm public constant vm_std_cheats =
        Vm(address(uint160(uint256(keccak256("hevm cheat code")))));

    function checkRevokedStrategy(IVault _vault, Strategy _strategy) public {
        StrategyParams memory status = _vault.strategies(address(_strategy));
        assertEq(status.debtRatio, 0);
        assertEq(status.totalDebt, 0);
    }

    function checkAccounting(
        IVault _vault,
        Strategy _strategy,
        uint256 _totalGain,
        uint256 _totalLoss,
        uint256 _totalDebt,
        uint256 _delta
    ) public {
        // inputs have to be manually calculated then checked
        StrategyParams memory status = _vault.strategies(address(_strategy));
        assertRelApproxEq(status.totalGain, _totalGain, _delta);
        assertRelApproxEq(status.totalLoss, _totalLoss, _delta);
        assertRelApproxEq(status.totalDebt, _totalDebt, _delta);
    }
}
