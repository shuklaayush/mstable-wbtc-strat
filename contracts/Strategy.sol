// SPDX-License-Identifier: AGPL-3.0
// Feel free to change the license, but this is what we use

/*
Strategy flow:

Deposit:
WBTC --> Mint mBTC
mBTC --> 'Saved' to get imBTC
imBTC --> Add to vault to get v-imBTC

Withdraw:
v-imBTC --> imBTC (1: 1) => No sandwich
imBTC --> mBTC (creditsToUnderlying(amount) / balanceOfUnderlying(address)) => Doesn't look sandwichable since exchange rate changes are mostly permissioned
mBTC --> WBTC (getRedeemOutput(want, amount)) => 1: 1
*/

// Feel free to change this version of Solidity. We support >=0.6.0 <0.7.0;
pragma solidity 0.6.12;
pragma experimental ABIEncoderV2;

// These are the core Yearn libraries
import {
    BaseStrategy,
    StrategyParams
} from "@yearnvaults/contracts/BaseStrategy.sol";
import {Math} from "@openzeppelin/contracts/math/Math.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {
    SafeERC20,
    SafeMath,
    IERC20,
    Address
} from "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";

// Import interfaces for many popular DeFi projects, or add your own!
import {
    FeedRegistryInterface
} from "../interfaces/chainlink/FeedRegistryInterface.sol";
import {
    IBoostedVaultWithLockup
} from "../interfaces/mstable/IBoostedVaultWithLockup.sol";
import {IMasset} from "../interfaces/mstable/IMasset.sol";
import {ISaveWrapper} from "../interfaces/mstable/ISaveWrapper.sol";
import {ISavingsContractV2} from "../interfaces/mstable/ISavingsContract.sol";
import {
    IUniswapV2Router02 as IUniswapV2Router
} from "../interfaces/uniswap/IUniswapV2Router02.sol";

contract Strategy is BaseStrategy {
    using SafeERC20 for IERC20;
    using Address for address;
    using SafeMath for uint256;

    // mStable
    ISaveWrapper public constant saveWrapper =
        ISaveWrapper(0x0CA7A25181FC991e3cC62BaC511E62973991f325);
    // Tokens
    IMasset public constant mbtc =
        IMasset(0x945Facb997494CC2570096c74b5F66A3507330a1);
    ISavingsContractV2 public constant imbtc =
        ISavingsContractV2(0x17d8CBB6Bce8cEE970a4027d1198F6700A7a6c24);
    IBoostedVaultWithLockup public constant vimbtc =
        IBoostedVaultWithLockup(0xF38522f63f40f9Dd81aBAfD2B8EFc2EC958a3016);
    // Reward token - MTA
    IERC20 public constant reward =
        IERC20(0xa3BeD4E1c75D00fa6f4E5E6922DB7261B5E9AcD2); // Token we farm and swap to want

    // Chainlink
    FeedRegistryInterface chainlinkRegistry =
        FeedRegistryInterface(0x47Fb2585D2C56Fe188D0E6ec628a38b74fCeeeDf);
    address public constant ETH = 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE;
    address public constant BTC = 0xbBbBBBBbbBBBbbbBbbBbbbbBBbBbbbbBbBbbBBbB;
    IERC20 public constant WETH_TOKEN =
        IERC20(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2);
    // IERC20 public constant DAI_TOKEN = IERC20(0x6b175474e89094c44da98b954eedeac495271d0f); // Uni v3 pool

    // Uniswap routers
    IUniswapV2Router public constant uniswapV2Router =
        IUniswapV2Router(0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D);
    // ISwapRouter public constant uniswapV3Router =
    //     IUniswapV2Router02(0xE592427A0AEce92De3Edee1F18E0157C05861564);

    uint256 public constant MAX_BPS = 10000;
    uint256 public immutable wantDecimals;

    // Should we ensure the swap will be within slippage params before performing it during normal harvest?
    bool public checkRewardToWantSlippage = true;
    uint256 public slippageRewardToWant = 2000; // 20%

    // uint256 public slippageWantToMbtc = 2000; // 20%

    constructor(address _vault) public BaseStrategy(_vault) {
        // You can set these parameters on deployment to whatever you want
        // TODO: Currently arbitrary
        maxReportDelay = 6300;
        profitFactor = 100;
        debtThreshold = 0;

        wantDecimals = ERC20(address(want)).decimals();

        want.safeApprove(address(saveWrapper), type(uint256).max);
        reward.safeApprove(address(uniswapV2Router), type(uint256).max);
    }

    function setCheckRewardToWantSlippage(bool _checkRewardToWantSlippage)
        external
        onlyVaultManagers
    {
        checkRewardToWantSlippage = _checkRewardToWantSlippage;
    }

    function setSlippageRewardToWant(uint256 _slippageRewardToWant)
        external
        onlyVaultManagers
    {
        require(_slippageRewardToWant <= MAX_BPS);
        slippageRewardToWant = _slippageRewardToWant;
    }

    // ******** OVERRIDE THESE METHODS FROM BASE CONTRACT ************

    function name() external view override returns (string memory) {
        // Add your own name here, suggestion e.g. "StrategyCreamYFI"
        return "Strategy-mStable-WBTC";
    }

    function imbtcToMbtc(uint256 _tokens) public view returns (uint256) {
        if (_tokens == 0) {
            return 0;
        }
        return imbtc.creditsToUnderlying(_tokens); // TODO: Check if sandwichable?
    }

    function mbtcToImbtc(uint256 _tokens) public view returns (uint256) {
        if (_tokens == 0) {
            return 0;
        }
        return imbtc.underlyingToCredits(_tokens); // TODO: Check if sandwichable?
    }

    function mbtcToWant(uint256 _tokens) public view returns (uint256) {
        if (_tokens == 0) {
            return 0;
        }
        // return mbtc.getRedeemOutput(address(want), _tokens); // TODO: Check if sandwichable? Maybe use 1: 1 ratio?
        return _tokens.mul(10**wantDecimals).div(1e18); // 1:1 peg
    }

    function wantToMbtc(uint256 _tokens) public view returns (uint256) {
        if (_tokens == 0) {
            return 0;
        }
        // return mbtc.getMintOutput(address(want), _tokens); // TODO: Check if sandwichable? Maybe use 1: 1 ratio?
        return _tokens.mul(1e18).div(10**wantDecimals); // 1:1 peg
    }

    function imbtcToWant(uint256 _tokens) public view returns (uint256) {
        if (_tokens == 0) {
            return 0;
        }
        return mbtcToWant(imbtcToMbtc(_tokens));
    }

    function wantToImbtc(uint256 _tokens) public view returns (uint256) {
        if (_tokens == 0) {
            return 0;
        }
        return wantToMbtc(mbtcToImbtc(_tokens));
    }

    function estimatedTotalAssets() public view override returns (uint256) {
        // TODO: Maybe also check mbtc balance
        uint256 vimbtcBalance = vimbtc.balanceOf(address(this));
        uint256 imbtcBalance = imbtc.balanceOf(address(this));

        return
            want.balanceOf(address(this)).add(
                imbtcToWant(imbtcBalance.add(vimbtcBalance))
            ); // vimBTC-imBTC is 1:1
    }

    // Calculate minimum output amount expected based on given slippage
    function _calcMinAmountFromSlippage(uint256 _amount, uint256 _slippage)
        internal
        view
        returns (uint256)
    {
        return _amount.mul(MAX_BPS.sub(_slippage)).div(MAX_BPS);
    }

    function _claimRewards() internal {
        vimbtc.claimRewards(0, 0);
    }

    function _swapRewardToWant(uint256 amountIn, uint256 minOut) internal {
        // TODO: Maybe add option to use v3 MTA-DAI pool
        // Swap reward MTA => WETH => WBTC on Uniswap v2
        address[] memory path = new address[](3);
        path[0] = address(reward);
        path[1] = address(WETH_TOKEN);
        path[2] = address(want);

        // Swap reward => WETH => want
        uniswapV2Router.swapExactTokensForTokens(
            amountIn,
            minOut,
            path,
            address(this),
            now
        );
    }

    function _claimRewardsAndSwapToWant() internal {
        _claimRewards();

        uint256 rewardsAmount = reward.balanceOf(address(this));
        if (rewardsAmount == 0) {
            return;
        }

        uint256 minWantOut;
        if (checkRewardToWantSlippage) {
            minWantOut = _calcMinAmountFromSlippage(
                rewardToWant(rewardsAmount),
                slippageRewardToWant
            );
        }
        _swapRewardToWant(rewardsAmount, minWantOut);
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
        // TODO: Do stuff here to free up any returns back into `want`
        // NOTE: Return `_profit` which is value generated by all positions, priced in `want`
        // NOTE: Should try to free up at least `_debtOutstanding` of underlying position
        // Reference: SingleSidedCrvWBTC.sol

        _debtPayment = _debtOutstanding;

        // Claim MTA rewards
        _claimRewardsAndSwapToWant();

        uint256 debt = vault.strategies(address(this)).totalDebt;
        uint256 currentValue = estimatedTotalAssets();
        uint256 wantBalance = want.balanceOf(address(this));

        if (debt < currentValue) {
            _profit = currentValue.sub(debt);
        } else {
            _loss = debt.sub(currentValue);
        }

        uint256 toFree = _debtPayment.add(_profit);

        if (toFree > wantBalance) {
            toFree = toFree.sub(wantBalance);

            (, uint256 withdrawalLoss) = withdrawSome(toFree);

            //when we withdraw we can lose money in the withdrawal
            if (withdrawalLoss < _profit) {
                _profit = _profit.sub(withdrawalLoss);
            } else {
                _loss = _loss.add(withdrawalLoss.sub(_profit));
                _profit = 0;
            }

            wantBalance = want.balanceOf(address(this));

            if (wantBalance < _profit) {
                _profit = wantBalance;
                _debtPayment = 0;
            } else if (wantBalance < _debtPayment.add(_profit)) {
                _debtPayment = wantBalance.sub(_profit);
            }
        }
    }

    function _stakeImbtc(uint256 _amount) internal {
        if (_amount > 0) {
            vimbtc.stake(_amount);
        }
    }

    function _unstakeVimbtc(uint256 _amount) internal {
        if (_amount > 0) {
            vimbtc.withdraw(_amount);
        }
    }

    function adjustPosition(uint256 _debtOutstanding) internal override {
        // TODO: Do something to invest excess `want` tokens (from the Vault) into your positions
        // NOTE: Try to adjust positions so that `_debtOutstanding` can be freed up on *next* harvest (not immediately)
        uint256 wantToInvest = want.balanceOf(address(this));
        if (wantToInvest > 0) {
            saveWrapper.saveViaMint(
                address(mbtc),
                address(imbtc),
                address(vimbtc),
                address(want), // WBTC
                wantToInvest,
                0, // _minOut for WBTC-mBTC conversion (TODO: See if there's a way to add slippage protection here)
                true
            );
        }
        // TODO: Should I also stake excess imBTC tokens?
        uint256 imbtcBalance = imbtc.balanceOf(address(this));
        if (imbtcBalance > 0) {
            _stakeImbtc(imbtcBalance);
        }
    }

    function _unstakeVimbtcAndRedeemImbtc(uint256 _amount)
        internal
        returns (uint256)
    {
        if (_amount == 0) {
            return 0;
        }
        _unstakeVimbtc(_amount);
        return imbtc.redeemCredits(_amount);
    }

    function _redeemMbtcForWant(uint256 _amount) internal returns (uint256) {
        if (_amount == 0) {
            return 0;
        }
        // TODO: Redeem may fail because of basket weight limits on mStable
        // (https://docs.mstable.org/mstable-assets/mstable-app/forge/minting-and-redemption#the-basic-process-of-redeeming-a-masset)
        return
            mbtc.redeem(
                address(want),
                _amount,
                0, // No slippage protection
                address(this)
            );
    }

    // Divest from imbtc vault
    function _divest(uint256 _amount) internal returns (uint256) {
        if (_amount == 0) {
            return 0;
        }
        uint256 mbtcAmount = _unstakeVimbtcAndRedeemImbtc(_amount);
        return _redeemMbtcForWant(mbtcAmount);
    }

    // safe to enter more than we have
    function withdrawSome(uint256 _amount)
        internal
        returns (uint256 _liquidatedAmount, uint256 _loss)
    {
        // Reference: SingleSidedCrvWBTC.sol
        uint256 wantBalanceBefore = want.balanceOf(address(this));

        uint256 vimbtcNeeded = wantToImbtc(_amount);
        uint256 vimbtcBalance = vimbtc.balanceOf(address(this));
        if (vimbtcBalance < vimbtcNeeded) {
            vimbtcNeeded = vimbtcBalance;
            //this is not loss. so we amend amount
            _amount = imbtcToWant(vimbtcNeeded);
        }

        _divest(vimbtcNeeded);

        uint256 diff = want.balanceOf(address(this)).sub(wantBalanceBefore);

        if (diff > _amount) {
            _liquidatedAmount = _amount;
        } else {
            _liquidatedAmount = diff;
            _loss = _amount.sub(diff);
        }
    }

    function liquidatePosition(uint256 _amountNeeded)
        internal
        override
        returns (uint256 _liquidatedAmount, uint256 _loss)
    {
        // TODO: Do stuff here to free up to `_amountNeeded` from all positions back into `want`
        // NOTE: Maintain invariant `want.balanceOf(this) >= _liquidatedAmount`
        // NOTE: Maintain invariant `_liquidatedAmount + _loss <= _amountNeeded`
        // Reference: SingleSidedCrvWBTC.sol

        uint256 wantBalance = want.balanceOf(address(this));
        if (wantBalance < _amountNeeded) {
            (_liquidatedAmount, _loss) = withdrawSome(
                _amountNeeded.sub(wantBalance)
            );
        }
        _liquidatedAmount = Math.min(
            _amountNeeded,
            _liquidatedAmount.add(wantBalance)
        );
    }

    function liquidateAllPositions() internal override returns (uint256) {
        // TODO: Liquidate all positions and return the amount freed.
        // Liquidate fully into WBTC
        // TODO: Redeem may fail because of basket weight limits on mStable
        // (https://docs.mstable.org/mstable-assets/mstable-app/forge/minting-and-redemption#the-basic-process-of-redeeming-a-masset)
        _divest(vimbtc.balanceOf(address(this)));
        // Get rewards before leaving
        _claimRewardsAndSwapToWant();

        return want.balanceOf(address(this));
    }

    // NOTE: Can override `tendTrigger` and `harvestTrigger` if necessary

    function prepareMigration(address _newStrategy) internal override {
        // TODO: Transfer any non-`want` tokens to the new strategy
        // NOTE: `migrate` will automatically forward all `want` in this strategy to the new one
        uint256 vimbtcBalance = vimbtc.balanceOf(address(this));
        if (vimbtcBalance > 0) {
            _unstakeVimbtc(vimbtcBalance);
        }
        uint256 imbtcBalance = imbtc.balanceOf(address(this));
        if (imbtcBalance > 0) {
            imbtc.transfer(_newStrategy, imbtcBalance);
        }
    }

    // Override this to add all tokens/tokenized positions this contract manages
    // on a *persistent* basis (e.g. not just for swapping back to want ephemerally)
    // NOTE: Do *not* include `want`, already included in `sweep` below
    //
    // Example:
    //
    //    function protectedTokens() internal override view returns (address[] memory) {
    //      address[] memory protected = new address[](3);
    //      protected[0] = tokenA;
    //      protected[1] = tokenB;
    //      protected[2] = tokenC;
    //      return protected;
    //    }
    function protectedTokens()
        internal
        view
        override
        returns (address[] memory)
    {
        address[] memory protected = new address[](2);
        protected[0] = address(vimbtc);
        protected[1] = address(reward); // MTA
        // protected[2] = address(imbtc);
        // protected[3] = address(mbtc);
        return protected;
    }

    /**
     * @notice
     *  Provide an accurate conversion from `_amtInWei` (denominated in wei)
     *  to `want` (using the native decimal characteristics of `want`).
     * @dev
     *  Care must be taken when working with decimals to assure that the conversion
     *  is compatible. As an example:
     *
     *      given 1e17 wei (0.1 ETH) as input, and want is USDC (6 decimals),
     *      with USDC/ETH = 1800, this should give back 180000000 (180 USDC)
     *
     * @param _amtInWei The amount (in wei/1e-18 ETH) to convert to `want`
     * @return The amount in `want` of `_amtInEth` converted to `want`
     **/
    function ethToWant(uint256 _amtInWei)
        public
        view
        virtual
        override
        returns (uint256)
    {
        int256 ethPerWant = chainlinkRegistry.latestAnswer(BTC, ETH);
        return _amtInWei.mul(10**wantDecimals).div(uint256(ethPerWant));
    }

    // Convert _amount of token into want using Chainlink price feed
    function rewardToEth(uint256 _amount) public view returns (uint256) {
        int256 ethPerReward =
            chainlinkRegistry.latestAnswer(address(reward), ETH);
        return _amount.mul(uint256(ethPerReward)).div(10**18);
    }

    function rewardToWant(uint256 _amount) public view returns (uint256) {
        return ethToWant(rewardToEth(_amount));
    }
}
