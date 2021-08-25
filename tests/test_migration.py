# TODO: Add tests that show proper migration of the strategy to a newer one
#       Use another copy of the strategy to simulate the migration
#       Show that nothing is lost!

import pytest


def test_migration(
    chain,
    token,
    vault,
    strategy,
    amount,
    Strategy,
    strategist,
    gov,
    user,
    RELATIVE_APPROX,
    RELATIVE_APPROX_WBTC,
    vimbtc,
    imbtc,
):
    # Deposit to the vault and harvest
    token.approve(vault.address, amount, {"from": user})
    vault.deposit(amount, {"from": user})
    chain.sleep(1)
    strategy.harvest()

    estimate_before = strategy.estimatedTotalAssets()
    vimbtc_before = vimbtc.balanceOf(strategy)
    assert vimbtc_before > 0

    # TODO: Strategy underestimates assets because mbtc:wbtc is assumed 1:1 pegged
    assert pytest.approx(estimate_before, rel=RELATIVE_APPROX_WBTC) == amount

    # migrate to a new strategy
    new_strategy = strategist.deploy(Strategy, vault)
    vault.migrateStrategy(strategy, new_strategy, {"from": gov})
    assert (
        pytest.approx(new_strategy.estimatedTotalAssets(), rel=RELATIVE_APPROX_WBTC)
        == amount
    )
    assert (
        pytest.approx(new_strategy.estimatedTotalAssets(), rel=RELATIVE_APPROX)
        == estimate_before
    )

    # imBTC-vault is unstaked to imBTC and transferred during migration
    assert vimbtc_before == imbtc.balanceOf(new_strategy)
    assert vimbtc.balanceOf(new_strategy) == 0

    # Tend to stake imBTC to imBTC-vault
    new_strategy.tend()
    assert vimbtc_before == vimbtc.balanceOf(new_strategy)
    assert imbtc.balanceOf(new_strategy) == 0

    assert (
        pytest.approx(new_strategy.estimatedTotalAssets(), rel=RELATIVE_APPROX_WBTC)
        == amount
    )
    assert (
        pytest.approx(new_strategy.estimatedTotalAssets(), rel=RELATIVE_APPROX)
        == estimate_before
    )
