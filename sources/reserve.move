module suilend::reserve {

    //==============================================================================================
    // Dependencies  
    //==============================================================================================

    use std::type_name::{Self, TypeName};
    use sui::balance::{Self, Balance};
    use sui::dynamic_field;
    use sui::clock::{Self, Clock};
    use suilend::cell::{Self, Cell};
    use suilend::reserve_config::{Self, ReserveConfig};
    use suilend::decimal::{Self, Decimal};
    use suilend::liquidity_mining::{Self, PoolRewardManager};

    //==============================================================================================
    // Struct  
    //==============================================================================================

    public struct Reserve<phantom T0> has store, key {
        id: UID,
        lending_market_id: ID,
        array_index: u64,
        coin_type: TypeName,
        config: Cell<ReserveConfig>,
        mint_decimals: u8,
        price_identifier: pyth::price_identifier::PriceIdentifier,
        price: Decimal,
        smoothed_price: Decimal,
        price_last_update_timestamp_s: u64,
        available_amount: u64,
        ctoken_supply: u64,
        borrowed_amount: Decimal,
        cumulative_borrow_rate: Decimal,
        interest_last_update_timestamp_s: u64,
        unclaimed_spread_fees: Decimal,
        attributed_borrow_value: Decimal,
        deposits_pool_reward_manager: PoolRewardManager,
        borrows_pool_reward_manager: PoolRewardManager,
    }
    
    public struct CToken<phantom T0, phantom T1> has drop {
        dummy_field: bool,
    }
    
    public struct BalanceKey has copy, drop, store {
        dummy_field: bool,
    }
    
    public struct Balances<phantom T0, phantom T1> has store {
        available_amount: balance::Balance<T1>,
        ctoken_supply: balance::Supply<CToken<T0, T1>>,
        fees: balance::Balance<T1>,
        ctoken_fees: balance::Balance<CToken<T0, T1>>,
        deposited_ctokens: balance::Balance<CToken<T0, T1>>,
    }

    //==============================================================================================
    // Events  
    //==============================================================================================
    
    public struct InterestUpdateEvent has copy, drop {
        lending_market_id: address,
        coin_type: TypeName,
        reserve_id: address,
        cumulative_borrow_rate: Decimal,
        available_amount: u64,
        borrowed_amount: Decimal,
        unclaimed_spread_fees: Decimal,
        ctoken_supply: u64,
        borrow_interest_paid: Decimal,
        spread_fee: Decimal,
        supply_interest_earned: Decimal,
        borrow_interest_paid_usd_estimate: Decimal,
        protocol_fee_usd_estimate: Decimal,
        supply_interest_earned_usd_estimate: Decimal,
    }
    
    public struct ReserveAssetDataEvent has copy, drop {
        lending_market_id: address,
        coin_type: TypeName,
        reserve_id: address,
        available_amount: Decimal,
        supply_amount: Decimal,
        borrowed_amount: Decimal,
        available_amount_usd_estimate: Decimal,
        supply_amount_usd_estimate: Decimal,
        borrowed_amount_usd_estimate: Decimal,
        borrow_apr: Decimal,
        supply_apr: Decimal,
        ctoken_supply: u64,
        cumulative_borrow_rate: Decimal,
        price: Decimal,
        smoothed_price: Decimal,
        price_last_update_timestamp_s: u64,
    }

    //==============================================================================================
    // Core Functions 
    //==============================================================================================
    
    public(package) fun borrow_liquidity<T0, T1>(reserve: &mut Reserve<T0>, amount: u64) : (balance::Balance<T1>, u64) {
        let borrow_fee = calculate_borrow_fee<T0>(reserve, amount);
        let borrow_amount_with_fee = amount + borrow_fee;
        reserve.available_amount = reserve.available_amount - borrow_amount_with_fee;
        reserve.borrowed_amount = decimal::add(reserve.borrowed_amount, decimal::from(borrow_amount_with_fee));
        assert!(decimal::le(reserve.borrowed_amount, decimal::from(reserve_config::borrow_limit(config<T0>(reserve)))), 3);
        assert!(decimal::le(market_value_upper_bound<T0>(reserve, reserve.borrowed_amount), decimal::from(reserve_config::borrow_limit_usd(config<T0>(reserve)))), 3);
        assert!(reserve.available_amount >= 100 && reserve.ctoken_supply >= 100, 5);
        log_reserve_data<T0>(reserve);
        let key = BalanceKey{dummy_field: false};
        let balances = dynamic_field::borrow_mut<BalanceKey, Balances<T0, T1>>(&mut reserve.id, key);
        let mut borrow_balance = balance::split<T1>(&mut balances.available_amount, borrow_amount_with_fee);
        balance::join<T1>(&mut balances.fees, balance::split<T1>(&mut borrow_balance, borrow_fee));
        (borrow_balance, borrow_amount_with_fee)
    }
    
    public(package) fun claim_fees<T0, T1>(reserve: &mut Reserve<T0>) : (balance::Balance<CToken<T0, T1>>, balance::Balance<T1>) {
        let key = BalanceKey{dummy_field: false};
        let balances = dynamic_field::borrow_mut<BalanceKey, Balances<T0, T1>>(&mut reserve.id, key);
        let mut balance_T1 = balance::withdraw_all<T1>(&mut balances.fees);
        if (reserve.available_amount >= 100) {
            let fees = balance::split<T1>(
                &mut balances.available_amount, 
                decimal::floor(decimal::min(reserve.unclaimed_spread_fees, decimal::from(reserve.available_amount - 100)))
            );
            reserve.unclaimed_spread_fees = decimal::sub(reserve.unclaimed_spread_fees, decimal::from(balance::value<T1>(&fees)));
            reserve.available_amount = reserve.available_amount - balance::value<T1>(&fees);
            balance::join<T1>(&mut balance_T1, fees);
        };
        (balance::withdraw_all<CToken<T0, T1>>(&mut balances.ctoken_fees), balance_T1)
    }
    
    public(package) fun compound_interest<T0>(reserve: &mut Reserve<T0>, clock: &clock::Clock) {
        let time_s = clock::timestamp_ms(clock) / 1000;
        let interval = time_s - reserve.interest_last_update_timestamp_s;
        if (interval == 0) {
            return
        };
        let interest_factor = decimal::pow(
            decimal::add(
                decimal::from(1), 
                decimal::div(
                    reserve_config::calculate_apr(
                        config<T0>(reserve), 
                        calculate_utilization_rate<T0>(reserve)
                    ), 
                    decimal::from(31536000)
                )
            ), 
            interval
        );
        reserve.cumulative_borrow_rate = decimal::mul(reserve.cumulative_borrow_rate, interest_factor);
        let interest = decimal::mul(reserve.borrowed_amount, decimal::sub(interest_factor, decimal::from(1)));
        let unclaimed_spread_fees = decimal::mul(interest, reserve_config::spread_fee(config<T0>(reserve)));
        reserve.unclaimed_spread_fees = decimal::add(reserve.unclaimed_spread_fees, unclaimed_spread_fees);
        reserve.borrowed_amount = decimal::add(reserve.borrowed_amount, interest);
        reserve.interest_last_update_timestamp_s = time_s;
        let event = InterestUpdateEvent{
            lending_market_id                   : 0x2::object::id_to_address(&reserve.lending_market_id), 
            coin_type                           : reserve.coin_type, 
            reserve_id                          : 0x2::object::uid_to_address(&reserve.id), 
            cumulative_borrow_rate              : reserve.cumulative_borrow_rate, 
            available_amount                    : reserve.available_amount, 
            borrowed_amount                     : reserve.borrowed_amount, 
            unclaimed_spread_fees               : reserve.unclaimed_spread_fees, 
            ctoken_supply                       : reserve.ctoken_supply, 
            borrow_interest_paid                : interest, 
            spread_fee                          : unclaimed_spread_fees, 
            supply_interest_earned              : decimal::sub(interest, unclaimed_spread_fees), 
            borrow_interest_paid_usd_estimate   : market_value<T0>(reserve, interest), 
            protocol_fee_usd_estimate           : market_value<T0>(reserve, unclaimed_spread_fees), 
            supply_interest_earned_usd_estimate : market_value<T0>(reserve, decimal::sub(interest, unclaimed_spread_fees)),
        };
        0x2::event::emit<InterestUpdateEvent>(event);
    }
    
    public(package) fun create_reserve<T0, T1>(
        lending_market_id: ID, 
        reserve_config: ReserveConfig, 
        array_index: u64, 
        coin_metadata: &0x2::coin::CoinMetadata<T1>, 
        pyth_price_info_obj: &pyth::price_info::PriceInfoObject, 
        clock: &clock::Clock, 
        ctx: &mut 0x2::tx_context::TxContext
    ) : Reserve<T0> {
        let (option_price, ema_price, price_identifier) = suilend::oracles::get_pyth_price_and_identifier(pyth_price_info_obj, clock);
        let mut price = option_price;
        assert!(0x1::option::is_some<Decimal>(&price), 4);
        let mut reserve = Reserve<T0>{
            id                               : 0x2::object::new(ctx), 
            lending_market_id                , 
            array_index                      , 
            coin_type                        : type_name::get<T1>(), 
            config                           : cell::new<ReserveConfig>(reserve_config), 
            mint_decimals                    : 0x2::coin::get_decimals<T1>(coin_metadata), 
            price_identifier                 : price_identifier, 
            price                            : 0x1::option::extract<Decimal>(&mut price), 
            smoothed_price                   : ema_price, 
            price_last_update_timestamp_s    : clock::timestamp_ms(clock) / 1000, 
            available_amount                 : 0, 
            ctoken_supply                    : 0, 
            borrowed_amount                  : decimal::from(0), 
            cumulative_borrow_rate           : decimal::from(1), 
            interest_last_update_timestamp_s : clock::timestamp_ms(clock) / 1000, 
            unclaimed_spread_fees            : decimal::from(0), 
            attributed_borrow_value          : decimal::from(0), 
            deposits_pool_reward_manager     : liquidity_mining::new_pool_reward_manager(ctx), 
            borrows_pool_reward_manager      : liquidity_mining::new_pool_reward_manager(ctx),
        };
        let key = BalanceKey{dummy_field: false};
        let ctoken = CToken<T0, T1>{dummy_field: false};
        let balances = Balances<T0, T1>{
            available_amount  : balance::zero<T1>(), 
            ctoken_supply     : balance::create_supply<CToken<T0, T1>>(ctoken), 
            fees              : balance::zero<T1>(), 
            ctoken_fees       : balance::zero<CToken<T0, T1>>(), 
            deposited_ctokens : balance::zero<CToken<T0, T1>>(),
        };
        dynamic_field::add<BalanceKey, Balances<T0, T1>>(&mut reserve.id, key, balances);
        reserve
    }
    
    public(package) fun deduct_liquidation_fee<T0, T1>(reserve: &mut Reserve<T0>, ctoken_balance: &mut balance::Balance<CToken<T0, T1>>) : (u64, u64) {
        let liquidation_bonus_bps = reserve_config::liquidation_bonus(config<T0>(reserve));
        let protocol_liquidation_fee_bps = reserve_config::protocol_liquidation_fee(config<T0>(reserve));
        let liquidation_fee = decimal::ceil(
            decimal::mul(
                decimal::div(
                    protocol_liquidation_fee_bps, 
                    decimal::add(
                        decimal::add(
                            decimal::from(1), 
                            liquidation_bonus_bps), 
                        protocol_liquidation_fee_bps)), 
                decimal::from(balance::value<CToken<T0, T1>>(ctoken_balance))));
        let key = BalanceKey{dummy_field: false};
        balance::join<CToken<T0, T1>>(
            &mut dynamic_field::borrow_mut<BalanceKey, Balances<T0, T1>>(&mut reserve.id, key).ctoken_fees, 
            balance::split<CToken<T0, T1>>(ctoken_balance, liquidation_fee)
        );
        (
            liquidation_fee, 
            decimal::ceil(
            decimal::mul(
                decimal::div(
                    liquidation_bonus_bps, 
                    decimal::add(
                        decimal::add(
                            decimal::from(1), 
                            liquidation_bonus_bps
                        ), 
                        protocol_liquidation_fee_bps
                    )
                ), 
            decimal::from(balance::value<CToken<T0, T1>>(ctoken_balance)))
            )
        )
    }
    
    public(package) fun deposit_ctokens<T0, T1>(reserve: &mut Reserve<T0>, ctoken_balance: balance::Balance<CToken<T0, T1>>) {
        log_reserve_data<T0>(reserve);
        let key = BalanceKey{dummy_field: false};
        balance::join<CToken<T0, T1>>(
            &mut dynamic_field::borrow_mut<BalanceKey, Balances<T0, T1>>(&mut reserve.id, key).deposited_ctokens, 
            ctoken_balance
        );
    }
    
    public(package) fun deposit_liquidity_and_mint_ctokens<T0, T1>(reserve: &mut Reserve<T0>, balance_T1: balance::Balance<T1>) : balance::Balance<CToken<T0, T1>> {
        let ctoken_amount = decimal::floor(
            decimal::div(
                decimal::from(balance::value<T1>(&balance_T1)), 
                ctoken_ratio<T0>(reserve)
            )
        );
        reserve.available_amount = reserve.available_amount + balance::value<T1>(&balance_T1);
        reserve.ctoken_supply = reserve.ctoken_supply + ctoken_amount;
        let total_supply = total_supply<T0>(reserve);
        assert!(decimal::le(total_supply, decimal::from(reserve_config::deposit_limit(config<T0>(reserve)))), 2);
        assert!(
            decimal::le(
                market_value_upper_bound<T0>(reserve, total_supply), 
                decimal::from(reserve_config::deposit_limit_usd(config<T0>(reserve)))
            ), 
            2
        );
        log_reserve_data<T0>(reserve);
        let key = BalanceKey{dummy_field: false};
        let balances = dynamic_field::borrow_mut<BalanceKey, Balances<T0, T1>>(&mut reserve.id, key);
        balance::join<T1>(&mut balances.available_amount, balance_T1);
        balance::increase_supply<CToken<T0, T1>>(&mut balances.ctoken_supply, ctoken_amount)
    }
    
    public fun deposits_pool_reward_manager<T0>(reserve: &Reserve<T0>) : &PoolRewardManager {
        &reserve.deposits_pool_reward_manager
    }
    
    public(package) fun deposits_pool_reward_manager_mut<T0>(reserve: &mut Reserve<T0>) : &mut PoolRewardManager {
        &mut reserve.deposits_pool_reward_manager
    }
    
    public(package) fun forgive_debt<T0>(reserve: &mut Reserve<T0>, debt_amount: Decimal) {
        reserve.borrowed_amount = decimal::saturating_sub(reserve.borrowed_amount, debt_amount);
        log_reserve_data<T0>(reserve);
    }
    
    public(package) fun redeem_ctokens<T0, T1>(reserve: &mut Reserve<T0>, ctoken_balance: balance::Balance<CToken<T0, T1>>) : balance::Balance<T1> {
        let amount_to_redeem = decimal::floor(
            decimal::mul(
                decimal::from(balance::value<CToken<T0, T1>>(&ctoken_balance)), 
                ctoken_ratio<T0>(reserve)
            )
        );
        reserve.available_amount = reserve.available_amount - amount_to_redeem;
        reserve.ctoken_supply = reserve.ctoken_supply - balance::value<CToken<T0, T1>>(&ctoken_balance);
        assert!(reserve.available_amount >= 100 && reserve.ctoken_supply >= 100, 5);
        log_reserve_data<T0>(reserve);
        let key = BalanceKey{dummy_field: false};
        let balances = dynamic_field::borrow_mut<BalanceKey, Balances<T0, T1>>(&mut reserve.id, key);
        balance::decrease_supply<CToken<T0, T1>>(&mut balances.ctoken_supply, ctoken_balance);
        balance::split<T1>(&mut balances.available_amount, amount_to_redeem)
    }
    
    public(package) fun repay_liquidity<T0, T1>(reserve: &mut Reserve<T0>, balance_T1: balance::Balance<T1>, amount: Decimal) {
        assert!(balance::value<T1>(&balance_T1) == decimal::ceil(amount), 6);
        reserve.available_amount = reserve.available_amount + balance::value<T1>(&balance_T1);
        reserve.borrowed_amount = decimal::saturating_sub(reserve.borrowed_amount, amount);
        log_reserve_data<T0>(reserve);
        let key = BalanceKey{dummy_field: false};
        balance::join<T1>(
            &mut dynamic_field::borrow_mut<BalanceKey, Balances<T0, T1>>(&mut reserve.id, key).available_amount, 
            balance_T1
        );
    }
    
    public(package) fun update_price<T0>(reserve: &mut Reserve<T0>, clock: &clock::Clock, pyth_price_info_obj: &pyth::price_info::PriceInfoObject) {
        let (option_price, ema_price, price_identifier) = suilend::oracles::get_pyth_price_and_identifier(pyth_price_info_obj, clock);
        let mut price = option_price;
        assert!(price_identifier == reserve.price_identifier, 1);
        assert!(0x1::option::is_some<Decimal>(&price), 4);
        reserve.price = 0x1::option::extract<Decimal>(&mut price);
        reserve.smoothed_price = ema_price;
        reserve.price_last_update_timestamp_s = clock::timestamp_ms(clock) / 1000;
    }
    
    public(package) fun update_reserve_config<T0>(reserve: &mut Reserve<T0>, reserve_config: ReserveConfig) {
        reserve_config::destroy(cell::set<ReserveConfig>(&mut reserve.config, reserve_config));
    }
    
    public(package) fun withdraw_ctokens<T0, T1>(reserve: &mut Reserve<T0>, ctoken_amount: u64) : balance::Balance<CToken<T0, T1>> {
        log_reserve_data<T0>(reserve);
        let key = BalanceKey{dummy_field: false};
        balance::split<CToken<T0, T1>>(
            &mut dynamic_field::borrow_mut<BalanceKey, Balances<T0, T1>>(&mut reserve.id, key).deposited_ctokens, 
            ctoken_amount
        )
    }

    //==============================================================================================
    // Getter Functions 
    //==============================================================================================
    
    public fun array_index<T0>(reserve: &Reserve<T0>) : u64 {
        reserve.array_index
    }
    
    public fun available_amount<T0>(reserve: &Reserve<T0>) : u64 {
        reserve.available_amount
    }

    public fun borrowed_amount<T0>(reserve: &Reserve<T0>) : Decimal {
        reserve.borrowed_amount
    }
    
    public fun borrows_pool_reward_manager<T0>(reserve: &Reserve<T0>) : &PoolRewardManager {
        &reserve.borrows_pool_reward_manager
    }
    
    public(package) fun borrows_pool_reward_manager_mut<T0>(reserve: &mut Reserve<T0>) : &mut PoolRewardManager {
        &mut reserve.borrows_pool_reward_manager
    }

    public fun coin_type<T0>(reserve: &Reserve<T0>) : TypeName {
        reserve.coin_type
    }

    public fun config<T0>(reserve: &Reserve<T0>) : &ReserveConfig {
        cell::get<ReserveConfig>(&reserve.config)
    }
    public fun ctoken_market_value<T0>(reserve: &Reserve<T0>, arg1: u64) : Decimal {
        market_value<T0>(reserve, decimal::mul(decimal::from(arg1), ctoken_ratio<T0>(reserve)))
    }
    
    public fun ctoken_market_value_lower_bound<T0>(reserve: &Reserve<T0>, arg1: u64) : Decimal {
        market_value_lower_bound<T0>(reserve, decimal::mul(decimal::from(arg1), ctoken_ratio<T0>(reserve)))
    }
    
    public fun ctoken_market_value_upper_bound<T0>(reserve: &Reserve<T0>, arg1: u64) : Decimal {
        market_value_upper_bound<T0>(reserve, decimal::mul(decimal::from(arg1), ctoken_ratio<T0>(reserve)))
    }
    
    public fun ctoken_ratio<T0>(reserve: &Reserve<T0>) : Decimal {
        if (reserve.ctoken_supply == 0) {
            decimal::from(1)
        } else {
            decimal::div(total_supply<T0>(reserve), decimal::from(reserve.ctoken_supply))
        }
    }
    
    public fun cumulative_borrow_rate<T0>(reserve: &Reserve<T0>) : Decimal {
        reserve.cumulative_borrow_rate
    }

    public fun market_value<T0>(reserve: &Reserve<T0>, value: Decimal) : Decimal {
        decimal::div(decimal::mul(price<T0>(reserve), value), decimal::from(0x2::math::pow(10, reserve.mint_decimals)))
    }
    
    public fun market_value_lower_bound<T0>(reserve: &Reserve<T0>, value: Decimal) : Decimal {
        decimal::div(
            decimal::mul(
                price_lower_bound<T0>(reserve),
                 value
            ), 
            decimal::from(0x2::math::pow(10, reserve.mint_decimals))
        )
    }
    
    public fun market_value_upper_bound<T0>(reserve: &Reserve<T0>, value: Decimal) : Decimal {
        decimal::div(
            decimal::mul(
                price_upper_bound<T0>(reserve), 
                value
            ), 
            decimal::from(0x2::math::pow(10, reserve.mint_decimals))
        )
    }
    
    public fun max_borrow_amount<T0>(reserve: &Reserve<T0>) : u64 {
        decimal::floor(
            decimal::min(
                decimal::saturating_sub(
                    decimal::from(reserve.available_amount), 
                    decimal::from(100)
                ), 
                decimal::min(
                    decimal::saturating_sub(
                        decimal::from(reserve_config::borrow_limit(config<T0>(reserve))), 
                        reserve.borrowed_amount
                    ), 
                    usd_to_token_amount_lower_bound<T0>(
                        reserve, 
                        decimal::saturating_sub(
                            decimal::from(reserve_config::borrow_limit_usd(config<T0>(reserve))), 
                            market_value_upper_bound<T0>(reserve, reserve.borrowed_amount)
                        )
                    )
                )
            )
        )
    }
    
    public fun max_redeem_amount<T0>(reserve: &Reserve<T0>) : u64 {
        decimal::floor(
            decimal::div(
                decimal::sub(
                    decimal::from(reserve.available_amount), 
                    decimal::from(100)
                ), 
                ctoken_ratio<T0>(reserve)
            )
        )
    }
    
    public fun price<T0>(reserve: &Reserve<T0>) : Decimal {
        reserve.price
    }
    
    public fun price_lower_bound<T0>(reserve: &Reserve<T0>) : Decimal {
        decimal::min(reserve.price, reserve.smoothed_price)
    }
    
    public fun price_upper_bound<T0>(reserve: &Reserve<T0>) : Decimal {
        decimal::max(reserve.price, reserve.smoothed_price)
    }
    
    public fun total_supply<T0>(reserve: &Reserve<T0>) : Decimal {
        decimal::sub(
            decimal::add(
                decimal::from(reserve.available_amount), 
                reserve.borrowed_amount
            ),
            reserve.unclaimed_spread_fees
        )
    }

    public fun usd_to_token_amount_lower_bound<T0>(reserve: &Reserve<T0>, usd: Decimal) : Decimal {
        decimal::div(decimal::mul(decimal::from(0x2::math::pow(10, reserve.mint_decimals)), usd), price_upper_bound<T0>(reserve))
    }
    
    public fun usd_to_token_amount_upper_bound<T0>(reserve: &Reserve<T0>, usd: Decimal) : Decimal {
        decimal::div(decimal::mul(decimal::from(0x2::math::pow(10, reserve.mint_decimals)), usd), price_lower_bound<T0>(reserve))
    }

    //==============================================================================================
    // Helper Functions 
    //==============================================================================================

    public fun assert_price_is_fresh<T0>(reserve: &Reserve<T0>, clock: &clock::Clock) {
        assert!(clock::timestamp_ms(clock) / 1000 - reserve.price_last_update_timestamp_s <= 0, 0);
    }
    
    public fun calculate_borrow_fee<T0>(reserve: &Reserve<T0>, arg1: u64) : u64 {
        decimal::ceil(decimal::mul(decimal::from(arg1), reserve_config::borrow_fee(config<T0>(reserve))))
    }
    
    public fun calculate_utilization_rate<T0>(reserve: &Reserve<T0>) : Decimal {
        let v0 = decimal::add(decimal::from(reserve.available_amount), reserve.borrowed_amount);
        if (decimal::eq(v0, decimal::from(0))) {
            decimal::from(0)
        } else {
            decimal::div(reserve.borrowed_amount, v0)
        }
    }

    fun log_reserve_data<T0>(reserve: &Reserve<T0>) {
        let reserve_available_amount = decimal::from(reserve.available_amount);
        let total_supply = total_supply<T0>(reserve);
        let utilization_rate = calculate_utilization_rate<T0>(reserve);
        let borrow_apr = reserve_config::calculate_apr(config<T0>(reserve), utilization_rate);
        let event = ReserveAssetDataEvent{
            lending_market_id             : 0x2::object::id_to_address(&reserve.lending_market_id), 
            coin_type                     : reserve.coin_type, 
            reserve_id                    : 0x2::object::uid_to_address(&reserve.id), 
            available_amount              : reserve_available_amount, 
            supply_amount                 : total_supply, 
            borrowed_amount               : reserve.borrowed_amount, 
            available_amount_usd_estimate : market_value<T0>(reserve, reserve_available_amount), 
            supply_amount_usd_estimate    : market_value<T0>(reserve, total_supply), 
            borrowed_amount_usd_estimate  : market_value<T0>(reserve, reserve.borrowed_amount), 
            borrow_apr                    , 
            supply_apr                    : reserve_config::calculate_supply_apr(config<T0>(reserve), utilization_rate, borrow_apr), 
            ctoken_supply                 : reserve.ctoken_supply, 
            cumulative_borrow_rate        : reserve.cumulative_borrow_rate, 
            price                         : reserve.price, 
            smoothed_price                : reserve.smoothed_price, 
            price_last_update_timestamp_s : reserve.price_last_update_timestamp_s,
        };
        0x2::event::emit<ReserveAssetDataEvent>(event);
    }
    // decompiled from Move bytecode v6
}

