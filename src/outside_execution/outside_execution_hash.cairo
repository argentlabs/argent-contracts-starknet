use argent::offchain_message::{
    interface::{
        StarkNetDomain, StarknetDomain, StructHashStarkNetDomain, IOffChainMessageHashRev1,
        IStructHashRev1
    },
    precalculated_hashing::get_message_hash_rev_1_with_precalc
};
use argent::outside_execution::interface::{OutsideExecution};
use hash::{HashStateTrait, HashStateExTrait};
use pedersen::PedersenTrait;
use poseidon::{poseidon_hash_span, hades_permutation, HashState};
use starknet::{get_tx_info, get_contract_address, account::Call};

const MAINNET_FIRST_HADES_PERMUTATION: (felt252, felt252, felt252) =
    (
        2727651893633223888261849279042022325174182119102281398572272198960815727249,
        729016093840936084580216898033636860729342953928695140840860652272753125883,
        2792630223211151632174198306610141883878913626231408099903852589995722964080
    );

const SEPOLIA_FIRST_HADES_PERMUTATION: (felt252, felt252, felt252) =
    (
        3580606761507954093996364807837346681513890124685758374532511352257317798951,
        3431227198346789440159663709265467470274870120429209591243179659934705045436,
        974062396530052497724701732977002885691473732259823426261944148730229556466
    );


const OUTSIDE_EXECUTION_TYPE_HASH_REV_2: felt252 =
    selector!(
        "\"OutsideExecution\"(\"Caller\":\"ContractAddress\",\"Nonce\":\"(felt,felt)\",\"Execute After\":\"u128\",\"Execute Before\":\"u128\",\"Calls\":\"Call*\")\"Call\"(\"To\":\"ContractAddress\",\"Selector\":\"selector\",\"Calldata\":\"felt*\")"
    );

const CALL_TYPE_HASH_REV_2: felt252 =
    selector!(
        "\"Call\"(\"To\":\"ContractAddress\",\"Selector\":\"selector\",\"Calldata\":\"felt*\")"
    );

impl StructHashCallRev2 of IStructHashRev1<Call> {
    fn get_struct_hash_rev_1(self: @Call) -> felt252 {
        poseidon_hash_span(
            array![
                CALL_TYPE_HASH_REV_2,
                (*self.to).into(),
                *self.selector,
                poseidon_hash_span(*self.calldata)
            ]
                .span()
        )
    }
}

impl StructHashOutsideExecutionRev2 of IStructHashRev1<OutsideExecution> {
    fn get_struct_hash_rev_1(self: @OutsideExecution) -> felt252 {
        let self = *self;
        let mut calls_span = self.calls;
        let mut hashed_calls = array![];

        while let Option::Some(call) = calls_span
            .pop_front() {
                hashed_calls.append(call.get_struct_hash_rev_1());
            };

        let (nonce_channel, nonce_index) = self.nonce;

        poseidon_hash_span(
            array![
                OUTSIDE_EXECUTION_TYPE_HASH_REV_2,
                self.caller.into(),
                nonce_channel,
                nonce_index,
                self.execute_after.into(),
                self.execute_before.into(),
                poseidon_hash_span(hashed_calls.span()),
            ]
                .span()
        )
    }
}

impl OffChainMessageOutsideExecutionRev2 of IOffChainMessageHashRev1<OutsideExecution> {
    fn get_message_hash_rev_1(self: @OutsideExecution) -> felt252 {
        // Version is a felt instead of a shortstring in SNIP-9 due to a mistake in the Braavos contracts and has been copied for compatibility.
        // Revision will also be a felt instead of a shortstring for all SNIP22-rev2 signatures because of the same issue

        let chain_id = get_tx_info().unbox().chain_id;
        if chain_id == 'SN_MAIN' {
            return get_message_hash_rev_1_with_precalc(MAINNET_FIRST_HADES_PERMUTATION, *self);
        }
        if chain_id == 'SN_SEPOLIA' {
            return get_message_hash_rev_1_with_precalc(SEPOLIA_FIRST_HADES_PERMUTATION, *self);
        }
        let domain = StarknetDomain {
            name: 'Account.execute_from_outside', version: 2, chain_id, revision: 2
        };
        poseidon_hash_span(
            array![
                'StarkNet Message',
                domain.get_struct_hash_rev_1(),
                get_contract_address().into(),
                (*self).get_struct_hash_rev_1(),
            ]
                .span()
        )
    }
}

