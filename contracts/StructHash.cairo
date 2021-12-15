%lang starknet
%builtins pedersen range_check ecdsa bitwise

from starkware.cairo.common.alloc import alloc
from starkware.cairo.common.cairo_builtins import HashBuiltin
from starkware.cairo.common.hash_state import (
    HashState, hash_finalize, hash_init, hash_update, hash_update_single)
from starkware.cairo.common.registers import get_fp_and_pc

struct StarkNet_Domain:
    member name : felt
    member version : felt
    member chain_id : felt
end

struct Person:
    member name : felt
    member wallet : felt
end

struct Mail:
    member from2 : Person
    member to : Person
    member contents : felt
end

# H('StarkNetDomain(name:felt,version:felt,chainId:felt)')
const STARKNET_DOMAIN_TYPE_HASH = 0x1bfc207425a47a5dfa1a50a4f5241203f50624ca5fdf5e18755765416b8e288

# H('Mail(from:Person,to:Person,contents:felt)Person(name:felt,wallet:felt)')
const MAIL_TYPE_HASH = 0x13d89452df9512bf750f539ba3001b945576243288137ddb6c788457d4b2f79

# H('Person(name:felt,wallet:felt)')
const PERSON_TYPE_HASH = 0x2896dbe4b96a67110f454c01e5336edc5bbc3635537efd690f122f4809cc855

# takes StarkNetDomain and returns its struct_hash
func hashDomain{hash_ptr : HashBuiltin*}(domain : StarkNet_Domain*) -> (hash : felt):
    let (hash_state : HashState*) = hash_init()
    let (hash_state) = hash_update_single(hash_state_ptr=hash_state, item=STARKNET_DOMAIN_TYPE_HASH)
    let (hash_state) = hash_update_single(hash_state_ptr=hash_state, item=domain.name)
    let (hash_state) = hash_update_single(hash_state_ptr=hash_state, item=domain.version)
    let (hash_state) = hash_update_single(hash_state_ptr=hash_state, item=domain.chain_id)
    let (hash : felt) = hash_finalize(hash_state_ptr=hash_state)
    return (hash=hash)
end

# takes Person and returns its struct_hash
func hashPerson{hash_ptr : HashBuiltin*}(person : Person*) -> (hash : felt):
    let (hash_state : HashState*) = hash_init()
    let (hash_state) = hash_update_single(hash_state_ptr=hash_state, item=PERSON_TYPE_HASH)
    let (hash_state) = hash_update_single(hash_state_ptr=hash_state, item=person.name)
    let (hash_state) = hash_update_single(hash_state_ptr=hash_state, item=person.wallet)
    let (hash : felt) = hash_finalize(hash_state_ptr=hash_state)
    return (hash=hash)
end

# takes Mail and returns its struct_hash
func hashMail{hash_ptr : HashBuiltin*}(mail : Mail*) -> (hash : felt):
    let (hash_state : HashState*) = hash_init()
    let (hash_state) = hash_update_single(hash_state_ptr=hash_state, item=MAIL_TYPE_HASH)
    let (personFromHash : felt) = hashPerson(person=&mail.from2)
    let (hash_state) = hash_update_single(hash_state_ptr=hash_state, item=personFromHash)
    let (personToHash : felt) = hashPerson(person=&mail.to)
    let (hash_state) = hash_update_single(hash_state_ptr=hash_state, item=personToHash)
    let (hash_state) = hash_update_single(hash_state_ptr=hash_state, item=mail.contents)
    let (hash : felt) = hash_finalize(hash_state_ptr=hash_state)
    return (hash=hash)
end

func hashMessage{hash_ptr : HashBuiltin*}(
        domain : StarkNet_Domain, mail : Mail, account : felt) -> (hash : felt):
    let (__fp__, _) = get_fp_and_pc()

    let (hash_state : HashState*) = hash_init()
    let (hash_state) = hash_update_single(hash_state_ptr=hash_state, item='StarkNet Message')
    let (hashDomainHash : felt) = hashDomain(domain=&domain)
    let (hash_state) = hash_update_single(hash_state_ptr=hash_state, item=hashDomainHash)
    let (hash_state) = hash_update_single(hash_state_ptr=hash_state, item=account)
    let (hashMailHash : felt) = hashMail(mail=&mail)
    let (hash_state) = hash_update_single(hash_state_ptr=hash_state, item=hashMailHash)
    let (hash : felt) = hash_finalize(hash_state_ptr=hash_state)
    return (hash=hash)
end

# test view
@view
func test{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}() -> (hash : felt):
    alloc_locals
    let (__fp__, _) = get_fp_and_pc()

    local domain : StarkNet_Domain = StarkNet_Domain(
        name='StarkNet Mail',
        version=1,
        chain_id=1
        )

    local cow : Person = Person(
        name='Cow',
        wallet=0xCD2a3d9F938E13CD947Ec05AbC7FE734Df8DD826,
        )
    local bob : Person = Person(
        name='Bob',
        wallet=0xbBbBBBBbbBBBbbbBbbBbbbbBBbBbbbbBbBbbBBbB,
        )
    local mail : Mail = Mail(
        from2=cow,
        to=bob,
        contents='Hello, Bob!'
        )
    let (messageHash : felt) = hashMessage{hash_ptr=pedersen_ptr}(
        domain=domain, mail=mail, account=cow.wallet)

    return (hash=messageHash)
end
