#[contract]
mod Multicall {
    use contracts::dummy_syscalls;


    // ////////////////////////////////////////////////////////////////////////
    // The Multicall contract can call an array of view methods on different
    // contracts and return the aggregate response as an array.
    // Input: same as the IAccount.__execute__ 
    // @return (block_number, retdata_size, retdata)
    //   Where retdata is [len(call_1_data), *call_1_data, len(call_2_data), *call_2_data, ..., len(call_N_data), *call_N_data]
    // ///////////////////////////////////////////////////////////////////////
    #[view]
    fn aggregate(call_array: Array::<felt>, calldata:Array::<felt>) -> felt { // (felt, Array::<felt>)
    // let (retdata_len, retdata) = execute_multicall(call_array_len, call_array, calldata);
        dummy_syscalls::get_block_number()
    }
}