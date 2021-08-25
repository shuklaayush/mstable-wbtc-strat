import brownie
from brownie import Contract
import pytest


def test_operation(
    chain,
    accounts,
    token,
    vault,
    strategy,
    user,
    strategist,
    amount,
    RELATIVE_APPROX,
    RELATIVE_APPROX_WBTC,
):
    # Deposit to the vault
    user_balance_before = token.balanceOf(user)
    token.approve(vault.address, amount, {"from": user})
    vault.deposit(amount, {"from": user})
    assert token.balanceOf(vault.address) == amount

    # harvest
    chain.sleep(1)
    strategy.harvest()
    assert (
        pytest.approx(strategy.estimatedTotalAssets(), rel=RELATIVE_APPROX_WBTC)
        == amount
    )

    # tend()
    strategy.tend()

    # withdrawal
    vault.withdraw(vault.balanceOf(user), user, 10, {"from": user})
    assert (
        pytest.approx(token.balanceOf(user), rel=RELATIVE_APPROX_WBTC)
        == user_balance_before
    )


def test_emergency_exit(
    chain,
    accounts,
    token,
    vault,
    strategy,
    user,
    strategist,
    amount,
    RELATIVE_APPROX,
    RELATIVE_APPROX_WBTC,
):
    # Deposit to the vault
    token.approve(vault.address, amount, {"from": user})
    vault.deposit(amount, {"from": user})
    chain.sleep(1)
    strategy.harvest()
    assert (
        pytest.approx(strategy.estimatedTotalAssets(), rel=RELATIVE_APPROX_WBTC)
        == amount
    )

    # set emergency and exit
    strategy.setEmergencyExit()
    chain.sleep(1)
    strategy.harvest()
    assert strategy.estimatedTotalAssets() < amount


# def test_profitable_harvest(
#     chain,
#     accounts,
#     token,
#     vault,
#     strategy,
#     user,
#     strategist,
#     amount,
#     RELATIVE_APPROX,
#     RELATIVE_APPROX_WBTC,
#     vimbtc,
# ):
#     # Deposit to the vault
#     token.approve(vault.address, amount, {"from": user})
#     vault.deposit(amount, {"from": user})
#     assert token.balanceOf(vault.address) == amount

#     # Harvest 1: Send funds through the strategy
#     chain.sleep(1)
#     strategy.harvest()
#     assert (
#         pytest.approx(strategy.estimatedTotalAssets(), rel=RELATIVE_APPROX_WBTC)
#         == amount
#     )

#     # Setup harvest #2 to simulate earning yield
#     before_pps = vault.pricePerShare()
#     before_total = vault.totalAssets()

#     print(f"Vault assets: {vault.totalAssets()}")
#     print(f"Strategy assets: {strategy.estimatedTotalAssets()}")

#     # TODO: Add some code before harvest #2 to simulate earning yield
#     chain.sleep(86400 * 7)  # 7 days
#     chain.mine(1)

#     print(f"Unclaimed rewards: {vimbtc.unclaimedRewards(strategy)[0]}")
#     assert vimbtc.unclaimedRewards(strategy)[0] > 0

#     # Harvest 2: Realize profit
#     strategy.harvest()

#     print(f"Vault assets: {vault.totalAssets()}")
#     print(f"Strategy assets: {strategy.estimatedTotalAssets()}")
#     print(f"Unclaimed rewards: {vimbtc.unclaimedRewards(strategy)[0]}")

#     assert vimbtc.unclaimedRewards(strategy)[0] == 0

#     chain.sleep(3600 * 6)  # 6 hrs needed for profits to unlock
#     chain.mine(1)
#     profit = token.balanceOf(vault.address)  # Profits go to vault

#     # TODO: Uncomment the lines below
#     # assert token.balanceOf(strategy) + profit > amount
#     assert vault.pricePerShare() > before_pps
#     assert vault.totalAssets() > before_total

#     # User must make profit
#     vault.withdraw(amount, {"from": user})
#     assert token.balanceOf(user) > amount


def test_change_debt(
    chain,
    gov,
    token,
    vault,
    strategy,
    user,
    strategist,
    amount,
    RELATIVE_APPROX,
    RELATIVE_APPROX_WBTC,
):
    # Deposit to the vault and harvest
    token.approve(vault.address, amount, {"from": user})
    vault.deposit(amount, {"from": user})
    vault.updateStrategyDebtRatio(strategy.address, 5_000, {"from": gov})
    chain.sleep(1)
    strategy.harvest()
    half = int(amount / 2)

    assert (
        pytest.approx(strategy.estimatedTotalAssets(), rel=RELATIVE_APPROX_WBTC) == half
    )

    vault.updateStrategyDebtRatio(strategy.address, 10_000, {"from": gov})
    chain.sleep(1)
    strategy.harvest()
    assert (
        pytest.approx(strategy.estimatedTotalAssets(), rel=RELATIVE_APPROX_WBTC)
        == amount
    )

    # In order to pass this tests, you will need to implement prepareReturn.
    vault.updateStrategyDebtRatio(strategy.address, 5_000, {"from": gov})
    chain.sleep(1)
    strategy.harvest()
    assert (
        pytest.approx(strategy.estimatedTotalAssets(), rel=RELATIVE_APPROX_WBTC) == half
    )


def test_sweep(
    gov, vault, strategy, token, user, amount, weth, weth_amount, vimbtc, imbtc, reward
):
    # Strategy want token doesn't work
    token.transfer(strategy, amount, {"from": user})
    assert token.address == strategy.want()
    assert token.balanceOf(strategy) > 0
    with brownie.reverts("!want"):
        strategy.sweep(token, {"from": gov})

    # Vault share token doesn't work
    with brownie.reverts("!shares"):
        strategy.sweep(vault.address, {"from": gov})

    # Protected token doesn't work
    for token in [vimbtc, imbtc, reward]:
        with brownie.reverts("!protected"):
            strategy.sweep(token, {"from": gov})

    before_balance = weth.balanceOf(gov)
    weth.transfer(strategy, weth_amount, {"from": user})
    assert weth.address != strategy.want()
    assert weth.balanceOf(user) == 0
    strategy.sweep(weth, {"from": gov})
    assert weth.balanceOf(gov) == weth_amount + before_balance


def test_triggers(
    chain, gov, vault, strategy, token, amount, user, weth, weth_amount, strategist
):
    # Deposit to the vault and harvest
    token.approve(vault.address, amount, {"from": user})
    vault.deposit(amount, {"from": user})
    vault.updateStrategyDebtRatio(strategy.address, 5_000, {"from": gov})
    chain.sleep(1)
    strategy.harvest()

    strategy.harvestTrigger(0)
    strategy.tendTrigger(0)
