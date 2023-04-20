#[derive(Serde, Drop)]
struct Version {
    major: u8,
    minor: u8,
    patch: u8,
}
