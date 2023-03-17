use array::ArrayTrait;
use gas::withdraw_gas_all;

#[inline(always)]
fn fetch_gas(){
match withdraw_gas_all(get_builtin_costs()) {
            Option::Some(_) => {},
            Option::None(_) => {
                let mut err_data = ArrayTrait::new();
                err_data.append('Out of gas');
                panic(err_data)
            }
        }
}