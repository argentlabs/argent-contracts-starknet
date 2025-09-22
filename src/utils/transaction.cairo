use core::starknet::TxInfo;

pub fn tx_v3_max_fee_and_tip(tx_info: TxInfo) -> (u128, u128) {
    let mut max_fee: u128 = 0;
    let mut max_tip: u128 = 0;
    for bound in tx_info.resource_bounds {
        let max_resource_amount: u128 = (*bound.max_amount).into();
        max_fee += *bound.max_price_per_unit * max_resource_amount;
        if *bound.resource == 'L2_GAS' {
            max_tip += tx_info.tip * max_resource_amount;
        }
    };
    max_fee += max_tip;
    return (max_fee, max_tip);
}
