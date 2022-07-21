%lang starknet
from starkware.cairo.common.cairo_builtins import HashBuiltin
from starkware.starknet.common.syscalls import get_contract_address, get_caller_address
from starkware.cairo.common.uint256 import Uint256

# rock, paper, scissors game
# takes 1 token on each bet and winner takes all tokens

# 0 = none, 1 = rock, 2 = paper, 3 = scissors
const ROCK = 1
const PAPER = 2
const SCISSORS = 3

@contract_interface
namespace ERC20:
    func transferFrom(sender : felt, recipient : felt, amount : Uint256) -> (success : felt):
    end
end

@contract_interface
namespace Game:
    func get_winner() -> (res : felt):
    end
end

@storage_var
func _token() -> (res : felt):
end

@storage_var
func _player1() -> (res : felt):
end

@storage_var
func _player2() -> (res : felt):
end

@storage_var
func _selectionFromPlayer1() -> (res : felt):
end

@storage_var
func _selectionFromPlayer2() -> (res : felt):
end

func assert_player{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}() -> ():
    let (caller_address) = get_caller_address()
    let (player1) = _player1.read()
    let (player2) = _player2.read()
    with_attr error_message("caller must be player"):
        assert ((player1 - caller_address) * (player2 - caller_address)) = 0
    end
    return ()
end

func assert_valid_selection{syscall_ptr : felt*}(selection : felt) -> ():
    with_attr error_message("selection must be 1, 2, or 3"):
        assert ((selection - 1) * (selection - 2) * (selection - 3)) = 0
    end
    return ()
end

@external
func bet{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}(selection : felt):
    assert_player()
    assert_valid_selection(selection)

    let (caller_address) = get_caller_address()
    let (player1) = _player1.read()
    let (player2) = _player2.read()
    let (selectionFromPlayer1) = _selectionFromPlayer1.read()
    let (selectionFromPlayer2) = _selectionFromPlayer2.read()

    if player1 == caller_address:
        with_attr error_message("already submitted"):
            assert (selectionFromPlayer1) = 0
        end
        _selectionFromPlayer1.write(selection)
        if selectionFromPlayer2 != 0:
            # call get_winner on self
            let (self) = get_contract_address()
            let (winner) = Game.get_winner(contract_address=self)
            if ((winner - player1) * (winner - player2)) == 0:
                let (token) = _token.read()
                if winner == player1:
                    ERC20.transferFrom(
                        contract_address=token,
                        sender=player2,
                        recipient=player1,
                        amount=Uint256(1000000000000000000, 0),
                    )
                    return ()
                else:
                    ERC20.transferFrom(
                        contract_address=token,
                        sender=player1,
                        recipient=player2,
                        amount=Uint256(1000000000000000000, 0),
                    )
                    return ()
                end
            end
            return ()
        end
    else:
        with_attr error_message("already submitted"):
            assert (selectionFromPlayer2) = 0
        end
        _selectionFromPlayer2.write(selection)
        if selectionFromPlayer1 != 0:
            # call get_winner on self
            let (self) = get_contract_address()
            let (winner) = Game.get_winner(contract_address=self)
            if ((winner - player1) * (winner - player2)) == 0:
                let (token) = _token.read()
                if winner == player1:
                    ERC20.transferFrom(
                        contract_address=token,
                        sender=player2,
                        recipient=player1,
                        amount=Uint256(1000000000000000000, 0),
                    )
                    return ()
                else:
                    ERC20.transferFrom(
                        contract_address=token,
                        sender=player1,
                        recipient=player2,
                        amount=Uint256(1000000000000000000, 0),
                    )
                    return ()
                end
            end
            return ()
        end
    end

    return ()
end

@view
func get_winner{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}() -> (
    res : felt
):
    let (player1) = _player1.read()
    let (player2) = _player2.read()
    let (selectionFromPlayer1) = _selectionFromPlayer1.read()
    let (selectionFromPlayer2) = _selectionFromPlayer2.read()

    if selectionFromPlayer1 == ROCK:
        if selectionFromPlayer2 == PAPER:
            return (player2)
        end
        if selectionFromPlayer2 == SCISSORS:
            return (player1)
        end
        if (selectionFromPlayer1 * selectionFromPlayer2) == 0:
            return (0)
        end
        return (1)
    end

    if selectionFromPlayer1 == PAPER:
        if selectionFromPlayer2 == ROCK:
            return (player1)
        end
        if selectionFromPlayer2 == SCISSORS:
            return (player2)
        end
        if (selectionFromPlayer1 * selectionFromPlayer2) == 0:
            return (0)
        end
        return (1)
    end

    if selectionFromPlayer1 == SCISSORS:
        if selectionFromPlayer2 == ROCK:
            return (player2)
        end
        if selectionFromPlayer2 == PAPER:
            return (player1)
        end
        if (selectionFromPlayer1 * selectionFromPlayer2) == 0:
            return (0)
        end
        return (1)
    end

    if (selectionFromPlayer1 * selectionFromPlayer2) == 0:
        return (0)
    end

    return (1)
end

@view
func get_players{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}() -> (
    player1 : felt, player2 : felt
):
    let (player1) = _player1.read()
    let (player2) = _player2.read()
    return (player1, player2)
end

@constructor
func constructor{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}(
    token : felt, player1 : felt, player2 : felt
):
    _token.write(token)
    _player1.write(player1)
    _player2.write(player2)
    return ()
end
