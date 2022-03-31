pragma solidity 0.8.12;
pragma experimental ABIEncoderV2;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "./interfaces/aave/IProtocolDataProvider.sol";
import "./interfaces/aave/IAaveIncentivesController.sol";
import "./interfaces/aave/IStakedAave.sol";
import "./interfaces/aave/IAToken.sol";
import "./interfaces/aave/IVariableDebtToken.sol";
import "./interfaces/aave/IPriceOracle.sol";
import "./interfaces/aave/ILendingPool.sol";
import "./interfaces/dai/IERC3156FlashLender.sol";
import "./interfaces/dai/IERC3156FlashBorrower.sol";

interface IOptionalERC20 {
    function decimals() external view returns (uint8);
}

library FlashMintLib {
    event Leverage(
        uint256 amountRequested,
        uint256 amountUsed,
        uint256 requiredDAI,
        uint256 amountToCloseLTVGap,
        bool deficit,
        address flashLoan
    );

    address public constant LENDER = 0x1EB4CF3A948E7D72A198fe073cCb8C7a948cD853;
    uint256 private constant DAI_DECIMALS = 1e18;
    uint256 private constant COLLAT_RATIO_PRECISION = 1 ether;
    address private constant WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    address private constant DAI = 0x6B175474E89094C44Da98b954EedeAC495271d0F;
    IAToken public constant ADAI =
        IAToken(0x028171bCA77440897B824Ca71D1c56caC55b68A3);
    IProtocolDataProvider private constant protocolDataProvider =
        IProtocolDataProvider(0x057835Ad21a177dbdd3090bB1CAE03EaCF78Fc6d);
    ILendingPool private constant lendingPool =
        ILendingPool(0x7d2768dE32b0b80b7a3454c06BdAc94A69DDc7A9);

    bytes32 public constant CALLBACK_SUCCESS =
        keccak256("ERC3156FlashBorrower.onFlashLoan");

    uint16 private constant referral = 7; // Yearn's aave referral code

    function doFlashMint(
        bool deficit,
        uint256 amountDesired,
        address token,
        uint256 collatRatioDAI,
        uint256 depositToCloseLTVGap
    ) public returns (uint256 amount) {
        if (amountDesired == 0) {
            return 0;
        }
        amount = amountDesired;
        address dai = DAI;

        // calculate amount of dai we need
        uint256 requiredDAI;
        {
            requiredDAI =
                (_toDAI(amount, token) * COLLAT_RATIO_PRECISION) /
                collatRatioDAI;

            uint256 requiredDAIToCloseLTVGap = 0;
            if (depositToCloseLTVGap > 0) {
                requiredDAIToCloseLTVGap = _toDAI(depositToCloseLTVGap, token);
                requiredDAI = requiredDAI + requiredDAIToCloseLTVGap;
            }

            uint256 _maxLiquidity = maxLiquidity();
            if (requiredDAI > _maxLiquidity) {
                requiredDAI = _maxLiquidity;
                // NOTE: if we cap amountDAI, we reduce amountToken we are taking too
                amount =
                    (_fromDAI(requiredDAI - requiredDAIToCloseLTVGap, token) *
                        collatRatioDAI) /
                    COLLAT_RATIO_PRECISION;
            }
        }

        bytes memory data = abi.encode(deficit, amount);
        uint256 _fee = IERC3156FlashLender(LENDER).flashFee(dai, requiredDAI);
        // Check that fees have not been increased without us knowing
        require(_fee == 0);
        uint256 _allowance = IERC20(dai).allowance(
            address(this),
            address(LENDER)
        );
        if (_allowance < requiredDAI) {
            IERC20(dai).approve(address(LENDER), 0);
            IERC20(dai).approve(address(LENDER), type(uint256).max);
        }
        IERC3156FlashLender(LENDER).flashLoan(
            IERC3156FlashBorrower(address(this)),
            dai,
            requiredDAI,
            data
        );

        emit Leverage(
            amountDesired,
            amount,
            requiredDAI,
            depositToCloseLTVGap,
            deficit,
            LENDER
        );

        return amount; // we need to return the amount of Token we have changed our position in
    }

    function loanLogic(
        bool deficit,
        uint256 amount,
        uint256 amountFlashmint,
        address want
    ) public returns (bytes32) {
        address dai = DAI;
        bool isDai = (want == dai);

        ILendingPool lp = lendingPool;

        if (isDai) {
            if (deficit) {
                lp.deposit(
                    dai,
                    amountFlashmint - amount,
                    address(this),
                    referral
                );
                lp.repay(
                    dai,
                    IERC20(dai).balanceOf(address(this)),
                    2,
                    address(this)
                );
                lp.withdraw(dai, amountFlashmint, address(this));
            } else {
                lp.deposit(
                    dai,
                    IERC20(dai).balanceOf(address(this)),
                    address(this),
                    referral
                );
                lp.borrow(dai, amount, 2, referral, address(this));
                lp.withdraw(dai, amountFlashmint - amount, address(this));
            }
        } else {
            // 1. Deposit DAI in Aave as collateral
            lp.deposit(dai, amountFlashmint, address(this), referral);

            if (deficit) {
                // 2a. if in deficit withdraw amount and repay it
                lp.withdraw(want, amount, address(this));
                lp.repay(
                    want,
                    IERC20(want).balanceOf(address(this)),
                    2,
                    address(this)
                );
            } else {
                // 2b. if levering up borrow and deposit
                lp.borrow(want, amount, 2, referral, address(this));
                lp.deposit(
                    want,
                    IERC20(want).balanceOf(address(this)),
                    address(this),
                    referral
                );
            }
            // 3. Withdraw DAI
            lp.withdraw(dai, amountFlashmint, address(this));
        }

        return CALLBACK_SUCCESS;
    }

    function _priceOracle() internal view returns (IPriceOracle) {
        return
            IPriceOracle(
                protocolDataProvider.ADDRESSES_PROVIDER().getPriceOracle()
            );
    }

    function _toDAI(uint256 _amount, address asset)
        internal
        view
        returns (uint256)
    {
        address dai = DAI;
        if (
            _amount == 0 || _amount == type(uint256).max || asset == dai // 1:1 change
        ) {
            return _amount;
        }

        if (asset == WETH) {
            return
                (_amount *
                    uint256(10)**uint256(IOptionalERC20(dai).decimals())) /
                _priceOracle().getAssetPrice(dai);
        }

        address[] memory tokens = new address[](2);
        tokens[0] = asset;
        tokens[1] = dai;
        uint256[] memory prices = _priceOracle().getAssetsPrices(tokens);

        uint256 ethPrice = (_amount * prices[0]) /
            uint256(10)**uint256(IOptionalERC20(asset).decimals());
        return (ethPrice * DAI_DECIMALS) / prices[1];
    }

    function _fromDAI(uint256 _amount, address asset)
        internal
        view
        returns (uint256)
    {
        address dai = DAI;
        if (
            _amount == 0 || _amount == type(uint256).max || asset == dai // 1:1 change
        ) {
            return _amount;
        }

        if (asset == WETH) {
            return
                (_amount * _priceOracle().getAssetPrice(dai)) /
                uint256(10)**uint256(IOptionalERC20(dai).decimals());
        }

        address[] memory tokens = new address[](2);
        tokens[0] = asset;
        tokens[1] = dai;
        uint256[] memory prices = _priceOracle().getAssetsPrices(tokens);

        uint256 ethPrice = (_amount * prices[1]) / DAI_DECIMALS;

        return
            (ethPrice *
                uint256(10)**uint256(IOptionalERC20(asset).decimals())) /
            prices[0];
    }

    function maxLiquidity() public view returns (uint256) {
        return IERC3156FlashLender(LENDER).maxFlashLoan(DAI);
    }
}
