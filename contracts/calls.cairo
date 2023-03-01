#[derive(Drop)]
struct Call {
    to: ContractAddress,
    selector: felt,
    calldata: Array::<felt>,
}
