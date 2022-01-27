from starkware.cairo.common.memcpy import memcpy
from starkware.cairo.common.alloc import alloc

func array_concat{
        range_check_ptr
    } (
        a_len: felt,
        a: felt*,
        b_len: felt,
        b: felt*,
    ) -> (
        res_len: felt,
        res: felt*
    ):
    alloc_locals
    let (local a_cpy: felt*) = alloc()

    memcpy(a_cpy, a, a_len)
    memcpy(a_cpy + a_len, b, b_len)

    return (a_len + b_len, a_cpy)
end