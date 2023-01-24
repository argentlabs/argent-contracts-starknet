%lang starknet

from contracts.account.library import CallArray

@contract_interface
namespace IPlugin {
    // Method to call during validation
    func validate(
        plugin_data_len: felt,
        plugin_data: felt*,
        call_array_len: felt,
        call_array: CallArray*,
        calldata_len: felt,
        calldata: felt*
    ) {
    }
}
