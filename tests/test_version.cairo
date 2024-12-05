use argent::account::interface::Version;

#[test]
fn test_version_lt_simple_version_incr() {
    let v1 = Version { major: 1, minor: 1, patch: 1 };
    let v2 = Version { major: 2, minor: 0, patch: 0 };
    assert!(v1 < v2);

    let v1 = Version { major: 1, minor: 1, patch: 1 };
    let v2 = Version { major: 1, minor: 2, patch: 0 };
    assert!(v1 < v2);

    let v1 = Version { major: 1, minor: 1, patch: 1 };
    let v2 = Version { major: 1, minor: 1, patch: 2 };
    assert!(v1 < v2);
}

#[test]
fn test_version_lt_decrement() {
    let v1 = Version { major: 0, minor: 1, patch: 1 };
    let v2 = Version { major: 1, minor: 0, patch: 0 };
    assert!(v1 < v2);

    let v1 = Version { major: 1, minor: 0, patch: 1 };
    let v2 = Version { major: 1, minor: 1, patch: 0 };
    assert!(v1 < v2);
}
