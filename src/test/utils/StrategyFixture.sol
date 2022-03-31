// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.12;
pragma abicoder v2;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ExtendedDSTest} from "./ExtendedDSTest.sol";
import {stdCheats} from "forge-std/stdlib.sol";
import {Vm} from "forge-std/Vm.sol";
import {IVault} from "../../interfaces/Vault.sol";
import {Actions} from "./Actions.sol";
import {Checks} from "./Checks.sol";
import {Utils} from "./Utils.sol";

// NOTE: if the name of the strat or file changes this needs to be updated
import {Strategy} from "../../Strategy.sol";
import {LevAaveFactory} from "../../LevAaveFactory.sol";

// Artifact paths for deploying from the deps folder, assumes that the command is run from
// the project root.
string constant vaultArtifact = "artifacts/Vault.json";

// @dev Base fixture deploying Vault
contract StrategyFixture is ExtendedDSTest, stdCheats {
    using SafeERC20 for IERC20;

    IVault public vault;
    Strategy public strategy;
    LevAaveFactory public levAaveFactory;
    IERC20 public weth;
    IERC20 public want;

    // we use custom names that are unlikely to cause collisions so this contract
    // can be inherited easily
    Vm public constant vm_std_cheats =
        Vm(address(uint160(uint256(keccak256("hevm cheat code")))));

    address public gov = 0xFEB4acf3df3cDEA7399794D0869ef76A6EfAff52;
    address public user = address(1);
    address public whale = address(2);
    address public rewards = address(3);
    address public guardian = address(4);
    address public management = address(5);
    address public strategist = address(6);
    address public keeper = address(7);

    uint256 public minFuzzAmt;
    // @dev maximum amount of want tokens deposited based on @maxDollarNotional
    uint256 public maxFuzzAmt;
    // @dev maximum dollar amount of tokens to be deposited
    uint256 public constant maxDollarNotional = 1_000_000;
    uint256 public constant bigDollarNotional = 49_000_000;
    uint256 public constant DELTA = 10**5;
    uint256 public bigAmount;

    mapping(string => address) tokenAddrs;
    mapping(string => uint256) tokenPrices;

    // utils
    Actions actions;
    Checks checks;
    Utils utils;

    function setUp() public virtual {
        actions = new Actions();
        checks = new Checks();
        utils = new Utils();

        _setTokenPrices();
        _setTokenAddrs();
        string memory token = "DAI";
        weth = IERC20(tokenAddrs["WETH"]);
        want = IERC20(tokenAddrs[token]);

        deployVaultAndStrategy(
            address(want),
            gov,
            rewards,
            "",
            "",
            guardian,
            management,
            keeper,
            strategist
        );

        minFuzzAmt = 10**vault.decimals() / 10;
        maxFuzzAmt =
            uint256(maxDollarNotional / tokenPrices[token]) *
            10**vault.decimals();
        bigAmount =
            uint256(bigDollarNotional / tokenPrices[token]) *
            10**vault.decimals();

        vm_std_cheats.label(address(vault), "Vault");
        vm_std_cheats.label(address(strategy), "Strategy");
        vm_std_cheats.label(address(want), "Want");
        vm_std_cheats.label(gov, "Gov");
        vm_std_cheats.label(user, "User");
        vm_std_cheats.label(whale, "Whale");
        vm_std_cheats.label(rewards, "Rewards");
        vm_std_cheats.label(guardian, "Guardian");
        vm_std_cheats.label(management, "Management");
        vm_std_cheats.label(strategist, "Strategist");
        vm_std_cheats.label(keeper, "Keeper");

        // Strategy specific labels for tracing
        vm_std_cheats.label(
            0x4da27a545c0c5B758a6BA100e3a049001de870f5,
            "stkAave"
        );
        vm_std_cheats.label(0x7Fc66500c84A76Ad7e9c93437bFc5Ac33E2DDaE9, "aave");
        vm_std_cheats.label(
            0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D,
            "univ2"
        );
        vm_std_cheats.label(
            0xd9e1cE17f2641f24aE83637ab66a2cca9C378B9F,
            "sushiv2"
        );
        vm_std_cheats.label(
            0xE592427A0AEce92De3Edee1F18E0157C05861564,
            "univ3"
        );
        vm_std_cheats.label(
            0x7d2768dE32b0b80b7a3454c06BdAc94A69DDc7A9,
            "Lending Pool"
        );

        // do here additional setup
        vm_std_cheats.startPrank(gov);
        vault.setManagementFee(0);
        vault.setDepositLimit(type(uint256).max);
        vm_std_cheats.stopPrank();
    }

    // @dev Deploys a vault
    function deployVault(
        address _token,
        address _gov,
        address _rewards,
        string memory _name,
        string memory _symbol,
        address _guardian,
        address _management
    ) public returns (address) {
        vm_std_cheats.prank(gov);
        address _vault = deployCode(vaultArtifact);
        vault = IVault(_vault);

        vm_std_cheats.prank(gov);
        vault.initialize(
            _token,
            _gov,
            _rewards,
            _name,
            _symbol,
            _guardian,
            _management
        );

        return address(vault);
    }

    // @dev Deploys a strategy
    function deployStrategy() public returns (address) {
        address _strategy = levAaveFactory.original();

        return address(_strategy);
    }

    // @dev Deploys levAaveFactory
    function deployLevAaveFactory(address _vault)
        public
        returns (address _levAaveFactory)
    {
        LevAaveFactory _levAaveFactory = new LevAaveFactory(_vault);

        return address(_levAaveFactory);
    }

    // @dev Deploys a vault and strategy attached to vault
    function deployVaultAndStrategy(
        address _token,
        address _gov,
        address _rewards,
        string memory _name,
        string memory _symbol,
        address _guardian,
        address _management,
        address _keeper,
        address _strategist
    ) public returns (address _vault, address _strategy) {
        vm_std_cheats.prank(gov);
        _vault = deployCode(vaultArtifact);
        vault = IVault(_vault);

        vm_std_cheats.prank(gov);
        vault.initialize(
            _token,
            _gov,
            _rewards,
            _name,
            _symbol,
            _guardian,
            _management
        );

        vm_std_cheats.prank(_strategist);
        levAaveFactory = LevAaveFactory(deployLevAaveFactory(address(vault)));

        vm_std_cheats.prank(_strategist);
        _strategy = deployStrategy();
        strategy = Strategy(_strategy);

        vm_std_cheats.prank(_strategist);
        strategy.setKeeper(_keeper);

        vm_std_cheats.prank(gov);
        vault.addStrategy(_strategy, 10_000, 0, type(uint256).max, 1_000);
    }

    function _setTokenAddrs() internal {
        tokenAddrs["WBTC"] = 0x2260FAC5E5542a773Aa44fBCfeDf7C193bc2C599;
        tokenAddrs["YFI"] = 0x0bc529c00C6401aEF6D220BE8C6Ea1667F6Ad93e;
        tokenAddrs["WETH"] = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
        tokenAddrs["LINK"] = 0x514910771AF9Ca656af840dff83E8264EcF986CA;
        tokenAddrs["USDT"] = 0xdAC17F958D2ee523a2206206994597C13D831ec7;
        tokenAddrs["DAI"] = 0x6B175474E89094C44Da98b954EedeAC495271d0F;
        tokenAddrs["USDC"] = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
    }

    function _setTokenPrices() internal {
        tokenPrices["WBTC"] = 60_000;
        tokenPrices["WETH"] = 4_000;
        tokenPrices["LINK"] = 20;
        tokenPrices["YFI"] = 35_000;
        tokenPrices["USDT"] = 1;
        tokenPrices["USDC"] = 1;
        tokenPrices["DAI"] = 1;
    }
}
