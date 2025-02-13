    public(package) fun update_reserve_config<T0>(reserve: &mut Reserve<T0>, reserve_config: ReserveConfig) {
        reserve_config::destroy(cell::set<ReserveConfig>(&mut reserve.config, reserve_config));
    }
    
    public fun usd_to_token_amount_lower_bound<T0>(reserve: &Reserve<T0>, usd: Decimal) : Decimal {
        decimal::div(decimal::mul(decimal::from(0x2::math::pow(10, reserve.mint_decimals)), usd), price_upper_bound<T0>(reserve))
    }
    
    public fun usd_to_token_amount_upper_bound<T0>(reserve: &Reserve<T0>, usd: Decimal) : Decimal {
        decimal::div(decimal::mul(decimal::from(0x2::math::pow(10, reserve.mint_decimals)), usd), price_lower_bound<T0>(reserve))
    }
    
    public(package) fun withdraw_ctokens<T0, T1>(reserve: &mut Reserve<T0>, ctoken_amount: u64) : balance::Balance<CToken<T0, T1>> {
        log_reserve_data<T0>(reserve);
        let key = BalanceKey{dummy_field: false};
        balance::split<CToken<T0, T1>>(&mut dynamic_field::borrow_mut<BalanceKey, Balances<T0, T1>>(&mut reserve.id, key).deposited_ctokens, ctoken_amount)
    }