// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.12;

import {StrategyFixture} from "./utils/StrategyFixture.sol";

contract StrategyRestrictedFn is StrategyFixture {
    function setUp() public override {
        super.setUp();
    }

    function testRestrictedFnUser(uint256 _amount) public {
        // TODO: add all the external functions that should not be callable by a user (if any)
        // vm_std_cheats.expectRevert(!authorized);
        // vm_std_cheats.prank(user);
        // strategy.setter(arg1, arg2);
        // NO FUNCTIONS THAT CHANGE STRATEGY BEHAVIOR SHOULD BE CALLABLE FROM A USER
        // thus, this may not be used
        // TODO: add all the external functions that should be callably by a user (if any)
        // vm_std_cheats.prank(user);
        // strategy.setter(arg1, arg2);
    }

    function testRestrictedFnManagement(uint256 _amount) public {
        // ONLY FUNCTIONS THAT DO NOT HAVE RUG POTENTIAL SHOULD BE CALLABLE BY MANAGEMENT
        // (e.g. a change of 3rd party contract => rug potential)
        // (e.g. a change in leverage ratio => no rug potential)
        // TODO: add all the external functions that should not be callable by management (if any)
        // vm_std_cheats.expectRevert(!authorized);
        // vm_std_cheats.prank(management);
        // strategy.setter(arg1, arg2);
        // Functions that are required to unwind a strategy should go be callable by management
        // TODO: add all the external functions that should be callably by management (if any)
        // vm_std_cheats.prank(management);
        // strategy.setter(arg1, arg2);
    }

    function testRestrictedFnGovernance(uint256 _amount) public {
        // OPTIONAL: No functions are required to not be callable from governance so this may not be used
        // TODO: add all the external functions that should not be callable by governance (if any)
        // vm_std_cheats.expectRevert(!authorized);
        // vm_std_cheats.prank(gov);
        // strategy.setter(arg1, arg2);
        // All setter functions should be callable by governance
        // TODO: add all the external functions that should be callably by governance (if any)
        // vm_std_cheats.prank(gov);
        // strategy.setter(arg1, arg2);
    }
}
