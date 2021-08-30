import brownie
from brownie import Contract, Wei
import pytest


def hours(x):
    return x * 3600


def days(x):
    return 24 * hours(x)


def weeks(x):
    return 7 * days(x)


def test_profitable_harvest(
    chain,
    accounts,
    token,
    vault,
    strategy,
    user,
    strategist,
    amount,
    RELATIVE_APPROX,
    vimbtc,
    sleep_wrapper,
):
    # Deposit to the vault
    token.approve(vault.address, amount, {"from": user})
    vault.deposit(amount, {"from": user})
    assert token.balanceOf(vault.address) == amount

    # Harvest 1: Send funds through the strategy
    chain.sleep(1)
    strategy.harvest()
    assert pytest.approx(strategy.estimatedTotalAssets(), rel=RELATIVE_APPROX) == amount

    # Setup harvest #2 to simulate earning yield
    before_pps = vault.pricePerShare()
    before_total = vault.totalAssets()

    print(f"Vault assets: {vault.totalAssets() / 10 ** token.decimals()}")
    print(
        f"Strategy assets: {strategy.estimatedTotalAssets() / 10 ** token.decimals()}"
    )

    # TODO: Add some code before harvest #2 to simulate earning yield
    sleep_wrapper(weeks(12))

    print(f"Unclaimed rewards: {vimbtc.unclaimedRewards(strategy)[0] / 1e18}")
    assert vimbtc.unclaimedRewards(strategy)[0] > 0

    # Harvest 2: Realize profit
    strategy.harvest()

    print(f"Vault assets: {vault.totalAssets() / 10 ** token.decimals()}")
    print(
        f"Strategy assets: {strategy.estimatedTotalAssets() / 10 ** token.decimals()}"
    )
    print(f"Unclaimed rewards: {vimbtc.unclaimedRewards(strategy)[0] / 1e18}")
    assert vimbtc.unclaimedRewards(strategy)[0] == 0

    chain.sleep(3600 * 6)  # 6 hrs needed for profits to unlock
    chain.mine(1)
    profit = token.balanceOf(vault.address)  # Profits go to vault

    # TODO: Uncomment the lines below
    assert vault.totalAssets() > before_total
    # assert vault.pricePerShare() > before_pps
    assert strategy.estimatedTotalAssets() + profit > amount

    # assert False

    # User must make profit
    vault.withdraw(amount, {"from": user})
    assert token.balanceOf(user) > amount
