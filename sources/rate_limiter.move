module suilend::rate_limiter {
    public struct RateLimiter has copy, drop, store {
        config: RateLimiterConfig,
        prev_qty: suilend::decimal::Decimal,
        window_start: u64,
        cur_qty: suilend::decimal::Decimal,
    }
    
    public struct RateLimiterConfig has copy, drop, store {
        window_duration: u64,
        max_outflow: u64,
    }
    
    fun current_outflow(arg0: &RateLimiter, arg1: u64) : suilend::decimal::Decimal {
        suilend::decimal::add(suilend::decimal::mul(arg0.prev_qty, suilend::decimal::div(suilend::decimal::sub(suilend::decimal::from(arg0.config.window_duration), suilend::decimal::from(arg1 - arg0.window_start + 1)), suilend::decimal::from(arg0.config.window_duration))), arg0.cur_qty)
    }
    
    public fun new(arg0: RateLimiterConfig, arg1: u64) : RateLimiter {
        RateLimiter{
            config       : arg0, 
            prev_qty     : suilend::decimal::from(0), 
            window_start : arg1, 
            cur_qty      : suilend::decimal::from(0),
        }
    }
    
    public fun new_config(arg0: u64, arg1: u64) : RateLimiterConfig {
        assert!(arg0 > 0, 0);
        RateLimiterConfig{
            window_duration : arg0, 
            max_outflow     : arg1,
        }
    }
    
    public fun process_qty(arg0: &mut RateLimiter, arg1: u64, arg2: suilend::decimal::Decimal) {
        update_internal(arg0, arg1);
        arg0.cur_qty = suilend::decimal::add(arg0.cur_qty, arg2);
        assert!(suilend::decimal::le(current_outflow(arg0, arg1), suilend::decimal::from(arg0.config.max_outflow)), 2);
    }
    
    public fun remaining_outflow(arg0: &mut RateLimiter, arg1: u64) : suilend::decimal::Decimal {
        update_internal(arg0, arg1);
        suilend::decimal::saturating_sub(suilend::decimal::from(arg0.config.max_outflow), current_outflow(arg0, arg1))
    }
    
    fun update_internal(arg0: &mut RateLimiter, arg1: u64) {
        assert!(arg1 >= arg0.window_start, 1);
        if (arg1 < arg0.window_start + arg0.config.window_duration) {
            return
        };
        if (arg1 < arg0.window_start + 2 * arg0.config.window_duration) {
            arg0.prev_qty = arg0.cur_qty;
            arg0.window_start = arg0.window_start + arg0.config.window_duration;
            arg0.cur_qty = suilend::decimal::from(0);
        } else {
            arg0.prev_qty = suilend::decimal::from(0);
            arg0.window_start = arg1;
            arg0.cur_qty = suilend::decimal::from(0);
        };
    }
    
    // decompiled from Move bytecode v6
}

