module suilend::lending_market {

    use std::type_name::{Self, TypeName};
    use sui::clock::{Self, Clock};
    use sui::coin::{Self, Coin};
    use sui::event;
    use sui::balance::{Self};
    use sui::object_table::{Self, ObjectTable};
    use suilend::reserve::{Self, Reserve};
    use suilend::obligation::{Self, Obligation};
    use suilend::rate_limiter::{Self, RateLimiter};
    use suilend::decimal::{Self, Decimal};
    use suilend::liquidity_mining;
    use suilend::reserve_config::{Self};

    public struct LENDING_MARKET has drop {
        dummy_field: bool,
    }
    
    public struct LendingMarket<phantom T0> has store, key {
        id: UID,
        version: u64,
        reserves: vector<Reserve<T0>>,
        obligations: ObjectTable<ID, Obligation<T0>>,
        rate_limiter: RateLimiter,
        fee_receiver: address,
        bad_debt_usd: Decimal,
        bad_debt_limit_usd: Decimal,
    }
    
    public struct LendingMarketOwnerCap<phantom T0> has store, key {
        id: UID,
        lending_market_id: ID,
    }
    
    public struct ObligationOwnerCap<phantom T0> has store, key {
        id: UID,
        obligation_id: ID,
    }
    
    public struct RateLimiterExemption<phantom T0, phantom T1> has drop {
        amount: u64,
    }
    
    public struct MintEvent has copy, drop {
        lending_market_id: address,
        coin_type: TypeName,
        reserve_id: address,
        liquidity_amount: u64,
        ctoken_amount: u64,
    }
    
    public struct RedeemEvent has copy, drop {
        lending_market_id: address,
        coin_type: TypeName,
        reserve_id: address,
        ctoken_amount: u64,
        liquidity_amount: u64,
    }
    
    public struct DepositEvent has copy, drop {
        lending_market_id: address,
        coin_type: TypeName,
        reserve_id: address,
        obligation_id: address,
        ctoken_amount: u64,
    }
    
    public struct WithdrawEvent has copy, drop {
        lending_market_id: address,
        coin_type: TypeName,
        reserve_id: address,
        obligation_id: address,
        ctoken_amount: u64,
    }
    
    public struct BorrowEvent has copy, drop {
        lending_market_id: address,
        coin_type: TypeName,
        reserve_id: address,
        obligation_id: address,
        liquidity_amount: u64,
        origination_fee_amount: u64,
    }
    
    public struct RepayEvent has copy, drop {
        lending_market_id: address,
        coin_type: TypeName,
        reserve_id: address,
        obligation_id: address,
        liquidity_amount: u64,
    }
    
    public struct ForgiveEvent has copy, drop {
        lending_market_id: address,
        coin_type: TypeName,
        reserve_id: address,
        obligation_id: address,
        liquidity_amount: u64,
    }
    
    public struct LiquidateEvent has copy, drop {
        lending_market_id: address,
        repay_reserve_id: address,
        withdraw_reserve_id: address,
        obligation_id: address,
        repay_coin_type: TypeName,
        withdraw_coin_type: TypeName,
        repay_amount: u64,
        withdraw_amount: u64,
        protocol_fee_amount: u64,
        liquidator_bonus_amount: u64,
    }
    
    public struct ClaimRewardEvent has copy, drop {
        lending_market_id: address,
        reserve_id: address,
        obligation_id: address,
        is_deposit_reward: bool,
        pool_reward_id: address,
        coin_type: TypeName,
        liquidity_amount: u64,
    }
    
    public fun borrow<T0, T1>(
        arg0: &mut LendingMarket<T0>, 
        arg1: u64, 
        arg2: &ObligationOwnerCap<T0>, 
        arg3: &Clock, 
        arg4: u64, 
        arg5: &mut TxContext
    ) : Coin<T1> {
        assert!(arg0.version == 3, 1);
        assert!(arg4 > 0, 2);
        let v0 = object_table::borrow_mut<ID, Obligation<T0>>(&mut arg0.obligations, arg2.obligation_id);
        obligation::refresh<T0>(v0, &mut arg0.reserves, arg3);
        let v1 = vector::borrow_mut<Reserve<T0>>(&mut arg0.reserves, arg1);
        assert!(reserve::coin_type<T0>(v1) == type_name::get<T1>(), 3);
        reserve::compound_interest<T0>(v1, arg3);
        reserve::assert_price_is_fresh<T0>(v1, arg3);
        if (arg4 == 18446744073709551615) {
            arg4 = max_borrow_amount<T0>(arg0.rate_limiter, v0, v1, arg3);
        };
        let (v2, v3) = reserve::borrow_liquidity<T0, T1>(v1, arg4);
        let v4 = v2;
        obligation::borrow<T0>(v0, v1, arg3, v3);
        rate_limiter::process_qty(
            &mut arg0.rate_limiter,
            clock::timestamp_ms(arg3) / 1000,
            reserve::market_value_upper_bound<T0>(v1, decimal::from(v3))
        );
        let v5 = BorrowEvent{
            lending_market_id      : object::id_address<LendingMarket<T0>>(arg0), 
            coin_type              : type_name::get<T1>(), 
            reserve_id             : object::id_address<Reserve<T0>>(v1), 
            obligation_id          : object::id_address<Obligation<T0>>(v0), 
            liquidity_amount       : v3, 
            origination_fee_amount : v3 - balance::value<T1>(&v4),
        };
        event::emit<BorrowEvent>(v5);
        coin::from_balance<T1>(v4, arg5)
    }
    
    public fun add_pool_reward<T0, T1>(
        arg0: &LendingMarketOwnerCap<T0>, 
        arg1: &mut LendingMarket<T0>, 
        arg2: u64, 
        arg3: bool, 
        arg4: Coin<T1>, 
        arg5: u64, 
        arg6: u64, 
        arg7: &Clock, 
        arg8: &mut TxContext
    ) {
        assert!(arg1.version == 3, 1);
        let v0 = if (arg3) {
            reserve::deposits_pool_reward_manager_mut<T0>(vector::borrow_mut<Reserve<T0>>(&mut arg1.reserves, arg2))
        } else {
            reserve::borrows_pool_reward_manager_mut<T0>(vector::borrow_mut<Reserve<T0>>(&mut arg1.reserves, arg2))
        };
        liquidity_mining::add_pool_reward<T1>(v0, coin::into_balance<T1>(arg4), arg5, arg6, arg7, arg8);
    }
    
    public fun cancel_pool_reward<T0, T1>(
        arg0: &LendingMarketOwnerCap<T0>, 
        arg1: &mut LendingMarket<T0>, 
        arg2: u64, 
        arg3: bool, 
        arg4: u64, 
        arg5: &Clock, 
        arg6: 
        &mut TxContext
    ) : Coin<T1> {
        assert!(arg1.version == 3, 1);
        let v0 = if (arg3) {
            reserve::deposits_pool_reward_manager_mut<T0>(vector::borrow_mut<Reserve<T0>>(&mut arg1.reserves, arg2))
        } else {
            reserve::borrows_pool_reward_manager_mut<T0>(vector::borrow_mut<Reserve<T0>>(&mut arg1.reserves, arg2))
        };
        coin::from_balance<T1>(liquidity_mining::cancel_pool_reward<T1>(v0, arg4, arg5), arg6)
    }
    
    public fun close_pool_reward<T0, T1>(
        arg0: &LendingMarketOwnerCap<T0>, 
        arg1: &mut LendingMarket<T0>, 
        arg2: u64, 
        arg3: bool, 
        arg4: u64, 
        arg5: &Clock, 
        arg6: &mut TxContext
    ) : Coin<T1> {
        assert!(arg1.version == 3, 1);
        let v0 = if (arg3) {
            reserve::deposits_pool_reward_manager_mut<T0>(vector::borrow_mut<Reserve<T0>>(&mut arg1.reserves, arg2))
        } else {
            reserve::borrows_pool_reward_manager_mut<T0>(vector::borrow_mut<Reserve<T0>>(&mut arg1.reserves, arg2))
        };
        coin::from_balance<T1>(liquidity_mining::close_pool_reward<T1>(v0, arg4, arg5), arg6)
    }
    
    public fun obligation<T0>(arg0: &LendingMarket<T0>, arg1: ID) : &Obligation<T0> {
        0x2::object_table::borrow<ID, Obligation<T0>>(&arg0.obligations, arg1)
    }
    
    public fun claim_rewards<T0, T1>(
        arg0: &mut LendingMarket<T0>, 
        arg1: &ObligationOwnerCap<T0>, 
        arg2: &Clock, 
        arg3: u64, 
        arg4: u64, 
        arg5: bool, 
        arg6: &mut TxContext
    ) : Coin<T1> {
        assert!(arg0.version == 3, 1);
        claim_rewards_by_obligation_id<T0, T1>(arg0, arg1.obligation_id, arg2, arg3, arg4, arg5, false, arg6)
    }
    
    public fun create_obligation<T0>(arg0: &mut LendingMarket<T0>, arg1: &mut TxContext) : ObligationOwnerCap<T0> {
        assert!(arg0.version == 3, 1);
        let v0 = obligation::create_obligation<T0>(object::id<LendingMarket<T0>>(arg0), arg1);
        let v1 = ObligationOwnerCap<T0>{
            id            : 0x2::object::new(arg1), 
            obligation_id : object::id<Obligation<T0>>(&v0),
        };
        0x2::object_table::add<ID, Obligation<T0>>(&mut arg0.obligations, object::id<Obligation<T0>>(&v0), v0);
        v1
    }
    
    public fun forgive<T0, T1>(arg0: &LendingMarketOwnerCap<T0>, arg1: &mut LendingMarket<T0>, arg2: u64, arg3: ID, arg4: &Clock, arg5: u64) {
        assert!(arg1.version == 3, 1);
        let v0 = object_table::borrow_mut<ID, Obligation<T0>>(&mut arg1.obligations, arg3);
        obligation::refresh<T0>(v0, &mut arg1.reserves, arg4);
        let v1 = vector::borrow_mut<Reserve<T0>>(&mut arg1.reserves, arg2);
        assert!(reserve::coin_type<T0>(v1) == type_name::get<T1>(), 3);
        let v2 = obligation::forgive<T0>(v0, v1, arg4, decimal::from(arg5));
        reserve::forgive_debt<T0>(v1, v2);
        let v3 = ForgiveEvent{
            lending_market_id : object::id_address<LendingMarket<T0>>(arg1), 
            coin_type         : type_name::get<T1>(), 
            reserve_id        : object::id_address<Reserve<T0>>(v1), 
            obligation_id     : object::id_address<Obligation<T0>>(v0), 
            liquidity_amount  : decimal::ceil(v2),
        };
        event::emit<ForgiveEvent>(v3);
    }
    
    public fun liquidate<T0, T1, T2>(arg0: &mut LendingMarket<T0>, arg1: ID, arg2: u64, arg3: u64, arg4: &Clock, arg5: &mut Coin<T1>, arg6: &mut TxContext) : (Coin<reserve::CToken<T0, T2>>, RateLimiterExemption<T0, T2>) {
        assert!(arg0.version == 3, 1);
        assert!(coin::value<T1>(arg5) > 0, 2);
        let v0 = object_table::borrow_mut<ID, Obligation<T0>>(&mut arg0.obligations, arg1);
        obligation::refresh<T0>(v0, &mut arg0.reserves, arg4);
        let (v1, v2) = obligation::liquidate<T0>(v0, &mut arg0.reserves, arg2, arg3, arg4, coin::value<T1>(arg5));
        assert!(decimal::gt(v2, decimal::from(0)), 2);
        let v3 = vector::borrow_mut<Reserve<T0>>(&mut arg0.reserves, arg2);
        assert!(reserve::coin_type<T0>(v3) == type_name::get<T1>(), 3);
        reserve::repay_liquidity<T0, T1>(v3, coin::into_balance<T1>(coin::split<T1>(arg5, decimal::ceil(v2), arg6)), v2);
        let v4 = vector::borrow_mut<Reserve<T0>>(&mut arg0.reserves, arg3);
        assert!(reserve::coin_type<T0>(v4) == type_name::get<T2>(), 3);
        let v5 = reserve::withdraw_ctokens<T0, T2>(v4, v1);
        let (v6, v7) = reserve::deduct_liquidation_fee<T0, T2>(v4, &mut v5);
        let v8 = LiquidateEvent{
            lending_market_id       : object::id_address<LendingMarket<T0>>(arg0), 
            repay_reserve_id        : object::id_address<Reserve<T0>>(vector::borrow<Reserve<T0>>(&arg0.reserves, arg2)), 
            withdraw_reserve_id     : object::id_address<Reserve<T0>>(vector::borrow<Reserve<T0>>(&arg0.reserves, arg3)), 
            obligation_id           : object::id_address<Obligation<T0>>(v0), 
            repay_coin_type         : type_name::get<T1>(), 
            withdraw_coin_type      : type_name::get<T2>(), 
            repay_amount            : decimal::ceil(v2), 
            withdraw_amount         : v1, 
            protocol_fee_amount     : v6, 
            liquidator_bonus_amount : v7,
        };
        event::emit<LiquidateEvent>(v8);
        let v9 = RateLimiterExemption<T0, T2>{amount: balance::value<reserve::CToken<T0, T2>>(&v5)};
        (coin::from_balance<reserve::CToken<T0, T2>>(v5, arg6), v9)
    }
    
    fun max_borrow_amount<T0>(arg0: RateLimiter, arg1: &Obligation<T0>, arg2: &Reserve<T0>, arg3: &Clock) : u64 {
        let v0 = 0x2::math::min(0x2::math::min(obligation::max_borrow_amount<T0>(arg1, arg2), reserve::max_borrow_amount<T0>(arg2)), decimal::floor(reserve::usd_to_token_amount_lower_bound<T0>(arg2, decimal::min(rate_limiter::remaining_outflow(&mut arg0, clock::timestamp_ms(arg3) / 1000), decimal::from(1000000000)))));
        let v1 = decimal::floor(decimal::div(decimal::from(v0), decimal::add(decimal::from(1), reserve_config::borrow_fee(reserve::config<T0>(arg2)))));
        let v2 = v1;
        if (v1 + decimal::ceil(decimal::mul(decimal::from(v1), reserve_config::borrow_fee(reserve::config<T0>(arg2)))) > v0 && v1 > 0) {
            v2 = v1 - 1;
        };
        v2
    }
    
    fun max_withdraw_amount<T0>(arg0: RateLimiter, arg1: &Obligation<T0>, arg2: &Reserve<T0>, arg3: &Clock) : u64 {
        0x2::math::min(0x2::math::min(obligation::max_withdraw_amount<T0>(arg1, arg2), decimal::floor(decimal::div(reserve::usd_to_token_amount_lower_bound<T0>(arg2, decimal::min(rate_limiter::remaining_outflow(&mut arg0, clock::timestamp_ms(arg3) / 1000), decimal::from(1000000000))), reserve::ctoken_ratio<T0>(arg2)))), reserve::max_redeem_amount<T0>(arg2))
    }
    
    public fun repay<T0, T1>(arg0: &mut LendingMarket<T0>, arg1: u64, arg2: ID, arg3: &Clock, arg4: &mut Coin<T1>, arg5: &mut TxContext) {
        assert!(arg0.version == 3, 1);
        let v0 = object_table::borrow_mut<ID, Obligation<T0>>(&mut arg0.obligations, arg2);
        let v1 = vector::borrow_mut<Reserve<T0>>(&mut arg0.reserves, arg1);
        assert!(reserve::coin_type<T0>(v1) == type_name::get<T1>(), 3);
        reserve::compound_interest<T0>(v1, arg3);
        let v2 = obligation::repay<T0>(v0, v1, arg3, decimal::from(coin::value<T1>(arg4)));
        reserve::repay_liquidity<T0, T1>(v1, coin::into_balance<T1>(coin::split<T1>(arg4, decimal::ceil(v2), arg5)), v2);
        let v3 = RepayEvent{
            lending_market_id : object::id_address<LendingMarket<T0>>(arg0), 
            coin_type         : type_name::get<T1>(), 
            reserve_id        : object::id_address<Reserve<T0>>(v1), 
            obligation_id     : object::id_address<Obligation<T0>>(v0), 
            liquidity_amount  : decimal::ceil(v2),
        };
        event::emit<RepayEvent>(v3);
    }
    
    fun reserve<T0, T1>(arg0: &LendingMarket<T0>) : &Reserve<T0> {
        vector::borrow<Reserve<T0>>(&arg0.reserves, reserve_array_index<T0, T1>(arg0))
    }
    
    entry fun claim_fees<T0, T1>(arg0: &mut LendingMarket<T0>, arg1: u64, arg2: &mut TxContext) {
        assert!(arg0.version == 3, 1);
        let v0 = vector::borrow_mut<Reserve<T0>>(&mut arg0.reserves, arg1);
        assert!(reserve::coin_type<T0>(v0) == type_name::get<T1>(), 3);
        let (v1, v2) = reserve::claim_fees<T0, T1>(v0);
        0x2::transfer::public_transfer<Coin<reserve::CToken<T0, T1>>>(coin::from_balance<reserve::CToken<T0, T1>>(v1, arg2), arg0.fee_receiver);
        0x2::transfer::public_transfer<Coin<T1>>(coin::from_balance<T1>(v2, arg2), arg0.fee_receiver);
    }
    
    public fun deposit_liquidity_and_mint_ctokens<T0, T1>(arg0: &mut LendingMarket<T0>, arg1: u64, arg2: &Clock, arg3: Coin<T1>, arg4: &mut TxContext) : Coin<reserve::CToken<T0, T1>> {
        assert!(arg0.version == 3, 1);
        assert!(coin::value<T1>(&arg3) > 0, 2);
        let v0 = vector::borrow_mut<Reserve<T0>>(&mut arg0.reserves, arg1);
        assert!(reserve::coin_type<T0>(v0) == type_name::get<T1>(), 3);
        reserve::compound_interest<T0>(v0, arg2);
        let v1 = reserve::deposit_liquidity_and_mint_ctokens<T0, T1>(v0, coin::into_balance<T1>(arg3));
        assert!(balance::value<reserve::CToken<T0, T1>>(&v1) > 0, 2);
        let v2 = MintEvent{
            lending_market_id : object::id_address<LendingMarket<T0>>(arg0), 
            coin_type         : type_name::get<T1>(), 
            reserve_id        : object::id_address<Reserve<T0>>(v0), 
            liquidity_amount  : coin::value<T1>(&arg3), 
            ctoken_amount     : balance::value<reserve::CToken<T0, T1>>(&v1),
        };
        event::emit<MintEvent>(v2);
        coin::from_balance<reserve::CToken<T0, T1>>(v1, arg4)
    }
    
    public fun update_reserve_config<T0, T1>(arg0: &LendingMarketOwnerCap<T0>, arg1: &mut LendingMarket<T0>, arg2: u64, arg3: reserve_config::ReserveConfig) {
        assert!(arg1.version == 3, 1);
        let v0 = vector::borrow_mut<Reserve<T0>>(&mut arg1.reserves, arg2);
        assert!(reserve::coin_type<T0>(v0) == type_name::get<T1>(), 3);
        reserve::update_reserve_config<T0>(v0, arg3);
    }
    
    public fun withdraw_ctokens<T0, T1>(arg0: &mut LendingMarket<T0>, arg1: u64, arg2: &ObligationOwnerCap<T0>, arg3: &Clock, arg4: u64, arg5: &mut TxContext) : Coin<reserve::CToken<T0, T1>> {
        assert!(arg0.version == 3, 1);
        assert!(arg4 > 0, 2);
        let v0 = object_table::borrow_mut<ID, Obligation<T0>>(&mut arg0.obligations, arg2.obligation_id);
        obligation::refresh<T0>(v0, &mut arg0.reserves, arg3);
        let v1 = vector::borrow_mut<Reserve<T0>>(&mut arg0.reserves, arg1);
        assert!(reserve::coin_type<T0>(v1) == type_name::get<T1>(), 3);
        if (arg4 == 18446744073709551615) {
            arg4 = max_withdraw_amount<T0>(arg0.rate_limiter, v0, v1, arg3);
        };
        obligation::withdraw<T0>(v0, v1, arg3, arg4);
        let v2 = WithdrawEvent{
            lending_market_id : object::id_address<LendingMarket<T0>>(arg0), 
            coin_type         : type_name::get<T1>(), 
            reserve_id        : object::id_address<Reserve<T0>>(v1), 
            obligation_id     : object::id_address<Obligation<T0>>(v0), 
            ctoken_amount     : arg4,
        };
        event::emit<WithdrawEvent>(v2);
        coin::from_balance<reserve::CToken<T0, T1>>(reserve::withdraw_ctokens<T0, T1>(v1, arg4), arg5)
    }
    
    public fun add_reserve<T0, T1>(arg0: &LendingMarketOwnerCap<T0>, arg1: &mut LendingMarket<T0>, arg2: &pyth::price_info::PriceInfoObject, arg3: reserve_config::ReserveConfig, arg4: &coin::CoinMetadata<T1>, arg5: &Clock, arg6: &mut TxContext) {
        assert!(arg1.version == 3, 1);
        assert!(reserve_array_index<T0, T1>(arg1) == vector::length<Reserve<T0>>(&arg1.reserves), 4);
        vector::push_back<Reserve<T0>>(&mut arg1.reserves, reserve::create_reserve<T0, T1>(object::id<LendingMarket<T0>>(arg1), arg3, vector::length<Reserve<T0>>(&arg1.reserves), arg4, arg2, arg5, arg6));
    }
    
    public fun claim_rewards_and_deposit<T0, T1>(arg0: &mut LendingMarket<T0>, arg1: ID, arg2: &Clock, arg3: u64, arg4: u64, arg5: bool, arg6: u64, arg7: &mut TxContext) {
        assert!(arg0.version == 3, 1);
        let v0 = claim_rewards_by_obligation_id<T0, T1>(arg0, arg1, arg2, arg3, arg4, arg5, true, arg7);
        if (decimal::gt(obligation::borrowed_amount<T0, T1>(0x2::object_table::borrow<ID, Obligation<T0>>(&arg0.obligations, arg1)), decimal::from(0))) {
            repay<T0, T1>(arg0, arg6, arg1, arg2, &mut v0, arg7);
        };
        let v1 = vector::borrow<Reserve<T0>>(&arg0.reserves, arg6);
        assert!(reserve::coin_type<T0>(v1) == type_name::get<T1>(), 3);
        if (decimal::floor(decimal::div(decimal::from(coin::value<T1>(&v0)), reserve::ctoken_ratio<T0>(v1))) == 0) {
            0x2::transfer::public_transfer<Coin<T1>>(v0, arg0.fee_receiver);
        } else {
            deposit_ctokens_into_obligation_by_id<T0, T1>(arg0, arg6, arg1, arg2, reserve::deposit_liquidity_and_mint_ctokens<T0, T1>(arg0, arg6, arg2, v0, arg7), arg7);
        };
    }
    
    fun claim_rewards_by_obligation_id<T0, T1>(arg0: &mut LendingMarket<T0>, arg1: ID, arg2: &Clock, arg3: u64, arg4: u64, arg5: bool, arg6: bool, arg7: &mut TxContext) : Coin<T1> {
        assert!(arg0.version == 3, 1);
        let v0 = type_name::get<T1>();
        let v1 = 0x1::ascii::string(b"34fe4f3c9e450fed4d0a3c587ed842eec5313c30c3cc3c0841247c49425e246b::suilend_point::SUILEND_POINT");
        assert!(0x1::type_name::borrow_string(&v0) != &v1, 6);
        let v2 = object_table::borrow_mut<ID, Obligation<T0>>(&mut arg0.obligations, arg1);
        let v3 = vector::borrow_mut<Reserve<T0>>(&mut arg0.reserves, arg3);
        reserve::compound_interest<T0>(v3, arg2);
        let v4 = if (arg5) {
            reserve::deposits_pool_reward_manager_mut<T0>(v3)
        } else {
            reserve::borrows_pool_reward_manager_mut<T0>(v3)
        };
        if (arg6) {
            assert!(clock::timestamp_ms(arg2) >= liquidity_mining::end_time_ms(0x1::option::borrow<liquidity_mining::PoolReward>(liquidity_mining::pool_reward(v4, arg4))), 5);
        };
        let v5 = coin::from_balance<T1>(obligation::claim_rewards<T0, T1>(v2, v4, arg2, arg4), arg7);
        let v6 = liquidity_mining::pool_reward_id(v4, arg4);
        let v7 = ClaimRewardEvent{
            lending_market_id : object::id_address<LendingMarket<T0>>(arg0), 
            reserve_id        : object::id_address<Reserve<T0>>(v3), 
            obligation_id     : object::id_address<Obligation<T0>>(v2), 
            is_deposit_reward : arg5, 
            pool_reward_id    : object::id_to_address(&v6), 
            coin_type         : type_name::get<T1>(), 
            liquidity_amount  : coin::value<T1>(&v5),
        };
        event::emit<ClaimRewardEvent>(v7);
        v5
    }
    
    public(package) fun create_lending_market<T0>(arg0: &mut TxContext) : (LendingMarketOwnerCap<T0>, LendingMarket<T0>) {
        let v0 = LendingMarket<T0>{
            id                 : 0x2::object::new(arg0), 
            version            : 3, 
            reserves           : vector::empty<Reserve<T0>>(), 
            obligations        : 0x2::object_table::new<ID, Obligation<T0>>(arg0), 
            rate_limiter       : rate_limiter::new(rate_limiter::new_config(1, 18446744073709551615), 0), 
            fee_receiver       : 0x2::tx_context::sender(arg0), 
            bad_debt_usd       : decimal::from(0), 
            bad_debt_limit_usd : decimal::from(0),
        };
        let v1 = LendingMarketOwnerCap<T0>{
            id                : 0x2::object::new(arg0), 
            lending_market_id : object::id<LendingMarket<T0>>(&v0),
        };
        (v1, v0)
    }
    
    public fun deposit_ctokens_into_obligation<T0, T1>(arg0: &mut LendingMarket<T0>, arg1: u64, arg2: &ObligationOwnerCap<T0>, arg3: &Clock, arg4: Coin<reserve::CToken<T0, T1>>, arg5: &mut TxContext) {
        assert!(arg0.version == 3, 1);
        deposit_ctokens_into_obligation_by_id<T0, T1>(arg0, arg1, arg2.obligation_id, arg3, arg4, arg5);
    }
    
    fun deposit_ctokens_into_obligation_by_id<T0, T1>(arg0: &mut LendingMarket<T0>, arg1: u64, arg2: ID, arg3: &Clock, arg4: Coin<reserve::CToken<T0, T1>>, arg5: &mut TxContext) {
        assert!(arg0.version == 3, 1);
        assert!(coin::value<reserve::CToken<T0, T1>>(&arg4) > 0, 2);
        let v0 = vector::borrow_mut<Reserve<T0>>(&mut arg0.reserves, arg1);
        assert!(reserve::coin_type<T0>(v0) == type_name::get<T1>(), 3);
        let v1 = object_table::borrow_mut<ID, Obligation<T0>>(&mut arg0.obligations, arg2);
        let v2 = DepositEvent{
            lending_market_id : object::id_address<LendingMarket<T0>>(arg0), 
            coin_type         : type_name::get<T1>(), 
            reserve_id        : object::id_address<Reserve<T0>>(v0), 
            obligation_id     : object::id_address<Obligation<T0>>(v1), 
            ctoken_amount     : coin::value<reserve::CToken<T0, T1>>(&arg4),
        };
        event::emit<DepositEvent>(v2);
        obligation::deposit<T0>(v1, v0, arg3, coin::value<reserve::CToken<T0, T1>>(&arg4));
        reserve::deposit_ctokens<T0, T1>(v0, coin::into_balance<reserve::CToken<T0, T1>>(arg4));
    }
    
    fun init(arg0: LENDING_MARKET, arg1: &mut TxContext) {
        0x2::package::claim_and_keep<LENDING_MARKET>(arg0, arg1);
    }
    
    entry fun migrate<T0>(arg0: &LendingMarketOwnerCap<T0>, arg1: &mut LendingMarket<T0>) {
        assert!(arg1.version == 3 - 1, 1);
        arg1.version = 3;
    }
    
    public fun obligation_id<T0>(arg0: &ObligationOwnerCap<T0>) : ID {
        arg0.obligation_id
    }
    
    public fun redeem_ctokens_and_withdraw_liquidity<T0, T1>(arg0: &mut LendingMarket<T0>, arg1: u64, arg2: &Clock, arg3: Coin<reserve::CToken<T0, T1>>, arg4: 0x1::option::Option<RateLimiterExemption<T0, T1>>, arg5: &mut TxContext) : Coin<T1> {
        assert!(arg0.version == 3, 1);
        assert!(coin::value<reserve::CToken<T0, T1>>(&arg3) > 0, 2);
        let v0 = coin::value<reserve::CToken<T0, T1>>(&arg3);
        let v1 = vector::borrow_mut<Reserve<T0>>(&mut arg0.reserves, arg1);
        assert!(reserve::coin_type<T0>(v1) == type_name::get<T1>(), 3);
        reserve::compound_interest<T0>(v1, arg2);
        let v2 = false;
        if (0x1::option::is_some<RateLimiterExemption<T0, T1>>(&arg4)) {
            if (0x1::option::borrow_mut<RateLimiterExemption<T0, T1>>(&mut arg4).amount >= v0) {
                v2 = true;
            };
        };
        if (!v2) {
            rate_limiter::process_qty(&mut arg0.rate_limiter, clock::timestamp_ms(arg2) / 1000, reserve::ctoken_market_value_upper_bound<T0>(v1, v0));
        };
        let v3 = reserve::redeem_ctokens<T0, T1>(v1, coin::into_balance<reserve::CToken<T0, T1>>(arg3));
        assert!(balance::value<T1>(&v3) > 0, 2);
        let v4 = RedeemEvent{
            lending_market_id : object::id_address<LendingMarket<T0>>(arg0), 
            coin_type         : type_name::get<T1>(), 
            reserve_id        : object::id_address<Reserve<T0>>(v1), 
            ctoken_amount     : v0, 
            liquidity_amount  : balance::value<T1>(&v3),
        };
        event::emit<RedeemEvent>(v4);
        coin::from_balance<T1>(v3, arg5)
    }
    
    public fun refresh_reserve_price<T0>(arg0: &mut LendingMarket<T0>, arg1: u64, arg2: &Clock, arg3: &pyth::price_info::PriceInfoObject) {
        assert!(arg0.version == 3, 1);
        reserve::update_price<T0>(vector::borrow_mut<Reserve<T0>>(&mut arg0.reserves, arg1), arg2, arg3);
    }
    
    fun reserve_array_index<T0, T1>(arg0: &LendingMarket<T0>) : u64 {
        let v0 = 0;
        while (v0 < vector::length<Reserve<T0>>(&arg0.reserves)) {
            if (reserve::coin_type<T0>(vector::borrow<Reserve<T0>>(&arg0.reserves, v0)) == type_name::get<T1>()) {
                return v0
            };
            v0 = v0 + 1;
        };
        v0
    }
    
    public fun update_rate_limiter_config<T0>(arg0: &LendingMarketOwnerCap<T0>, arg1: &mut LendingMarket<T0>, arg2: &Clock, arg3: rate_limiter::RateLimiterConfig) {
        assert!(arg1.version == 3, 1);
        arg1.rate_limiter = rate_limiter::new(arg3, clock::timestamp_ms(arg2) / 1000);
    }
    
    // decompiled from Move bytecode v6
}

