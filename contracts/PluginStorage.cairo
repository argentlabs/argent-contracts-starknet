%lang starknet

from starkware.cairo.common.cairo_builtins import HashBuiltin

@storage_var
func _storage(plugin_key: felt, var_name: felt) -> (res: felt):
end

func plugin_read{
        syscall_ptr : felt*,
        range_check_ptr,
        pedersen_ptr : HashBuiltin*
    } (
        plugin_key: felt,
        var_name: felt
    ) -> (value : felt):
    let (value) = _storage.read(plugin_key, var_name)
    return (value=value)

end

func plugin_write{
        syscall_ptr : felt*,
        range_check_ptr,
        pedersen_ptr : HashBuiltin*
    } (
        plugin_key: felt,
        var_name: felt,
        var_value: felt
    ):
    _storage.write(plugin_key, var_name, var_value)
    return()
end