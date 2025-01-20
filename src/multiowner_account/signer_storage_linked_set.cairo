use argent::signer::signer_signature::{SignerStorageValue, SignerStorageTrait, SignerType};
use argent::utils::linked_set::LinkedSetConfig;
use starknet::storage::StoragePath;

impl SignerStorageValueLinkedSetConfig of LinkedSetConfig<SignerStorageValue> {
    const END_MARKER: SignerStorageValue =
        SignerStorageValue { stored_value: 'end', signer_type: SignerType::Starknet };

    #[inline(always)]
    fn is_valid_item(self: @SignerStorageValue) -> bool {
        *self.stored_value != 0 && *self.stored_value != Self::END_MARKER.stored_value
    }

    #[inline(always)]
    fn hash(self: @SignerStorageValue) -> felt252 {
        (*self).into_guid()
    }

    #[inline(always)]
    fn path_read_value(path: StoragePath<SignerStorageValue>) -> Option<SignerStorageValue> {
        let stored_value = path.stored_value.read();
        if stored_value == 0 || stored_value == Self::END_MARKER.stored_value {
            return Option::None;
        }
        let signer_type = path.signer_type.read();
        Option::Some(SignerStorageValue { stored_value, signer_type })
    }

    #[inline(always)]
    fn path_is_in_set(path: StoragePath<SignerStorageValue>) -> bool {
        // Items in the set point to the next item or the end marker.
        // Items outside the set point to uninitialized storage
        path.stored_value.read() != 0
    }
}
