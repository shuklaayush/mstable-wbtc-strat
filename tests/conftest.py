import pytest
from brownie import config, Contract, Wei


@pytest.fixture
def gov(accounts):
    yield accounts.at("0xFEB4acf3df3cDEA7399794D0869ef76A6EfAff52", force=True)


@pytest.fixture
def user(accounts):
    yield accounts[0]


@pytest.fixture
def rewards(accounts):
    yield accounts[1]


@pytest.fixture
def guardian(accounts):
    yield accounts[2]


@pytest.fixture
def management(accounts):
    yield accounts[3]


@pytest.fixture
def strategist(accounts):
    yield accounts[4]


@pytest.fixture
def keeper(accounts):
    yield accounts[5]


@pytest.fixture
def token():
    token_address = "0x2260FAC5E5542a773Aa44fBCfeDf7C193bc2C599"  # this should be the address of the ERC-20 used by the strategy/vault (DAI)
    yield Contract(token_address)


@pytest.fixture
def amount(accounts, token, user):
    # Capping investments at 100WBTC since mStable doesn't allow depositing more (exceeds weight limits)
    amount = 100 * 10 ** token.decimals()
    # In order to get some funds for the token you are about to use,
    # it impersonate an exchange address to use it's funds.
    reserve = accounts.at("0x9ff58f4ffb29fa2266ab25e75e2a8b3503311656", force=True)
    token.transfer(user, amount, {"from": reserve})
    yield amount


@pytest.fixture
def weth():
    token_address = "0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2"
    yield Contract(token_address)


@pytest.fixture
def weth_amount(user, weth):
    weth_amount = 10 ** weth.decimals()
    user.transfer(weth, weth_amount)
    yield weth_amount


@pytest.fixture
def vimbtc():
    token_address = "0xf38522f63f40f9dd81abafd2b8efc2ec958a3016"
    yield Contract(token_address)


@pytest.fixture
def imbtc():
    token_address = "0x17d8cbb6bce8cee970a4027d1198f6700a7a6c24"
    yield Contract(token_address)


@pytest.fixture
def mbtc():
    token_address = "0x945facb997494cc2570096c74b5f66a3507330a1"
    yield Contract(token_address)


@pytest.fixture
def reward():
    token_address = "0xa3BeD4E1c75D00fa6f4E5E6922DB7261B5E9AcD2"
    yield Contract(token_address)


@pytest.fixture
def rewards_keeper(reward, accounts):
    # Transfer MTA to rewards keeper
    account_address = "0xB81473F20818225302B8FFFB905B53D58A793D84"
    rewards_whale = "0x3dd46846eed8D147841AE162C8425c08BD8E1b41"
    reward.transfer(account_address, Wei("300000 ether"), {"from": rewards_whale})
    yield accounts.at(account_address, force=True)


@pytest.fixture
def rewards_distributor():
    contract_address = "0x04dfDfa471b79cc9E6E8C355e6C71F8eC4916C50"
    yield Contract(contract_address)


@pytest.fixture
def sleep_and_topup_rewards(chain, rewards_distributor, rewards_keeper, vimbtc):
    def f(t):
        while t > 0:
            reward_period_left = vimbtc.periodFinish() - chain.time()
            # Add pending MTA rewards
            if t > reward_period_left:
                chain.sleep(vimbtc.periodFinish() - chain.time())
                rewards_distributor.distributeRewards(
                    [vimbtc], [Wei("7000 ether")], {"from": rewards_keeper}
                )
            else:
                chain.sleep(t)
            t -= min(t, reward_period_left)
            chain.mine(1)

    yield f


@pytest.fixture
def vault(pm, gov, rewards, guardian, management, token):
    Vault = pm(config["dependencies"][0]).Vault
    vault = guardian.deploy(Vault)
    vault.initialize(token, gov, rewards, "", "", guardian, management)
    vault.setDepositLimit(2 ** 256 - 1, {"from": gov})
    vault.setManagement(management, {"from": gov})
    yield vault


@pytest.fixture
def strategy(strategist, keeper, vault, Strategy, gov):
    strategy = strategist.deploy(Strategy, vault)
    strategy.setKeeper(keeper)
    vault.addStrategy(strategy, 10_000, 0, 2 ** 256 - 1, 1_000, {"from": gov})
    yield strategy


@pytest.fixture(scope="session")
def RELATIVE_APPROX():
    yield 50e-4  # 0.48% max slippage (from strategy) + 0.02% redemption fee on mBTC


@pytest.fixture(autouse=True)
def isolation(fn_isolation):
    pass
