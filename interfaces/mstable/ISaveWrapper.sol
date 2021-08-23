// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity 0.6.12;

// pragma experimental ABIEncoderV2;

// FLOWS
// 0 - mAsset -> Savings Vault
// 1 - bAsset -> Save/Savings Vault via Mint
// 2 - fAsset -> Save/Savings Vault via Feeder Pool
// 3 - ETH    -> Save/Savings Vault via Uniswap

interface ISaveWrapper {
    /**
     * @dev 0. Simply saves an mAsset and then into the vault
     * @param _mAsset   mAsset address
     * @param _save     Save address
     * @param _vault    Boosted Savings Vault address
     * @param _amount   Units of mAsset to deposit to savings
     */
    function saveAndStake(
        address _mAsset,
        address _save,
        address _vault,
        uint256 _amount
    ) external;

    /**
     * @dev 1. Mints an mAsset and then deposits to Save/Savings Vault
     * @param _mAsset       mAsset address
     * @param _save         Save address
     * @param _vault        Boosted Savings Vault address
     * @param _bAsset       bAsset address
     * @param _amount       Amount of bAsset to mint with
     * @param _minOut       Min amount of mAsset to get back
     * @param _stake        Add the imAsset to the Boosted Savings Vault?
     */
    function saveViaMint(
        address _mAsset,
        address _save,
        address _vault,
        address _bAsset,
        uint256 _amount,
        uint256 _minOut,
        bool _stake
    ) external;

    /**
     * @dev 2. Swaps fAsset for mAsset and then deposits to Save/Savings Vault
     * @param _mAsset             mAsset address
     * @param _save               Save address
     * @param _vault              Boosted Savings Vault address
     * @param _feeder             Feeder Pool address
     * @param _fAsset             fAsset address
     * @param _fAssetQuantity     Quantity of fAsset sent
     * @param _minOutputQuantity  Min amount of mAsset to be swapped and deposited
     * @param _stake              Deposit the imAsset in the Savings Vault?
     */
    function saveViaSwap(
        address _mAsset,
        address _save,
        address _vault,
        address _feeder,
        address _fAsset,
        uint256 _fAssetQuantity,
        uint256 _minOutputQuantity,
        bool _stake
    ) external;

    /**
     * @dev 3. Buys a bAsset on Uniswap with ETH, then mints imAsset via mAsset,
     *         optionally staking in the Boosted Savings Vault
     * @param _mAsset         mAsset address
     * @param _save           Save address
     * @param _vault          Boosted vault address
     * @param _uniswap        Uniswap router address
     * @param _amountOutMin   Min uniswap output in bAsset units
     * @param _path           Sell path on Uniswap (e.g. [WETH, DAI])
     * @param _minOutMStable  Min amount of mAsset to receive
     * @param _stake          Add the imAsset to the Savings Vault?
     */
    function saveViaUniswapETH(
        address _mAsset,
        address _save,
        address _vault,
        address _uniswap,
        uint256 _amountOutMin,
        address[] calldata _path,
        uint256 _minOutMStable,
        bool _stake
    ) external payable;

    /**
     * @dev Gets estimated mAsset output from a WETH > bAsset > mAsset trade
     * @param _mAsset       mAsset address
     * @param _uniswap      Uniswap router address
     * @param _ethAmount    ETH amount to sell
     * @param _path         Sell path on Uniswap (e.g. [WETH, DAI])
     */
    function estimate_saveViaUniswapETH(
        address _mAsset,
        address _uniswap,
        uint256 _ethAmount,
        address[] calldata _path
    ) external view returns (uint256 out);

    /**
     * @dev Approve mAsset and bAssets, Feeder Pools and fAssets, and Save/vault
     */
    function approve(
        address _mAsset,
        address[] calldata _bAssets,
        address[] calldata _fPools,
        address[] calldata _fAssets,
        address _save,
        address _vault
    ) external;

    /**
     * @dev Approve one token/spender
     */
    function approve(address _token, address _spender) external;

    /**
     * @dev Approve multiple tokens/one spender
     */
    function approve(address[] calldata _tokens, address _spender) external;
}
