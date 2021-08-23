// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity 0.6.12;

// Internal
import {IBoostDirector} from "./IBoostDirector.sol";

// Libs
import {IERC20} from "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";

/**
 * @title  BoostedTokenWrapper
 * @author mStable
 * @notice Wrapper to facilitate tracking of staked balances, applying a boost
 * @dev    Forked from rewards/staking/StakingTokenWrapper.sol
 *         Changes:
 *          - Adding `_boostedBalances` and `_totalBoostedSupply`
 *          - Implemting of a `_setBoost` hook to calculate/apply a users boost
 */
interface IBoostedTokenWrapper {
    function stakingToken() external view returns (IERC20);

    function boostDirector() external view returns (IBoostDirector);

    function boostCoeff() external view returns (int256);

    function priceCoeff() external view returns (uint256);

    function name() external view returns (string memory);

    function symbol() external view returns (string memory);

    function decimals() external view returns (uint8);

    /**
     * @dev Get the total boosted amount
     * @return uint256 total supply
     */
    function totalSupply() external view returns (uint256);

    /**
     * @dev Get the boosted balance of a given account
     * @param _account User for which to retrieve balance
     */
    function balanceOf(address _account) external view returns (uint256);

    /**
     * @dev Get the RAW balance of a given account
     * @param _account User for which to retrieve balance
     */
    function rawBalanceOf(address _account) external view returns (uint256);

    /**
     * @dev Read the boost for the given address
     * @param _account User for which to return the boost
     * @return boost where 1x == 1e18
     */
    function getBoost(address _account) external view returns (uint256);
}
