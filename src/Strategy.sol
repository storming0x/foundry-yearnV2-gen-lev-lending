// SPDX-License-Identifier: AGPL-3.0
// Feel free to change the license, but this is what we use

// Feel free to change this version of Solidity. We support >=0.6.0 <0.7.0;
pragma solidity 0.8.12;
pragma experimental ABIEncoderV2;

// These are the core Yearn libraries
import {BaseStrategy} from "@yearnvaults/contracts/BaseStrategy.sol";

import {Address} from "@openzeppelin/contracts/utils/Address.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import "@openzeppelin/contracts/utils/math/Math.sol";

import "./interfaces/uniswap/IUni.sol";
import {ISwapRouter} from "./interfaces/uniswap/ISwapRouter.sol";

import "./interfaces/aave/IProtocolDataProvider.sol";
import "./interfaces/aave/IAaveIncentivesController.sol";
import "./interfaces/aave/IStakedAave.sol";
import "./interfaces/aave/IAToken.sol";
import "./interfaces/aave/IVariableDebtToken.sol";
import "./interfaces/aave/ILendingPool.sol";

import "./FlashMintLib.sol";

contract Strategy is BaseStrategy, IERC3156FlashBorrower {
    using SafeERC20 for IERC20;
    using Address for address;

    // AAVE protocol address
    IProtocolDataProvider private constant protocolDataProvider =
        IProtocolDataProvider(0x057835Ad21a177dbdd3090bB1CAE03EaCF78Fc6d);
    IAaveIncentivesController private constant incentivesController =
        IAaveIncentivesController(0xd784927Ff2f95ba542BfC824c8a8a98F3495f6b5);
    ILendingPool private constant lendingPool =
        ILendingPool(0x7d2768dE32b0b80b7a3454c06BdAc94A69DDc7A9);

    // Token addresses
    address private constant aave = 0x7Fc66500c84A76Ad7e9c93437bFc5Ac33E2DDaE9;
    IStakedAave private constant stkAave =
        IStakedAave(0x4da27a545c0c5B758a6BA100e3a049001de870f5);
    address private constant weth = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    address private constant dai = 0x6B175474E89094C44Da98b954EedeAC495271d0F;

    // Supply and borrow tokens
    IAToken public aToken;
    IVariableDebtToken public debtToken;

    // represents stkAave cooldown status
    // 0 = no cooldown or past withdraw period
    // 1 = claim period
    // 2 = cooldown initiated, future claim period
    enum CooldownStatus {
        None,
        Claim,
        Initiated
    }

    // SWAP routers
    IUni private constant UNI_V2_ROUTER =
        IUni(0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D);
    IUni private constant SUSHI_V2_ROUTER =
        IUni(0xd9e1cE17f2641f24aE83637ab66a2cca9C378B9F);
    ISwapRouter private constant UNI_V3_ROUTER =
        ISwapRouter(0xE592427A0AEce92De3Edee1F18E0157C05861564);

    // OPS State Variables
    uint256 private constant DEFAULT_COLLAT_TARGET_MARGIN = 0.02 ether;
    uint256 private constant DEFAULT_COLLAT_MAX_MARGIN = 0.005 ether;
    uint256 private constant LIQUIDATION_WARNING_THRESHOLD = 0.01 ether;

    uint256 public maxBorrowCollatRatio; // The maximum the aave protocol will let us borrow
    uint256 public targetCollatRatio; // The LTV we are levering up to
    uint256 public maxCollatRatio; // Closest to liquidation we'll risk
    uint256 public daiBorrowCollatRatio; // Used for flashmint

    uint8 public maxIterations;
    bool public isFlashMintActive;
    bool public withdrawCheck;

    uint256 public minWant;
    uint256 public minRatio;
    uint256 public minRewardToSell;

    enum SwapRouter {
        UniV2,
        SushiV2,
        UniV3
    }
    SwapRouter public swapRouter = SwapRouter.UniV2; // only applied to aave => want, stkAave => aave always uses v3

    bool public sellStkAave;
    bool public cooldownStkAave;
    uint256 public maxStkAavePriceImpactBps;

    uint24 public stkAaveToAaveSwapFee;
    uint24 public aaveToWethSwapFee;
    uint24 public wethToWantSwapFee;

    bool private alreadyAdjusted; // Signal whether a position adjust was done in prepareReturn

    uint16 private constant referral = 7; // Yearn's aave referral code

    uint256 private constant MAX_BPS = 1e4;
    uint256 private constant BPS_WAD_RATIO = 1e14;
    uint256 private constant COLLATERAL_RATIO_PRECISION = 1 ether;
    uint256 private constant PESSIMISM_FACTOR = 1000;
    uint256 private DECIMALS;

    constructor(address _vault) public BaseStrategy(_vault) {
        _initializeThis();
    }

    function initialize(
        address _vault,
        address _strategist,
        address _rewards,
        address _keeper
    ) external {
        _initialize(_vault, _strategist, _rewards, _keeper);
        _initializeThis();
    }

    function _initializeThis() internal {
        require(address(aToken) == address(0));

        // initialize operational state
        maxIterations = 6;
        isFlashMintActive = true;
        withdrawCheck = false;

        // mins
        minWant = 100;
        minRatio = 0.005 ether;
        minRewardToSell = 1e15;

        // reward params
        swapRouter = SwapRouter.UniV2;
        sellStkAave = true;
        cooldownStkAave = false;
        maxStkAavePriceImpactBps = 500;

        stkAaveToAaveSwapFee = 3000;
        aaveToWethSwapFee = 3000;
        wethToWantSwapFee = 3000;

        alreadyAdjusted = false;

        // Set aave tokens
        (address _aToken, , address _debtToken) = protocolDataProvider
            .getReserveTokensAddresses(address(want));
        aToken = IAToken(_aToken);
        debtToken = IVariableDebtToken(_debtToken);

        // Let collateral targets
        (uint256 ltv, uint256 liquidationThreshold) = getProtocolCollatRatios(
            address(want)
        );
        targetCollatRatio = liquidationThreshold - DEFAULT_COLLAT_TARGET_MARGIN;
        maxCollatRatio = liquidationThreshold - DEFAULT_COLLAT_MAX_MARGIN;
        maxBorrowCollatRatio = ltv - DEFAULT_COLLAT_MAX_MARGIN;
        (uint256 daiLtv, ) = getProtocolCollatRatios(dai);
        daiBorrowCollatRatio = daiLtv - DEFAULT_COLLAT_MAX_MARGIN;

        DECIMALS = 10**vault.decimals();

        // approve spend aave spend
        approveMaxSpend(address(want), address(lendingPool));
        approveMaxSpend(address(aToken), address(lendingPool));

        // approve flashloan spend
        address _dai = dai;
        if (address(want) != _dai) {
            approveMaxSpend(_dai, address(lendingPool));
        }
        approveMaxSpend(_dai, FlashMintLib.LENDER);

        // approve swap router spend
        approveMaxSpend(address(stkAave), address(UNI_V3_ROUTER));
        approveMaxSpend(aave, address(UNI_V2_ROUTER));
        approveMaxSpend(aave, address(SUSHI_V2_ROUTER));
        approveMaxSpend(aave, address(UNI_V3_ROUTER));
    }

    // SETTERS
    function setCollateralTargets(
        uint256 _targetCollatRatio,
        uint256 _maxCollatRatio,
        uint256 _maxBorrowCollatRatio,
        uint256 _daiBorrowCollatRatio
    ) external onlyVaultManagers {
        (uint256 ltv, uint256 liquidationThreshold) = getProtocolCollatRatios(
            address(want)
        );
        (uint256 daiLtv, ) = getProtocolCollatRatios(dai);
        require(_targetCollatRatio < liquidationThreshold);
        require(_maxCollatRatio < liquidationThreshold);
        require(_targetCollatRatio < _maxCollatRatio);
        require(_maxBorrowCollatRatio < ltv);
        require(_daiBorrowCollatRatio < daiLtv);

        targetCollatRatio = _targetCollatRatio;
        maxCollatRatio = _maxCollatRatio;
        maxBorrowCollatRatio = _maxBorrowCollatRatio;
        daiBorrowCollatRatio = _daiBorrowCollatRatio;
    }

    function setIsFlashMintActive(bool _isFlashMintActive)
        external
        onlyVaultManagers
    {
        isFlashMintActive = _isFlashMintActive;
    }

    function setWithdrawCheck(bool _withdrawCheck) external onlyVaultManagers {
        withdrawCheck = _withdrawCheck;
    }

    function setMinsAndMaxs(
        uint256 _minWant,
        uint256 _minRatio,
        uint8 _maxIterations
    ) external onlyVaultManagers {
        require(_minRatio < maxBorrowCollatRatio);
        require(_maxIterations > 0 && _maxIterations < 16);
        minWant = _minWant;
        minRatio = _minRatio;
        maxIterations = _maxIterations;
    }

    function setRewardBehavior(
        SwapRouter _swapRouter,
        bool _sellStkAave,
        bool _cooldownStkAave,
        uint256 _minRewardToSell,
        uint256 _maxStkAavePriceImpactBps,
        uint24 _stkAaveToAaveSwapFee,
        uint24 _aaveToWethSwapFee,
        uint24 _wethToWantSwapFee
    ) external onlyVaultManagers {
        require(
            _swapRouter == SwapRouter.UniV2 ||
                _swapRouter == SwapRouter.SushiV2 ||
                _swapRouter == SwapRouter.UniV3
        );
        require(_maxStkAavePriceImpactBps <= MAX_BPS);
        swapRouter = _swapRouter;
        sellStkAave = _sellStkAave;
        cooldownStkAave = _cooldownStkAave;
        minRewardToSell = _minRewardToSell;
        maxStkAavePriceImpactBps = _maxStkAavePriceImpactBps;
        stkAaveToAaveSwapFee = _stkAaveToAaveSwapFee;
        aaveToWethSwapFee = _aaveToWethSwapFee;
        wethToWantSwapFee = _wethToWantSwapFee;
    }

    function name() external view override returns (string memory) {
        return "StrategyGenLevAAVE-Flashmint";
    }

    function estimatedTotalAssets() public view override returns (uint256) {
        uint256 balanceExcludingRewards = balanceOfWant() + getCurrentSupply();

        // if we don't have a position, don't worry about rewards
        if (balanceExcludingRewards < minWant) {
            return balanceExcludingRewards;
        }

        uint256 rewards = (estimatedRewardsInWant() *
            (MAX_BPS - PESSIMISM_FACTOR)) / MAX_BPS;

        return balanceExcludingRewards + rewards;
    }

    function estimatedRewardsInWant() public view returns (uint256) {
        uint256 aaveBalance = balanceOfAave();
        uint256 stkAaveBalance = balanceOfStkAave();

        uint256 pendingRewards = incentivesController.getRewardsBalance(
            getAaveAssets(),
            address(this)
        );
        uint256 stkAaveDiscountFactor = MAX_BPS - maxStkAavePriceImpactBps;
        uint256 combinedStkAave = pendingRewards +
            (stkAaveBalance * stkAaveDiscountFactor) /
            MAX_BPS;

        return tokenToWant(aave, aaveBalance + combinedStkAave);
    }

    function prepareReturn(uint256 _debtOutstanding)
        internal
        override
        returns (
            uint256 _profit,
            uint256 _loss,
            uint256 _debtPayment
        )
    {
        // claim & sell rewards
        _claimAndSellRewards();

        // account for profit / losses
        uint256 totalDebt = vault.strategies(address(this)).totalDebt;

        // Assets immediately convertable to want only
        uint256 supply = getCurrentSupply();
        uint256 totalAssets = balanceOfWant() + supply;

        if (totalDebt > totalAssets) {
            // we have losses
            unchecked {
                _loss = totalDebt - totalAssets;
            }
        } else {
            // we have profit
            unchecked {
                _profit = totalAssets - totalDebt;
            }
        }

        // free funds to repay debt + profit to the strategy
        uint256 amountAvailable = balanceOfWant();
        uint256 amountRequired = _debtOutstanding + _profit;

        if (amountRequired > amountAvailable) {
            // we need to free funds
            // we dismiss losses here, they cannot be generated from withdrawal
            // but it is possible for the strategy to unwind full position
            (amountAvailable, ) = liquidatePosition(amountRequired);

            // Don't do a redundant adjustment in adjustPosition
            alreadyAdjusted = true;

            if (amountAvailable >= amountRequired) {
                _debtPayment = _debtOutstanding;
                // profit remains unchanged unless there is not enough to pay it
                if (amountRequired - _debtPayment < _profit) {
                    _profit = amountRequired - _debtPayment;
                }
            } else {
                // we were not able to free enough funds
                if (amountAvailable < _debtOutstanding) {
                    // available funds are lower than the repayment that we need to do
                    _profit = 0;
                    _debtPayment = amountAvailable;
                    // we dont report losses here as the strategy might not be able to return in this harvest
                    // but it will still be there for the next harvest
                } else {
                    // NOTE: amountRequired is always equal or greater than _debtOutstanding
                    // important to use amountRequired just in case amountAvailable is > amountAvailable
                    _debtPayment = _debtOutstanding;
                    _profit = amountAvailable - _debtPayment;
                }
            }
        } else {
            _debtPayment = _debtOutstanding;
            // profit remains unchanged unless there is not enough to pay it
            if (amountRequired - _debtPayment < _profit) {
                _profit = amountRequired - _debtPayment;
            }
        }
    }

    function adjustPosition(uint256 _debtOutstanding) internal override {
        if (alreadyAdjusted) {
            alreadyAdjusted = false; // reset for next time
            return;
        }

        uint256 wantBalance = balanceOfWant();
        // deposit available want as collateral
        if (
            wantBalance > _debtOutstanding &&
            (wantBalance - _debtOutstanding) > minWant
        ) {
            _depositCollateral(wantBalance - _debtOutstanding);
            // we update the value
            wantBalance = balanceOfWant();
        }
        // check current position
        uint256 currentCollatRatio = getCurrentCollatRatio();

        // Either we need to free some funds OR we want to be max levered
        if (_debtOutstanding > wantBalance) {
            // we should free funds
            unchecked {
                uint256 amountRequired = _debtOutstanding - wantBalance;
                // NOTE: vault will take free funds during the next harvest
                _freeFunds(amountRequired);
            }
        } else if (currentCollatRatio < targetCollatRatio) {
            // we should lever up
            if (targetCollatRatio - currentCollatRatio > minRatio) {
                // we only act on relevant differences
                _leverMax();
            }
        } else if (currentCollatRatio > targetCollatRatio) {
            if (currentCollatRatio - targetCollatRatio > minRatio) {
                (uint256 deposits, uint256 borrows) = getCurrentPosition();
                uint256 newBorrow = getBorrowFromSupply(
                    deposits - borrows,
                    targetCollatRatio
                );
                _leverDownTo(newBorrow, borrows);
            }
        }
    }

    function liquidatePosition(uint256 _amountNeeded)
        internal
        override
        returns (uint256 _liquidatedAmount, uint256 _loss)
    {
        // NOTE: Maintain invariant `want.balanceOf(this) >= _liquidatedAmount`
        // NOTE: Maintain invariant `_liquidatedAmount + _loss <= _amountNeeded`
        uint256 wantBalance = balanceOfWant();
        if (wantBalance > _amountNeeded) {
            // if there is enough free want, let's use it
            return (_amountNeeded, 0);
        }

        // we need to free funds
        uint256 amountRequired = _amountNeeded - wantBalance;
        _freeFunds(amountRequired);

        uint256 freeAssets = balanceOfWant();
        if (_amountNeeded > freeAssets) {
            _liquidatedAmount = freeAssets;
            uint256 diff = _amountNeeded - _liquidatedAmount;
            if (diff <= minWant) {
                _loss = diff;
            }
        } else {
            _liquidatedAmount = _amountNeeded;
        }

        if (withdrawCheck) {
            require(_amountNeeded == _liquidatedAmount - _loss); // dev: withdraw safety check
        }
    }

    function tendTrigger(uint256 gasCost) public view override returns (bool) {
        if (harvestTrigger(gasCost)) {
            //harvest takes priority
            return false;
        }
        // pull the liquidation liquidationThreshold from aave to be extra safu
        (, uint256 liquidationThreshold) = getProtocolCollatRatios(
            address(want)
        );

        uint256 currentCollatRatio = getCurrentCollatRatio();

        if (currentCollatRatio >= liquidationThreshold) {
            return true;
        }

        return
            (liquidationThreshold - currentCollatRatio) <=
            LIQUIDATION_WARNING_THRESHOLD;
    }

    function liquidateAllPositions()
        internal
        override
        returns (uint256 _amountFreed)
    {
        (_amountFreed, ) = liquidatePosition(type(uint256).max);
    }

    function prepareMigration(address _newStrategy) internal override {
        require(getCurrentSupply() < minWant);
    }

    function protectedTokens()
        internal
        view
        override
        returns (address[] memory)
    {}

    //emergency function that we can use to deleverage manually if something is broken
    function manualDeleverage(uint256 amount) external onlyVaultManagers {
        _withdrawCollateral(amount);
        _repayWant(amount);
    }

    //emergency function that we can use to deleverage manually if something is broken
    function manualReleaseWant(uint256 amount) external onlyVaultManagers {
        _withdrawCollateral(amount);
    }

    // emergency function that we can use to sell rewards if something is broken
    function manualClaimAndSellRewards() external onlyVaultManagers {
        _claimAndSellRewards();
    }

    // INTERNAL ACTIONS

    function _claimAndSellRewards() internal returns (uint256) {
        uint256 stkAaveBalance = balanceOfStkAave();
        CooldownStatus cooldownStatus;
        if (stkAaveBalance > 0) {
            cooldownStatus = _checkCooldown(); // don't check status if we have no stkAave
        }

        // If it's the claim period claim
        if (stkAaveBalance > 0 && cooldownStatus == CooldownStatus.Claim) {
            // redeem AAVE from stkAave
            stkAave.claimRewards(address(this), type(uint256).max);
            stkAave.redeem(address(this), stkAaveBalance);
        }

        // claim stkAave from lending and borrowing, this will reset the cooldown
        incentivesController.claimRewards(
            getAaveAssets(),
            type(uint256).max,
            address(this)
        );

        stkAaveBalance = balanceOfStkAave();

        // request start of cooldown period, if there's no cooldown in progress
        if (
            cooldownStkAave &&
            stkAaveBalance > 0 &&
            cooldownStatus == CooldownStatus.None
        ) {
            stkAave.cooldown();
        }

        // Always keep 1 wei to get around cooldown clear
        if (sellStkAave && stkAaveBalance >= minRewardToSell + 1) {
            uint256 minAAVEOut = (stkAaveBalance *
                (MAX_BPS - maxStkAavePriceImpactBps)) / MAX_BPS;
            _sellSTKAAVEToAAVE(stkAaveBalance - 1, minAAVEOut);
        }

        // sell AAVE for want
        uint256 aaveBalance = balanceOfAave();
        if (aaveBalance >= minRewardToSell) {
            _sellAAVEForWant(aaveBalance, 0);
        }
    }

    function _freeFunds(uint256 amountToFree) internal returns (uint256) {
        if (amountToFree == 0) return 0;

        (uint256 deposits, uint256 borrows) = getCurrentPosition();

        uint256 realAssets = deposits - borrows;
        uint256 amountRequired = Math.min(amountToFree, realAssets);
        uint256 newSupply = realAssets - amountRequired;
        uint256 newBorrow = getBorrowFromSupply(newSupply, targetCollatRatio);

        // repay required amount
        _leverDownTo(newBorrow, borrows);

        return balanceOfWant();
    }

    function _leverMax() internal {
        (uint256 deposits, uint256 borrows) = getCurrentPosition();

        // NOTE: decimals should cancel out
        uint256 realSupply = deposits - borrows;
        uint256 newBorrow = getBorrowFromSupply(realSupply, targetCollatRatio);
        uint256 totalAmountToBorrow = newBorrow - borrows;

        if (isFlashMintActive) {
            // The best approach is to lever up using regular method, then finish with flash loan
            totalAmountToBorrow =
                totalAmountToBorrow -
                _leverUpStep(totalAmountToBorrow);

            if (totalAmountToBorrow > minWant) {
                totalAmountToBorrow =
                    totalAmountToBorrow -
                    _leverUpFlashLoan(totalAmountToBorrow);
            }
        } else {
            for (
                uint8 i = 0;
                i < maxIterations && totalAmountToBorrow > minWant;
                i++
            ) {
                totalAmountToBorrow =
                    totalAmountToBorrow -
                    _leverUpStep(totalAmountToBorrow);
            }
        }
    }

    function _leverUpFlashLoan(uint256 amount) internal returns (uint256) {
        (uint256 deposits, uint256 borrows) = getCurrentPosition();
        uint256 depositsToMeetLtv = getDepositFromBorrow(
            borrows,
            maxBorrowCollatRatio
        );
        uint256 depositsDeficitToMeetLtv = 0;
        if (depositsToMeetLtv > deposits) {
            unchecked {
                depositsDeficitToMeetLtv = depositsToMeetLtv - deposits;
            }
        }
        return
            FlashMintLib.doFlashMint(
                false,
                amount,
                address(want),
                daiBorrowCollatRatio,
                depositsDeficitToMeetLtv
            );
    }

    function _leverUpStep(uint256 amount) internal returns (uint256) {
        if (amount == 0) {
            return 0;
        }

        uint256 wantBalance = balanceOfWant();

        // calculate how much borrow can I take
        (uint256 deposits, uint256 borrows) = getCurrentPosition();
        uint256 canBorrow = getBorrowFromDeposit(
            deposits + wantBalance,
            maxBorrowCollatRatio
        );

        if (canBorrow <= borrows) {
            return 0;
        }
        canBorrow = canBorrow - borrows;

        if (canBorrow < amount) {
            amount = canBorrow;
        }

        // deposit available want as collateral
        _depositCollateral(wantBalance);

        // borrow available amount
        _borrowWant(amount);

        return amount;
    }

    function _leverDownTo(uint256 newAmountBorrowed, uint256 currentBorrowed)
        internal
    {
        if (currentBorrowed > newAmountBorrowed) {
            uint256 totalRepayAmount = currentBorrowed - newAmountBorrowed;

            if (isFlashMintActive) {
                totalRepayAmount =
                    totalRepayAmount -
                    _leverDownFlashLoan(totalRepayAmount);
            }

            uint256 _maxCollatRatio = maxCollatRatio;

            for (
                uint8 i = 0;
                i < maxIterations && totalRepayAmount > minWant;
                i++
            ) {
                _withdrawExcessCollateral(_maxCollatRatio);
                uint256 toRepay = totalRepayAmount;
                uint256 wantBalance = balanceOfWant();
                if (toRepay > wantBalance) {
                    toRepay = wantBalance;
                }
                uint256 repaid = _repayWant(toRepay);
                totalRepayAmount = totalRepayAmount - repaid;
            }
        }

        // deposit back to get targetCollatRatio (we always need to leave this in this ratio)
        (uint256 deposits, uint256 borrows) = getCurrentPosition();
        uint256 _targetCollatRatio = targetCollatRatio;
        uint256 targetDeposit = getDepositFromBorrow(
            borrows,
            _targetCollatRatio
        );
        if (targetDeposit > deposits) {
            unchecked {
                uint256 toDeposit = targetDeposit - deposits;
                if (toDeposit > minWant) {
                    _depositCollateral(Math.min(toDeposit, balanceOfWant()));
                }
            }
        } else {
            _withdrawExcessCollateral(_targetCollatRatio);
        }
    }

    function _leverDownFlashLoan(uint256 amount) internal returns (uint256) {
        if (amount <= minWant) return 0;
        (, uint256 borrows) = getCurrentPosition();
        if (amount > borrows) {
            amount = borrows;
        }
        return
            FlashMintLib.doFlashMint(
                true,
                amount,
                address(want),
                daiBorrowCollatRatio,
                0
            );
    }

    function _withdrawExcessCollateral(uint256 collatRatio)
        internal
        returns (uint256 amount)
    {
        (uint256 deposits, uint256 borrows) = getCurrentPosition();
        uint256 theoDeposits = getDepositFromBorrow(borrows, collatRatio);
        if (deposits > theoDeposits) {
            unchecked {
                uint256 toWithdraw = deposits - theoDeposits;
                return _withdrawCollateral(toWithdraw);
            }
        }
    }

    function _depositCollateral(uint256 amount) internal returns (uint256) {
        if (amount == 0) return 0;
        lendingPool.deposit(address(want), amount, address(this), referral);
        return amount;
    }

    function _withdrawCollateral(uint256 amount) internal returns (uint256) {
        if (amount == 0) return 0;
        lendingPool.withdraw(address(want), amount, address(this));
        return amount;
    }

    function _repayWant(uint256 amount) internal returns (uint256) {
        if (amount == 0) return 0;
        return lendingPool.repay(address(want), amount, 2, address(this));
    }

    function _borrowWant(uint256 amount) internal returns (uint256) {
        if (amount == 0) return 0;
        lendingPool.borrow(address(want), amount, 2, referral, address(this));
        return amount;
    }

    // INTERNAL VIEWS
    function balanceOfWant() internal view returns (uint256) {
        return want.balanceOf(address(this));
    }

    function balanceOfAToken() internal view returns (uint256) {
        return aToken.balanceOf(address(this));
    }

    function balanceOfDebtToken() internal view returns (uint256) {
        return debtToken.balanceOf(address(this));
    }

    function balanceOfAave() internal view returns (uint256) {
        return IERC20(aave).balanceOf(address(this));
    }

    function balanceOfStkAave() internal view returns (uint256) {
        return IERC20(address(stkAave)).balanceOf(address(this));
    }

    function onFlashLoan(
        address initiator,
        address token,
        uint256 amount,
        uint256 fee,
        bytes calldata data
    ) external override returns (bytes32) {
        require(msg.sender == FlashMintLib.LENDER);
        require(initiator == address(this));
        (bool deficit, uint256 amountWant) = abi.decode(data, (bool, uint256));

        return
            FlashMintLib.loanLogic(deficit, amountWant, amount, address(want));
    }

    function getCurrentPosition()
        public
        view
        returns (uint256 deposits, uint256 borrows)
    {
        deposits = balanceOfAToken();
        borrows = balanceOfDebtToken();
    }

    function getCurrentCollatRatio()
        public
        view
        returns (uint256 currentCollatRatio)
    {
        (uint256 deposits, uint256 borrows) = getCurrentPosition();

        if (deposits > 0) {
            currentCollatRatio =
                (borrows * COLLATERAL_RATIO_PRECISION) /
                deposits;
        }
    }

    function getCurrentSupply() public view returns (uint256) {
        (uint256 deposits, uint256 borrows) = getCurrentPosition();
        return deposits - borrows;
    }

    // conversions
    function tokenToWant(address token, uint256 amount)
        internal
        view
        returns (uint256)
    {
        if (amount == 0 || address(want) == token) {
            return amount;
        }

        // KISS: just use a v2 router for quotes which aren't used in critical logic
        IUni router = swapRouter == SwapRouter.SushiV2
            ? SUSHI_V2_ROUTER
            : UNI_V2_ROUTER;
        uint256[] memory amounts = router.getAmountsOut(
            amount,
            getTokenOutPathV2(token, address(want))
        );

        return amounts[amounts.length - 1];
    }

    function ethToWant(uint256 _amtInWei)
        public
        view
        override
        returns (uint256)
    {
        return tokenToWant(weth, _amtInWei);
    }

    function _checkCooldown() internal view returns (CooldownStatus) {
        uint256 cooldownStartTimestamp = IStakedAave(stkAave).stakersCooldowns(
            address(this)
        );
        uint256 COOLDOWN_SECONDS = IStakedAave(stkAave).COOLDOWN_SECONDS();
        uint256 UNSTAKE_WINDOW = IStakedAave(stkAave).UNSTAKE_WINDOW();
        uint256 nextClaimStartTimestamp = cooldownStartTimestamp +
            COOLDOWN_SECONDS;

        if (cooldownStartTimestamp == 0) {
            return CooldownStatus.None;
        }
        if (
            block.timestamp > nextClaimStartTimestamp &&
            block.timestamp <= nextClaimStartTimestamp + UNSTAKE_WINDOW
        ) {
            return CooldownStatus.Claim;
        }
        if (block.timestamp < nextClaimStartTimestamp) {
            return CooldownStatus.Initiated;
        }
    }

    function getTokenOutPathV2(address _token_in, address _token_out)
        internal
        pure
        returns (address[] memory _path)
    {
        bool is_weth = _token_in == address(weth) ||
            _token_out == address(weth);
        _path = new address[](is_weth ? 2 : 3);
        _path[0] = _token_in;

        if (is_weth) {
            _path[1] = _token_out;
        } else {
            _path[1] = address(weth);
            _path[2] = _token_out;
        }
    }

    function getTokenOutPathV3(address _token_in, address _token_out)
        internal
        view
        returns (bytes memory _path)
    {
        if (address(want) == weth) {
            _path = abi.encodePacked(
                address(aave),
                aaveToWethSwapFee,
                address(weth)
            );
        } else {
            _path = abi.encodePacked(
                address(aave),
                aaveToWethSwapFee,
                address(weth),
                wethToWantSwapFee,
                address(want)
            );
        }
    }

    function _sellAAVEForWant(uint256 amountIn, uint256 minOut) internal {
        if (amountIn == 0) {
            return;
        }
        if (swapRouter == SwapRouter.UniV3) {
            UNI_V3_ROUTER.exactInput(
                ISwapRouter.ExactInputParams(
                    getTokenOutPathV3(address(aave), address(want)),
                    address(this),
                    block.timestamp,
                    amountIn,
                    minOut
                )
            );
        } else {
            IUni router = swapRouter == SwapRouter.UniV2
                ? UNI_V2_ROUTER
                : SUSHI_V2_ROUTER;
            router.swapExactTokensForTokens(
                amountIn,
                minOut,
                getTokenOutPathV2(address(aave), address(want)),
                address(this),
                block.timestamp
            );
        }
    }

    function _sellSTKAAVEToAAVE(uint256 amountIn, uint256 minOut) internal {
        // Swap Rewards in UNIV3
        // NOTE: Unoptimized, can be frontrun and most importantly this pool is low liquidity
        UNI_V3_ROUTER.exactInputSingle(
            ISwapRouter.ExactInputSingleParams(
                address(stkAave),
                address(aave),
                stkAaveToAaveSwapFee,
                address(this),
                block.timestamp,
                amountIn, // wei
                minOut,
                0
            )
        );
    }

    function getAaveAssets() internal view returns (address[] memory assets) {
        assets = new address[](2);
        assets[0] = address(aToken);
        assets[1] = address(debtToken);
    }

    function getProtocolCollatRatios(address token)
        internal
        view
        returns (uint256 ltv, uint256 liquidationThreshold)
    {
        (, ltv, liquidationThreshold, , , , , , , ) = protocolDataProvider
            .getReserveConfigurationData(token);
        // convert bps to wad
        ltv = ltv * BPS_WAD_RATIO;
        liquidationThreshold = liquidationThreshold * BPS_WAD_RATIO;
    }

    function getBorrowFromDeposit(uint256 deposit, uint256 collatRatio)
        internal
        pure
        returns (uint256)
    {
        return (deposit * collatRatio) / COLLATERAL_RATIO_PRECISION;
    }

    function getDepositFromBorrow(uint256 borrow, uint256 collatRatio)
        internal
        pure
        returns (uint256)
    {
        return (borrow * COLLATERAL_RATIO_PRECISION) / collatRatio;
    }

    function getBorrowFromSupply(uint256 supply, uint256 collatRatio)
        internal
        pure
        returns (uint256)
    {
        return
            (supply * collatRatio) / (COLLATERAL_RATIO_PRECISION - collatRatio);
    }

    function approveMaxSpend(address token, address spender) internal {
        IERC20(token).safeApprove(spender, type(uint256).max);
    }
}
