#!/usr/bin/env python
import sys
sys.path.append('test')

from utils.Signer import Signer
from utils.utilities import str_to_felt

signer = Signer(1)
guardian = Signer(2)
guardian_backup = Signer(3)

new_signer = Signer(4)
new_guardian = Signer(5)
new_guardian_backup = Signer(6)

wrong_signer = Signer(7)
wrong_guardian = Signer(8)

ESCAPE_SECURITY_PERIOD = 24*7*60*60

VERSION = str_to_felt('0.2.4')
NAME = str_to_felt('ArgentAccount')

IACCOUNT_ID = 0xa66bd575
IACCOUNT_ID_OLD = 0x3943f10f

ESCAPE_TYPE_GUARDIAN = 1
ESCAPE_TYPE_SIGNER = 2

hash = 1283225199545181604979924458180358646374088657288769423115053097913173815464
invalid_hash = 1283225199545181604979924458180358646374088657288769423115053097913173811111

signer_r, signer_s = signer.sign(hash)
guardian_r, guardian_s = guardian.sign(hash)
guardian_backup_r, guardian_backup_s = guardian_backup.sign(hash)

print(f"""

const message_hash: felt = 0x{hash:x};

const signer_pubkey: felt = 0x{signer.public_key:x};
const signer_r: felt = 0x{signer_r:x};
const signer_s: felt = 0x{signer_s:x};

const guardian_pubkey: felt = 0x{guardian.public_key:x};
const guardian_r: felt = 0x{guardian_r:x};
const guardian_s: felt = 0x{guardian_s:x};

const guardian_backup_pubkey: felt = 0x{guardian_backup.public_key:x};
const guardian_backup_r: felt = 0x{guardian_backup_r:x};
const guardian_backup_s: felt = 0x{guardian_backup_s:x};

""");
