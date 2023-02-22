mod test_asserts;
mod test_argent_account;
mod test_argent_account_signatures;
mod test_argent_account_escape;

use contracts::ArgentAccount;

fn initialize_account() {
    ArgentAccount::initialize(signer().pubkey, guardian().pubkey, 0);
}

fn initialize_account_without_guardian() {
    ArgentAccount::initialize(signer().pubkey, 0, 0);
}

#[derive(Copy)]
struct Signature {
    pubkey: felt,
    r: felt,
    s: felt,
}

fn signer() -> Signature {
    Signature {
        pubkey: 0x1ef15c18599971b7beced415a40f0c7deacfd9b0d1819e03d723d8bc943cfca,
        r: 0x6ff7b413a8457ef90f326b5280600a4473fef49b5b1dcdfcd7f42ca7aa59c69,
        s: 0x23a9747ed71abc5cb956c0df44ee8638b65b3e9407deade65de62247b8fd77
    }
}

fn guardian() -> Signature {
    Signature {
        pubkey: 0x759ca09377679ecd535a81e83039658bf40959283187c654c5416f439403cf5,
        r: 0x1734f5510c8b862984461d2221411d12a706140bae629feac0aad35f4d91a19,
        s: 0x75c904c1969e5b2bf2e9fedb32d6180f06288d81a6a2164d876ea4be2ae7520
    }
}

fn guardian_backup() -> Signature {
    Signature {
        pubkey: 0x411494b501a98abd8262b0da1351e17899a0c4ef23dd2f96fec5ba847310b20,
        r: 0x1e03a158a4142532f903caa32697a74fcf5c05b762bb866cec28670d0a53f9a,
        s: 0x74be76fe620a42899bc34afce7b31a058408b23c250805054fca4de4e0121ca
    }
}
