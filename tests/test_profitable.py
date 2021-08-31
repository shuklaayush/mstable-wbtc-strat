import brownie
from brownie import Contract, Wei
import pytest


def days(x):
    return 24 * 3600 * x


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
    gov,
    amount,
    RELATIVE_APPROX,
    vimbtc,
    sleep_and_topup_rewards,
):
    # Set management fee to 0
    vault.setManagementFee(0, {"from": gov})

    # Deposit to the vault
    print(f"User balance (before): {token.balanceOf(user) / 10 ** token.decimals()}")
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
    num_days = 360
    harvest_freq_days = 3
    for i in range(0, num_days, harvest_freq_days):
        sleep_and_topup_rewards(days(harvest_freq_days))
        # print(f"Unclaimed rewards (day {i + harvest_freq_days}): {vimbtc.unclaimedRewards(strategy)[0] / 1e18}")
        assert vimbtc.unclaimedRewards(strategy)[0] > 0

        # Harvest 2: Realize profit
        strategy.harvest()
        # print(
        #     f"Strategy vimbtc: {vimbtc.balanceOf(strategy) / 1e18}"
        # )
        # print(
        #     f"Strategy assets: {strategy.estimatedTotalAssets() / 10 ** token.decimals()}"
        # )

    print(f"Vault assets: {vault.totalAssets() / 10 ** token.decimals()}")
    print(
        f"Strategy assets: {strategy.estimatedTotalAssets() / 10 ** token.decimals()}"
    )
    assert vimbtc.unclaimedRewards(strategy)[0] == 0

    chain.sleep(3600 * 6)  # 6 hrs needed for profits to unlock
    chain.mine(1)
    profit = token.balanceOf(vault.address)  # Profits go to vault

    # TODO: Uncomment the lines below
    assert vault.totalAssets() > before_total
    assert vault.pricePerShare() > before_pps
    assert strategy.estimatedTotalAssets() + profit > amount

    print(
        f"\nEstimated APR (after {num_days} days): ",
        "{:.2%}".format(
            (days(365.25) / days(num_days))
            * (vault.totalAssets() - before_total)
            / before_total
        ),
    )

    # User must make profit
    vault.withdraw(amount, {"from": user})
    assert token.balanceOf(user) > amount
    print(f"User balance (after): {token.balanceOf(user) / 10 ** token.decimals()}\n")
