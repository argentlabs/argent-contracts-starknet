import pytest
import asyncio
import logging
from starkware.starknet.testing.starknet import Starknet
from starkware.starknet.business_logic.state.state import BlockInfo
from utils.Signer import Signer
from utils.utilities import deploy, assert_revert, str_to_felt, assert_event_emmited
from utils.TransactionSender import TransactionSender

LOGGER = logging.getLogger(__name__)

player1 = Signer(123456789987654321)
player2 = Signer(456789987654321123)


@pytest.fixture(scope='module')
def event_loop():
    return asyncio.new_event_loop()


@pytest.fixture(scope='module')
async def get_starknet():
    starknet = await Starknet.empty()
    return starknet


@pytest.fixture
async def account1_factory(get_starknet):
    starknet = get_starknet
    account = await deploy(starknet, "contracts/ArgentAccount.cairo")
    await account.initialize(player1.public_key, 0).invoke()
    return account


@pytest.fixture
async def account2_factory(get_starknet):
    starknet = get_starknet
    account = await deploy(starknet, "contracts/ArgentAccount.cairo")
    await account.initialize(player2.public_key, 0).invoke()
    return account


@pytest.fixture
async def game_factory(get_starknet, account1_factory, account2_factory):
    starknet = get_starknet
    account1 = account1_factory
    account2 = account2_factory
    dapp = await deploy(starknet, "contracts/Game.cairo", [account1.contract_address, account2.contract_address])
    return dapp


@pytest.mark.asyncio
async def test_accounts(account1_factory, account2_factory):
    account1 = account1_factory
    account2 = account2_factory
    # should be configured correctly
    assert (await account1.get_signer().call()).result.signer == (player1.public_key)
    assert (await account2.get_signer().call()).result.signer == (player2.public_key)


@pytest.mark.asyncio
async def test_game_defaults(game_factory, account1_factory, account2_factory):
    game = game_factory
    account1 = account1_factory
    account2 = account2_factory
    # should be configured correctly
    assert (await game.get_winner().call()).result.res == 0
    assert (await game.get_players().call()).result.player1 == account1.contract_address
    assert (await game.get_players().call()).result.player2 == account2.contract_address


@pytest.mark.asyncio
# test cases with the following parameters:
# - input_player1: the move player 1 is going to play (0 if no move, 1 = rock, 2 = paper, 3 = scissors)
# - input_player2: the move player 2 is going to play (0 if no move, 1 = rock, 2 = paper, 3 = scissors)
# - winner: the expected winner of the game (-1 if game is not over yet, 0 if it's a tie, 1 if player 1 won, 2 if player 2 won)
@pytest.mark.parametrize("input_player1,input_player2,winner", [
    # 0 = none, 1 = rock, 2 = paper, 3 = scissors
    (0, 0, -1),  # no one played, game is not over
    (0, 1, -1),  # player 1 didn't play, game is not over
    (0, 2, -1),  # player 2 didn't play, game is not over
    (0, 3, -1),  # player 1 didn't play, game is not over
    (1, 0, -1),  # player 2 didn't play, game is not over
    (1, 1, 0),  # rock vs rock, tie
    (1, 2, 2),  # rock vs paper, player 2 wins
    (1, 3, 1),  # rock vs scissors, player 1 wins
    (2, 0, -1),  # player 2 didn't play, game is not over
    (2, 1, 1),  # paper vs rock, player 1 wins
    (2, 2, 0),  # paper vs paper, tie
    (2, 3, 2),  # paper vs scissors, player 2 wins
    (3, 0, -1),  # player 2 didn't play, game is not over
    (3, 1, 2),  # scissors vs rock, player 2 wins
    (3, 2, 1),  # scissors vs paper, player 1 wins
    (3, 3, 0),  # scissors vs scissors, tie
])
async def test_game(game_factory, account1_factory, account2_factory, input_player1, input_player2, winner):
    game = game_factory
    account1 = account1_factory
    account2 = account2_factory
    sender1 = TransactionSender(account1)
    sender2 = TransactionSender(account2)

    calls1 = [(game.contract_address, 'bet', [input_player1])]
    calls2 = [(game.contract_address, 'bet', [input_player2])]

    if input_player1 > 0:
        await sender1.send_transaction(calls1, [player1])
    if input_player2 > 0:
        await sender2.send_transaction(calls2, [player2])

    expectedWinnerAccountAddress = (1 if winner == 0 else (
        account1.contract_address if winner == 1 else (account2.contract_address if winner == 2 else 0)))

    assert (await game.get_winner().call()).result.res == expectedWinnerAccountAddress
