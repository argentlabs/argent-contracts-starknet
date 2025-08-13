use argent::utils::transaction_version::{
    assert_correct_declare_version, assert_correct_deploy_account_version, assert_correct_invoke_version,
};

#[test]
fn test_assert_correct_invoke_version() {
    assert_correct_invoke_version(1);
    assert_correct_invoke_version(0x100000000000000000000000000000000 + 1);
    assert_correct_invoke_version(3);
    assert_correct_invoke_version(0x100000000000000000000000000000000 + 3);
}

#[test]
#[should_panic(expected: ('argent/invalid-tx-version',))]
fn assert_invoke_version_invalid() {
    assert_correct_invoke_version(2);
}

#[test]
fn test_assert_correct_deploy_account_version() {
    assert_correct_deploy_account_version(1);
    assert_correct_deploy_account_version(0x100000000000000000000000000000000 + 1);
    assert_correct_deploy_account_version(3);
    assert_correct_deploy_account_version(0x100000000000000000000000000000000 + 3);
}

#[test]
#[should_panic(expected: ('argent/invalid-deploy-account-v',))]
fn assert_deploy_account_invalid() {
    assert_correct_deploy_account_version(2);
}

#[test]
fn test_assert_correct_declare_version() {
    assert_correct_declare_version(2);
    assert_correct_declare_version(0x100000000000000000000000000000000 + 2);
    assert_correct_declare_version(3);
    assert_correct_declare_version(0x100000000000000000000000000000000 + 3);
}

#[test]
#[should_panic(expected: ('argent/invalid-declare-version',))]
fn assert_declare_version_invalid() {
    assert_correct_declare_version(1);
}

