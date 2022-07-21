%lang starknet
from starkware.cairo.common.cairo_builtins import HashBuiltin
from starkware.starknet.common.syscalls import get_caller_address

# rock, paper, scissors game
# takes 1 token on each bet and winner takes all tokens

# 0 = none, 1 = rock, 2 = paper, 3 = scissors
const ROCK = 1
const PAPER = 2
const SCISSORS = 3

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

    if player1 == caller_address:
        let (selectionFromPlayer1) = _selectionFromPlayer1.read()
        with_attr error_message("already submitted"):
            assert (selectionFromPlayer1) = 0
        end
        _selectionFromPlayer1.write(selection)
    else:
        let (selectionFromPlayer2) = _selectionFromPlayer2.read()
        with_attr error_message("already submitted"):
            assert (selectionFromPlayer2) = 0
        end
        _selectionFromPlayer2.write(selection)
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
    player1 : felt, player2 : felt
):
    _player1.write(player1)
    _player2.write(player2)
    return ()
end
