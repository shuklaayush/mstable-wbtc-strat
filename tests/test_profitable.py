import brownie
from brownie import Contract
import pytest


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

    print(f"Vault assets: {vault.totalAssets()}")
    print(f"Strategy assets: {strategy.estimatedTotalAssets()}")

    # TODO: Add some code before harvest #2 to simulate earning yield
    chain.sleep(86400 * 7)  # 7 days
    chain.mine(1)

    print(f"Unclaimed rewards: {vimbtc.unclaimedRewards(strategy)[0]}")
    assert vimbtc.unclaimedRewards(strategy)[0] > 0

    # Harvest 2: Realize profit
    strategy.harvest()

    print(f"Vault assets: {vault.totalAssets()}")
    print(f"Strategy assets: {strategy.estimatedTotalAssets()}")
    print(f"Unclaimed rewards: {vimbtc.unclaimedRewards(strategy)[0]}")

    assert vimbtc.unclaimedRewards(strategy)[0] == 0

    chain.sleep(3600 * 6)  # 6 hrs needed for profits to unlock
    chain.mine(1)
    profit = token.balanceOf(vault.address)  # Profits go to vault

    # TODO: Uncomment the lines below
    # assert token.balanceOf(strategy) + profit > amount
    assert vault.pricePerShare() > before_pps
    assert vault.totalAssets() > before_total

    # User must make profit
    vault.withdraw(amount, {"from": user})
    assert token.balanceOf(user) > amount
