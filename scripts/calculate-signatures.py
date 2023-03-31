#!/usr/bin/env python
import sys
sys.path.append('test')

from utils.Signer import Signer
from utils.utilities import str_to_felt

owner = Signer(1)
guardian = Signer(2)
guardian_backup = Signer(3)

new_owner = Signer(4)
new_guardian = Signer(5)
new_guardian_backup = Signer(6)

wrong_owner = Signer(7)
wrong_guardian = Signer(8)

ESCAPE_SECURITY_PERIOD = 24*7*60*60

VERSION = str_to_felt('0.2.4')
NAME = str_to_felt('ArgentAccount')

IACCOUNT_ID = 0xa66bd575
IACCOUNT_ID_OLD = 0x3943f10f

ESCAPE_TYPE_GUARDIAN = 1
ESCAPE_TYPE_OWNER = 2

hash = 1283225199545181604979924458180358646374088657288769423115053097913173815464
invalid_hash = 1283225199545181604979924458180358646374088657288769423115053097913173811111

owner_r, owner_s = owner.sign(hash)
guardian_r, guardian_s = guardian.sign(hash)
guardian_backup_r, guardian_backup_s = guardian_backup.sign(hash)
wrong_owner_r, wrong_owner_s = wrong_owner.sign(hash)
wrong_guardian_r, wrong_guardian_s = wrong_guardian.sign(hash)

print(f"""

const message_hash: felt = 0x{hash:x};

const owner_pubkey: felt = 0x{owner.public_key:x};
const owner_r: felt = 0x{owner_r:x};
const owner_s: felt = 0x{owner_s:x};

const guardian_pubkey: felt = 0x{guardian.public_key:x};
const guardian_r: felt = 0x{guardian_r:x};
const guardian_s: felt = 0x{guardian_s:x};

const guardian_backup_pubkey: felt = 0x{guardian_backup.public_key:x};
const guardian_backup_r: felt = 0x{guardian_backup_r:x};
const guardian_backup_s: felt = 0x{guardian_backup_s:x};

const wrong_owner_pubkey: felt = 0x{wrong_owner.public_key:x};
const wrong_owner_r: felt = 0x{wrong_owner_r:x};
const wrong_owner_s: felt = 0x{wrong_owner_s:x};

const wrong_guardian_pubkey: felt = 0x{wrong_guardian.public_key:x};
const wrong_guardian_r: felt = 0x{wrong_guardian_r:x};
const wrong_guardian_s: felt = 0x{wrong_guardian_s:x};

""");
