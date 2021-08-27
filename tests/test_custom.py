import brownie


def test_set_variables(
    chain,
    accounts,
    token,
    vault,
    strategy,
    user,
    gov,
    amount,
    vimbtc,
):
    # Deposit to the vault
    token.approve(vault.address, amount, {"from": user})
    vault.deposit(amount, {"from": user})
    assert token.balanceOf(vault.address) == amount

    # harvest
    chain.sleep(1)
    strategy.harvest()

    # Get rewards
    chain.sleep(86400 * 1)  # 7 days
    chain.mine(1)
    assert vimbtc.unclaimedRewards(strategy)[0] > 0

    # Realize profit
    strategy.harvest()

    # Set variables
    strategy.setCheckSlippageRewardToWant(False, {"from": gov})
    assert strategy.checkSlippageRewardToWant() == False

    strategy.setSlippageRewardToWant(10_000, {"from": gov})
    assert strategy.slippageRewardToWant() == 10_000

    strategy.setSlippageWantToMbtc(10_000, {"from": gov})
    assert strategy.slippageWantToMbtc() == 10_000

    # Get rewards
    chain.sleep(86400 * 1)  # 7 days
    chain.mine(1)
    assert vimbtc.unclaimedRewards(strategy)[0] > 0

    # Realize profit
    strategy.harvest()

    # Basis points <= 10000
    for fn in [strategy.setSlippageWantToMbtc, strategy.setSlippageRewardToWant]:
        with brownie.reverts():
            fn(100_000, {"from": gov})

    # Only vault managers
    random_user = accounts[-1]
    for fn, arg in [
        (strategy.setCheckSlippageRewardToWant, True),
        (strategy.setSlippageRewardToWant, 100),
        (strategy.setSlippageWantToMbtc, 100),
    ]:
        with brownie.reverts("!authorized"):
            fn(arg, {"from": random_user})
