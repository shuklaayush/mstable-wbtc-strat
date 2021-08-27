import brownie
from brownie import Contract
import pytest


def test_setup_address(strategy, token, mbtc, imbtc):
    assert strategy.mbtc() == mbtc
    assert strategy.imbtc() == imbtc
    assert strategy.wantDecimals() == token.decimals()
