// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.12;
import "forge-std/console.sol";

import {IProtocolDataProvider} from "../interfaces/aave/IProtocolDataProvider.sol";
import {StrategyFixture} from "./utils/StrategyFixture.sol";
import {Strategy} from "../Strategy.sol";

contract StrategyOperationsTest is StrategyFixture {
    // setup is run on before each test
    function setUp() public override {
        // setup vault
        super.setUp();
    }

    function testSetupVaultOK() public {
        console.log("address of vault", address(vault));
        assertTrue(address(0) != address(vault));
        assertEq(vault.token(), address(want));
        assertEq(vault.depositLimit(), type(uint256).max);
    }

    // TODO: add additional check on strat params
    function testSetupStrategyOK() public {
        console.log("address of strategy", address(strategy));
        assertTrue(address(0) != address(strategy));
        assertEq(address(strategy.vault()), address(vault));
    }

    /// Test Operations
    function testOperation(uint256 _amount) public {
        vm_std_cheats.assume(_amount > minFuzzAmt && _amount < maxFuzzAmt);
        tip(address(want), address(user), _amount);

        // Deposit to the vault
        uint256 balanceBefore = want.balanceOf(address(user));
        actions.userDeposit(user, vault, want, _amount);

        // harvest
        skip(1);
        vm_std_cheats.prank(strategist);
        strategy.harvest();
        assertRelApproxEq(strategy.estimatedTotalAssets(), _amount, DELTA);

        utils.strategyStatus(vault, strategy);

        // tend()
        vm_std_cheats.prank(strategist);
        strategy.tend();

        utils.strategyStatus(vault, strategy);

        vm_std_cheats.prank(user);
        vault.withdraw();
        assertRelApproxEq(want.balanceOf(user), balanceBefore, DELTA);
    }

    // function testWithdraw(uint256 _amount, bool _isFlashLoanActive) public {
    //     vm_std_cheats.assume(_amount > minFuzzAmt && _amount < maxFuzzAmt);
    //     tip(address(want), address(user), _amount);

    //     // Deposit to the vault
    //     uint256 balanceBefore = want.balanceOf(user);
    //     actions.userDeposit(user, vault, want, _amount);

    //     // harvest
    //     skip(1);
    //     vm_std_cheats.prank(strategist);
    //     strategy.harvest();
    //     assertRelApproxEq(strategy.estimatedTotalAssets(), _amount, DELTA);

    //     skip(1 days);
    //     utils.strategyStatus(vault, strategy);
    //     vm_std_cheats.prank(strategist);
    //     strategy.harvest();
    //     skip(6 hours);

    //     vm_std_cheats.prank(gov);
    //     strategy.setIsFlashMintActive(_isFlashLoanActive);
    //     // remove this statement
    //     if (!_isFlashLoanActive) {
    //         vm_std_cheats.startPrank(gov);
    //         strategy.setCollateralTargets(
    //             strategy.maxBorrowCollatRatio() - ((2 * 10**18) / 100),
    //             strategy.maxCollatRatio(),
    //             strategy.maxBorrowCollatRatio(),
    //             strategy.daiBorrowCollatRatio()
    //         );
    //         vm_std_cheats.stopPrank();
    //     }

    //     // withdrawal
    //     for (uint256 i = 1; i < 10; i++) {
    //         console.log(i);
    //         utils.strategyStatus(vault, strategy);
    //         vm_std_cheats.prank(user);
    //         vault.withdraw(uint256(_amount / 10), user, 10_000);
    //         assertGe(want.balanceOf(user), (balanceBefore * i) / 10);
    //     }

    //     skip(1);
    //     vm_std_cheats.prank(strategist);
    //     strategy.harvest();
    //     skip(6 hours);
    //     vm_std_cheats.prank(user);
    //     vault.withdraw(uint256(_amount / 10));
    //     assertGt(want.balanceOf(user), balanceBefore);
    //     utils.strategyStatus(vault, strategy);
    // }

    // @dev See https://github.com/gakonst/foundry/issues/871
    //      on how to fuzz enums in foundry
    function testApr(uint256 _amount, uint8 _swapRouter) public {
        vm_std_cheats.assume(_amount > minFuzzAmt && _amount < maxFuzzAmt);
        vm_std_cheats.assume(_swapRouter <= 2);
        Strategy.SwapRouter sr = Strategy.SwapRouter(_swapRouter);
        tip(address(want), address(user), _amount);

        vm_std_cheats.startPrank(gov);
        strategy.setRewardBehavior(
            sr,
            strategy.sellStkAave(),
            strategy.cooldownStkAave(),
            strategy.minRewardToSell(),
            strategy.maxStkAavePriceImpactBps(),
            strategy.stkAaveToAaveSwapFee(),
            strategy.aaveToWethSwapFee(),
            strategy.wethToWantSwapFee()
        );
        vm_std_cheats.stopPrank();

        // Deposit to the vault
        actions.userDeposit(user, vault, want, _amount);

        // harvest
        skip(1);
        vm_std_cheats.prank(strategist);
        strategy.harvest();
        assertRelApproxEq(strategy.estimatedTotalAssets(), _amount, DELTA);

        skip(1 weeks);

        vm_std_cheats.prank(gov);
        vault.revokeStrategy(address(strategy));
        vm_std_cheats.prank(strategist);
        strategy.harvest();
        int256 apr = ((int256(want.balanceOf(address(vault))) -
            int256(_amount)) *
            52 *
            100) / int256(_amount);
        uint256 total = _amount / (10**vault.decimals());
        console.log("APR:");
        console.logInt(apr);
        console.log("on ", total);
    }

    // function testAprWithCooldown(uint256 _amount) public {
    //     vm_std_cheats.assume(_amount > minFuzzAmt && _amount < maxFuzzAmt);
    //     tip(address(want), address(user), _amount);

    //     // Don't sell stkAave, cool it down
    //     vm_std_cheats.startPrank(gov);
    //     strategy.setRewardBehavior(
    //         Strategy.SwapRouter(1),
    //         false,
    //         true,
    //         strategy.minRewardToSell(),
    //         strategy.maxStkAavePriceImpactBps(),
    //         strategy.stkAaveToAaveSwapFee(),
    //         strategy.aaveToWethSwapFee(),
    //         strategy.wethToWantSwapFee()
    //     );
    //     vm_std_cheats.stopPrank();

    //     // harvest
    //     skip(1);
    //     vm_std_cheats.prank(strategist);
    //     strategy.harvest();
    //     assertRelApproxEq(strategy.estimatedTotalAssets(), _amount, DELTA);

    //     skip(7 days);
    //     vm_std_cheats.prank(gov);
    //     vault.revokeStrategy(address(strategy));
    //     vm_std_cheats.prank(strategist);
    //     strategy.harvest();

    //     skip(101 days / 10);

    //     vm_std_cheats.prank(strategist);
    //     strategy.harvest();
    //     int256 apr = ((int256(want.balanceOf(address(vault))) -
    //         int256(_amount)) *
    //         52 *
    //         100) / int256(_amount);
    //     uint256 total = _amount / (10**vault.decimals());
    //     console.log("APR:");
    //     console.logInt(apr);
    //     console.log("on ", total);
    // }

    // function testHarvestAfterLongIdlePeriod(uint256 _amount) public {
    //     vm_std_cheats.assume(_amount > minFuzzAmt && _amount < maxFuzzAmt);
    //     tip(address(want), address(user), _amount);

    //     // Deposit to the vault
    //     actions.userDeposit(user, vault, want, _amount);

    //     // harvest
    //     skip(1);
    //     vm_std_cheats.prank(strategist);
    //     strategy.harvest();
    //     assertRelApproxEq(strategy.estimatedTotalAssets(), _amount, DELTA);

    //     utils.strategyStatus(vault, strategy);
    //     skip(26 weeks);
    //     utils.strategyStatus(vault, strategy);

    //     vm_std_cheats.prank(strategist);
    //     strategy.harvest();

    //     utils.strategyStatus(vault, strategy);
    // }

    function testEmergencyExit(uint256 _amount) public {
        vm_std_cheats.assume(_amount > minFuzzAmt && _amount < maxFuzzAmt);
        tip(address(want), address(user), _amount);

        // Deposit to the vault
        actions.userDeposit(user, vault, want, _amount);
        skip(1);
        vm_std_cheats.prank(strategist);
        strategy.harvest();
        assertRelApproxEq(strategy.estimatedTotalAssets(), _amount, DELTA);

        // set emergency and exit
        vm_std_cheats.prank(strategist);
        strategy.setEmergencyExit();
        skip(1);
        vm_std_cheats.prank(strategist);
        strategy.harvest();
        assertLt(strategy.estimatedTotalAssets(), _amount);
    }

    function testIncreaseDebtRatio(uint256 _amount, uint16 _startingDebtRatio)
        public
    {
        vm_std_cheats.assume(_amount > minFuzzAmt && _amount < maxFuzzAmt);
        vm_std_cheats.assume(
            _startingDebtRatio >= 100 && _startingDebtRatio < 10_000
        );
        uint256 startingDebtRatio = uint256(_startingDebtRatio);
        tip(address(want), address(user), _amount);

        // Deposit to the vault and harvest
        actions.userDeposit(user, vault, want, _amount);
        vm_std_cheats.prank(gov);
        vault.updateStrategyDebtRatio(address(strategy), startingDebtRatio);
        skip(1);
        vm_std_cheats.prank(strategist);
        strategy.harvest();
        uint256 partAmount = uint256((_amount * startingDebtRatio) / 10_000);

        utils.strategyStatus(vault, strategy);

        assertRelApproxEq(strategy.estimatedTotalAssets(), partAmount, DELTA);

        vm_std_cheats.prank(gov);
        vault.updateStrategyDebtRatio(address(strategy), 10_000);
        skip(1);
        vm_std_cheats.prank(strategist);
        strategy.harvest();

        utils.strategyStatus(vault, strategy);

        assertRelApproxEq(strategy.estimatedTotalAssets(), _amount, DELTA);
    }

    function testDecreaseDebtRatio(uint256 _amount, uint16 _endingDebtRatio)
        public
    {
        vm_std_cheats.assume(_amount > minFuzzAmt && _amount < maxFuzzAmt);
        vm_std_cheats.assume(
            _endingDebtRatio >= 100 && _endingDebtRatio < 10_000
        );
        uint256 endingDebtRatio = uint256(_endingDebtRatio);
        tip(address(want), address(user), _amount);

        // Deposit to the vault and harvest
        actions.userDeposit(user, vault, want, _amount);
        vm_std_cheats.prank(gov);
        vault.updateStrategyDebtRatio(address(strategy), 10_000);
        skip(1);
        vm_std_cheats.prank(strategist);
        strategy.harvest();

        utils.strategyStatus(vault, strategy);

        assertRelApproxEq(strategy.estimatedTotalAssets(), _amount, DELTA);

        // Two harvests needed to unlock
        vm_std_cheats.prank(gov);
        vault.updateStrategyDebtRatio(address(strategy), endingDebtRatio);
        skip(1);
        vm_std_cheats.prank(strategist);
        strategy.harvest();

        utils.strategyStatus(vault, strategy);

        uint256 partAmount = uint256((_amount * endingDebtRatio) / 10_000);
        assertRelApproxEq(strategy.estimatedTotalAssets(), partAmount, DELTA);
    }

    function testLargeDeleverage(uint256 _amount) public {
        vm_std_cheats.assume(_amount > minFuzzAmt && _amount < maxFuzzAmt);
        tip(address(want), address(user), _amount);

        // Deposit to the vault and harvest
        actions.userDeposit(user, vault, want, _amount);
        vm_std_cheats.prank(gov);
        vault.updateStrategyDebtRatio(address(strategy), 10_000);
        skip(1);
        vm_std_cheats.prank(strategist);
        strategy.harvest();

        utils.strategyStatus(vault, strategy);

        assertRelApproxEq(strategy.estimatedTotalAssets(), _amount, DELTA);

        // Two harvests needed to unlock
        vm_std_cheats.prank(gov);
        vault.updateStrategyDebtRatio(address(strategy), 1_000);
        skip(1);
        vm_std_cheats.prank(strategist);
        strategy.harvest();

        utils.strategyStatus(vault, strategy);

        uint256 tenth = uint256(_amount / 10);
        assertRelApproxEq(strategy.estimatedTotalAssets(), tenth, DELTA);
    }

    function testLargerDeleverage(uint256 _amount) public {
        vm_std_cheats.assume(_amount > minFuzzAmt && _amount < maxFuzzAmt);
        tip(address(want), address(user), _amount);

        // Deposit to the vault and harvest
        actions.userDeposit(user, vault, want, _amount);
        vm_std_cheats.prank(gov);
        vault.updateStrategyDebtRatio(address(strategy), 10_000);
        skip(1);
        vm_std_cheats.prank(strategist);
        strategy.harvest();

        utils.strategyStatus(vault, strategy);

        assertRelApproxEq(strategy.estimatedTotalAssets(), _amount, DELTA);

        vm_std_cheats.prank(gov);
        vault.updateStrategyDebtRatio(address(strategy), 1_000);
        uint256 i = 0;
        while (vault.debtOutstanding(address(strategy)) > 0 && i < 5) {
            skip(1);
            vm_std_cheats.prank(strategist);
            strategy.harvest();
            utils.strategyStatus(vault, strategy);
            i++;
        }

        uint256 tenth = uint256(_amount / 10);
        assertRelApproxEq(strategy.estimatedTotalAssets(), tenth, DELTA);
    }

    function testSweep(uint256 _amount) public {
        vm_std_cheats.assume(_amount > minFuzzAmt && _amount < maxFuzzAmt);
        tip(address(want), address(user), _amount);

        // Strategy want token doesn't work
        vm_std_cheats.prank(user);
        want.transfer(address(strategy), _amount);
        assertEq(address(want), address(strategy.want()));
        assertGt(want.balanceOf(address(strategy)), 0);
        vm_std_cheats.prank(gov);
        vm_std_cheats.expectRevert("!want");
        strategy.sweep(address(want));

        // Vault share token doesn't work
        vm_std_cheats.prank(gov);
        vm_std_cheats.expectRevert("!shares");
        strategy.sweep(address(vault));

        uint256 beforeBalance = weth.balanceOf(gov) +
            weth.balanceOf(address(strategy));
        uint256 wethAmount = 1 ether;
        tip(address(weth), address(user), wethAmount);
        // strategy has some weth to pay for flashloans
        vm_std_cheats.prank(user);
        weth.transfer(address(strategy), wethAmount);
        assertNeq(address(weth), address(strategy.want()));
        assertEq(weth.balanceOf(user), 0);
        vm_std_cheats.prank(gov);
        strategy.sweep(address(weth));
        assertEq(weth.balanceOf(gov), wethAmount + beforeBalance);
    }

    function testTriggers(uint256 _amount) public {
        vm_std_cheats.assume(_amount > minFuzzAmt && _amount < maxFuzzAmt);
        tip(address(want), address(user), _amount);

        // Deposit to the vault and harvest
        actions.userDeposit(user, vault, want, _amount);
        vm_std_cheats.prank(gov);
        vault.updateStrategyDebtRatio(address(strategy), 5_000);
        skip(1);
        vm_std_cheats.prank(strategist);
        strategy.harvest();

        strategy.harvestTrigger(0);
        strategy.tendTrigger(0);
    }

    function testTend(uint256 _amount) public {
        vm_std_cheats.assume(_amount > minFuzzAmt && _amount < maxFuzzAmt);
        tip(address(want), address(user), _amount);

        // Deposit to the vault and harvest
        actions.userDeposit(user, vault, want, _amount);
        skip(1);
        vm_std_cheats.prank(strategist);
        strategy.harvest();

        (
            ,
            ,
            uint256 liquidationThreshold,
            ,
            ,
            ,
            ,
            ,
            ,

        ) = IProtocolDataProvider(0x057835Ad21a177dbdd3090bB1CAE03EaCF78Fc6d)
                .getReserveConfigurationData(address(want));
        (uint256 deposits, uint256 borrows) = strategy.getCurrentPosition();
        uint256 theoDeposits = (borrows * 1e4) / (liquidationThreshold - 90);
        uint256 toLose = uint256(deposits - theoDeposits);

        utils.strategyStatus(vault, strategy);
        actions.generateLoss(strategy, toLose);
        utils.strategyStatus(vault, strategy);

        // prevent harvestTrigger
        vm_std_cheats.prank(strategist);
        strategy.setDebtThreshold((toLose * 110) / 100);

        assertTrue(strategy.tendTrigger(0));

        vm_std_cheats.prank(strategist);
        strategy.tend();

        utils.strategyStatus(vault, strategy);
        assertTrue(!strategy.tendTrigger(0));
        assertRelApproxEq(
            strategy.getCurrentCollatRatio(),
            strategy.targetCollatRatio(),
            DELTA
        );
    }
}
