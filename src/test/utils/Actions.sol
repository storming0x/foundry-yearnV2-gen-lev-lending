// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.12;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IVault} from "../../interfaces/Vault.sol";
import {Vm} from "forge-std/Vm.sol";
import {ExtendedDSTest} from "./ExtendedDSTest.sol";
import {stdCheats} from "forge-std/stdlib.sol";

import {ILendingPool} from "../../interfaces/aave/ILendingPool.sol";
import {ILendingPoolAddressesProvider} from "../../interfaces/aave/ILendingPoolAddressesProvider.sol";
import {IProtocolDataProvider} from "../../interfaces/aave/IProtocolDataProvider.sol";
import {Strategy} from "../../Strategy.sol";

import "forge-std/console.sol";

contract Actions is ExtendedDSTest, stdCheats {
    Vm public constant vm_std_cheats =
        Vm(address(uint160(uint256(keccak256("hevm cheat code")))));

    function userDeposit(
        address _user,
        IVault _vault,
        IERC20 _want,
        uint256 _amount
    ) public {
        if (_want.allowance(_user, address(_vault)) < _amount) {
            vm_std_cheats.prank(_user);
            _want.approve(address(_vault), type(uint256).max);
        }
        vm_std_cheats.prank(_user);
        _vault.deposit(_amount);
        assertEq(_want.balanceOf(address(_vault)), _amount);
    }

    function generateProfit(
        Strategy _strategy,
        address _whale,
        uint256 _amount
    ) public {
        ILendingPool lp = ILendingPool(
            ILendingPoolAddressesProvider(
                IProtocolDataProvider(
                    0x057835Ad21a177dbdd3090bB1CAE03EaCF78Fc6d
                ).ADDRESSES_PROVIDER()
            ).getLendingPool()
        );
        address want = address(_strategy.want());
        tip(want, _whale, _amount);
        vm_std_cheats.prank(_whale);
        IERC20(want).approve(address(lp), type(uint256).max);
        vm_std_cheats.prank(_whale);
        lp.deposit(want, _amount, address(_strategy), 0);
    }

    function generateLoss(Strategy _strategy, uint256 _amount) public {
        address aToken = address(_strategy.aToken());
        vm_std_cheats.prank(address(_strategy));
        IERC20(aToken).transfer(aToken, _amount);
    }
}
