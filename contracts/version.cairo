use serde::Serde;

struct Version {
    major: u8,
    minor: u8,
    patch: u8,
}

impl VersionSerde of Serde::<Version> {
    fn serialize(ref serialized: Array<felt252>, input: Version) {
        Serde::serialize(ref serialized, input.major);
        Serde::serialize(ref serialized, input.minor);
        Serde::serialize(ref serialized, input.patch);
    }
    fn deserialize(ref serialized: Span<felt252>) -> Option<Version> {
        Option::Some(
            Version {
                major: Serde::deserialize(ref serialized)?,
                minor: Serde::deserialize(ref serialized)?,
                patch: Serde::deserialize(ref serialized)?,
            }
        )
    }
}
