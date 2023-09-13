// companion for https://github.com/starkware-libs/cairo/blob/2a789fa04f0e2b61d92817afc2245bf966e3074e/corelib/src/poseidon.cairo#L65
fn pedersen_hash_span(mut span: Array<felt252>) -> felt252 {
    let mut state = 0;
    loop {
        match span.pop_front() {
            Option::Some(item) => {
                state = pedersen::pedersen(state, item);
            },
            Option::None => {
                break state;
            },
        };
    }
}
