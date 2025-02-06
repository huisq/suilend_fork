module suilend::oracles {
    public fun get_pyth_price_and_identifier(
        arg0: &pyth::price_info::PriceInfoObject, 
        arg1: &0x2::clock::Clock
    ) : (0x1::option::Option<suilend::decimal::Decimal>, suilend::decimal::Decimal, pyth::price_identifier::PriceIdentifier) 
    {
        let v0 = pyth::price_info::get_price_info_from_price_info_object(arg0);
        let v1 = pyth::price_info::get_price_feed(&v0);
        let v2 = pyth::price_feed::get_price(v1);
        let v3 = pyth::price::get_price(&v2);
        if (pyth::price::get_conf(&v2) * 10 > pyth::i64::get_magnitude_if_positive(&v3)) {
            return (0x1::option::none<suilend::decimal::Decimal>(), parse_price_to_decimal(pyth::price_feed::get_ema_price(v1)), pyth::price_feed::get_price_identifier(v1))
        };
        let v4 = 0x2::clock::timestamp_ms(arg1) / 1000;
        if (v4 > pyth::price::get_timestamp(&v2) && v4 - pyth::price::get_timestamp(&v2) > 60) {
            return (0x1::option::none<suilend::decimal::Decimal>(), parse_price_to_decimal(pyth::price_feed::get_ema_price(v1)), pyth::price_feed::get_price_identifier(v1))
        };
        (0x1::option::some<suilend::decimal::Decimal>(parse_price_to_decimal(v2)), parse_price_to_decimal(pyth::price_feed::get_ema_price(v1)), pyth::price_feed::get_price_identifier(v1))
    }
    
    fun parse_price_to_decimal(arg0: pyth::price::Price) : suilend::decimal::Decimal {
        let v0 = pyth::price::get_price(&arg0);
        let v1 = pyth::price::get_expo(&arg0);
        if (pyth::i64::get_is_negative(&v1)) {
            suilend::decimal::div(
                suilend::decimal::from(pyth::i64::get_magnitude_if_positive(&v0)), 
                suilend::decimal::from(0x2::math::pow(10, (pyth::i64::get_magnitude_if_negative(&v1) as u8)))
            )
        } else {
            suilend::decimal::mul(
                suilend::decimal::from(pyth::i64::get_magnitude_if_positive(&v0)), 
                suilend::decimal::from(0x2::math::pow(10, (pyth::i64::get_magnitude_if_positive(&v1) as u8)))
            )
        }
    }
    
    // decompiled from Move bytecode v6
}

