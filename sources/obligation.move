module suilend::obligation {
    public struct Obligation<phantom T0> has store, key {
        id: 0x2::object::UID,
        lending_market_id: 0x2::object::ID,
        deposits: vector<Deposit>,
        borrows: vector<Borrow>,
        deposited_value_usd: suilend::decimal::Decimal,
        allowed_borrow_value_usd: suilend::decimal::Decimal,
        unhealthy_borrow_value_usd: suilend::decimal::Decimal,
        super_unhealthy_borrow_value_usd: suilend::decimal::Decimal,
        unweighted_borrowed_value_usd: suilend::decimal::Decimal,
        weighted_borrowed_value_usd: suilend::decimal::Decimal,
        weighted_borrowed_value_upper_bound_usd: suilend::decimal::Decimal,
        borrowing_isolated_asset: bool,
        user_reward_managers: vector<suilend::liquidity_mining::UserRewardManager>,
        bad_debt_usd: suilend::decimal::Decimal,
        closable: bool,
    }
    
    public struct Deposit has store {
        coin_type: 0x1::type_name::TypeName,
        reserve_array_index: u64,
        deposited_ctoken_amount: u64,
        market_value: suilend::decimal::Decimal,
        user_reward_manager_index: u64,
        attributed_borrow_value: suilend::decimal::Decimal,
    }
    
    public struct Borrow has store {
        coin_type: 0x1::type_name::TypeName,
        reserve_array_index: u64,
        borrowed_amount: suilend::decimal::Decimal,
        cumulative_borrow_rate: suilend::decimal::Decimal,
        market_value: suilend::decimal::Decimal,
        user_reward_manager_index: u64,
    }
    
    public struct ObligationDataEvent has copy, drop {
        lending_market_id: address,
        obligation_id: address,
        deposits: vector<DepositRecord>,
        borrows: vector<BorrowRecord>,
        deposited_value_usd: suilend::decimal::Decimal,
        allowed_borrow_value_usd: suilend::decimal::Decimal,
        unhealthy_borrow_value_usd: suilend::decimal::Decimal,
        super_unhealthy_borrow_value_usd: suilend::decimal::Decimal,
        unweighted_borrowed_value_usd: suilend::decimal::Decimal,
        weighted_borrowed_value_usd: suilend::decimal::Decimal,
        weighted_borrowed_value_upper_bound_usd: suilend::decimal::Decimal,
        borrowing_isolated_asset: bool,
        bad_debt_usd: suilend::decimal::Decimal,
        closable: bool,
    }
    
    public struct DepositRecord has copy, drop, store {
        coin_type: 0x1::type_name::TypeName,
        reserve_array_index: u64,
        deposited_ctoken_amount: u64,
        market_value: suilend::decimal::Decimal,
        user_reward_manager_index: u64,
        attributed_borrow_value: suilend::decimal::Decimal,
    }
    
    public struct BorrowRecord has copy, drop, store {
        coin_type: 0x1::type_name::TypeName,
        reserve_array_index: u64,
        borrowed_amount: suilend::decimal::Decimal,
        cumulative_borrow_rate: suilend::decimal::Decimal,
        market_value: suilend::decimal::Decimal,
        user_reward_manager_index: u64,
    }
    
    public(package) fun borrow<T0>(arg0: &mut Obligation<T0>, arg1: &mut suilend::reserve::Reserve<T0>, arg2: &0x2::clock::Clock, arg3: u64) {
        assert!(0x1::vector::length<Borrow>(&arg0.borrows) <= 5, 6);
        assert!(find_deposit_index<T0>(arg0, arg1) == 0x1::vector::length<Deposit>(&arg0.deposits), 8);
        let idx = find_or_add_borrow<T0>(arg0, arg1, arg2);
        let v0 = 0x1::vector::borrow_mut<Borrow>(&mut arg0.borrows, idx);
        v0.borrowed_amount = suilend::decimal::add(v0.borrowed_amount, suilend::decimal::from(arg3));
        let v1 = suilend::reserve::market_value<T0>(arg1, suilend::decimal::from(arg3));
        v0.market_value = suilend::decimal::add(v0.market_value, v1);
        arg0.unweighted_borrowed_value_usd = suilend::decimal::add(arg0.unweighted_borrowed_value_usd, v1);
        arg0.weighted_borrowed_value_usd = suilend::decimal::add(arg0.weighted_borrowed_value_usd, suilend::decimal::mul(v1, suilend::reserve_config::borrow_weight(suilend::reserve::config<T0>(arg1))));
        arg0.weighted_borrowed_value_upper_bound_usd = suilend::decimal::add(arg0.weighted_borrowed_value_upper_bound_usd, suilend::decimal::mul(suilend::reserve::market_value_upper_bound<T0>(arg1, suilend::decimal::from(arg3)), suilend::reserve_config::borrow_weight(suilend::reserve::config<T0>(arg1))));
        suilend::liquidity_mining::change_user_reward_manager_share(suilend::reserve::borrows_pool_reward_manager_mut<T0>(arg1), 0x1::vector::borrow_mut<suilend::liquidity_mining::UserRewardManager>(&mut arg0.user_reward_managers, v0.user_reward_manager_index), liability_shares(v0), arg2);
        assert!(is_healthy<T0>(arg0), 1);
        if (suilend::reserve_config::isolated(suilend::reserve::config<T0>(arg1)) || arg0.borrowing_isolated_asset) {
            assert!(0x1::vector::length<Borrow>(&arg0.borrows) == 1, 4);
        };
        log_obligation_data<T0>(arg0);
    }
    
    public(package) fun claim_rewards<T0, T1>(arg0: &mut Obligation<T0>, arg1: &mut suilend::liquidity_mining::PoolRewardManager, arg2: &0x2::clock::Clock, arg3: u64) : 0x2::balance::Balance<T1> {
        let idx = find_user_reward_manager_index<T0>(arg0, arg1);
        suilend::liquidity_mining::claim_rewards<T1>(
            arg1, 
            0x1::vector::borrow_mut<suilend::liquidity_mining::UserRewardManager>(
                &mut arg0.user_reward_managers, 
                idx
            ), 
            arg2, 
            arg3
        )
    }
    
    public fun borrowed_amount<T0, T1>(arg0: &Obligation<T0>) : suilend::decimal::Decimal {
        let mut v0 = 0;
        while (v0 < 0x1::vector::length<Borrow>(&arg0.borrows)) {
            let v1 = 0x1::vector::borrow<Borrow>(&arg0.borrows, v0);
            if (v1.coin_type == 0x1::type_name::get<T1>()) {
                return v1.borrowed_amount
            };
            v0 = v0 + 1;
        };
        suilend::decimal::from(0)
    }
    
    fun compound_debt<T0>(arg0: &mut Borrow, arg1: &suilend::reserve::Reserve<T0>) {
        let v0 = suilend::reserve::cumulative_borrow_rate<T0>(arg1);
        arg0.borrowed_amount = suilend::decimal::mul(arg0.borrowed_amount, suilend::decimal::div(v0, arg0.cumulative_borrow_rate));
        arg0.cumulative_borrow_rate = v0;
    }
    
    public(package) fun create_obligation<T0>(arg0: 0x2::object::ID, arg1: &mut 0x2::tx_context::TxContext) : Obligation<T0> {
        Obligation<T0>{
            id                                      : 0x2::object::new(arg1), 
            lending_market_id                       : arg0, 
            deposits                                : 0x1::vector::empty<Deposit>(), 
            borrows                                 : 0x1::vector::empty<Borrow>(), 
            deposited_value_usd                     : suilend::decimal::from(0), 
            allowed_borrow_value_usd                : suilend::decimal::from(0), 
            unhealthy_borrow_value_usd              : suilend::decimal::from(0), 
            super_unhealthy_borrow_value_usd        : suilend::decimal::from(0), 
            unweighted_borrowed_value_usd           : suilend::decimal::from(0), 
            weighted_borrowed_value_usd             : suilend::decimal::from(0), 
            weighted_borrowed_value_upper_bound_usd : suilend::decimal::from(0), 
            borrowing_isolated_asset                : false, 
            user_reward_managers                    : 0x1::vector::empty<suilend::liquidity_mining::UserRewardManager>(), 
            bad_debt_usd                            : suilend::decimal::from(0), 
            closable                                : false,
        }
    }
    
    public(package) fun deposit<T0>(arg0: &mut Obligation<T0>, arg1: &mut suilend::reserve::Reserve<T0>, arg2: &0x2::clock::Clock, arg3: u64) {
        assert!(0x1::vector::length<Deposit>(&arg0.deposits) <= 5, 5);
        assert!(find_borrow_index<T0>(arg0, arg1) == 0x1::vector::length<Borrow>(&arg0.borrows), 8);
        let idx = find_or_add_deposit<T0>(arg0, arg1, arg2);
        let v0 = 0x1::vector::borrow_mut<Deposit>(&mut arg0.deposits, idx);
        v0.deposited_ctoken_amount = v0.deposited_ctoken_amount + arg3;
        let v1 = suilend::reserve::ctoken_market_value<T0>(arg1, arg3);
        v0.market_value = suilend::decimal::add(v0.market_value, v1);
        arg0.deposited_value_usd = suilend::decimal::add(arg0.deposited_value_usd, v1);
        arg0.allowed_borrow_value_usd = suilend::decimal::add(arg0.allowed_borrow_value_usd, suilend::decimal::mul(suilend::reserve::ctoken_market_value_lower_bound<T0>(arg1, arg3), suilend::reserve_config::open_ltv(suilend::reserve::config<T0>(arg1))));
        arg0.unhealthy_borrow_value_usd = suilend::decimal::add(arg0.unhealthy_borrow_value_usd, suilend::decimal::mul(v1, suilend::reserve_config::close_ltv(suilend::reserve::config<T0>(arg1))));
        suilend::liquidity_mining::change_user_reward_manager_share(suilend::reserve::deposits_pool_reward_manager_mut<T0>(arg1), 0x1::vector::borrow_mut<suilend::liquidity_mining::UserRewardManager>(&mut arg0.user_reward_managers, v0.user_reward_manager_index), v0.deposited_ctoken_amount, arg2);
        log_obligation_data<T0>(arg0);
    }
    
    public fun deposited_ctoken_amount<T0, T1>(arg0: &Obligation<T0>) : u64 {
        let mut v0 = 0;
        while (v0 < 0x1::vector::length<Deposit>(&arg0.deposits)) {
            let v1 = 0x1::vector::borrow<Deposit>(&arg0.deposits, v0);
            if (v1.coin_type == 0x1::type_name::get<T1>()) {
                return v1.deposited_ctoken_amount
            };
            v0 = v0 + 1;
        };
        0
    }
    
    fun find_borrow<T0>(arg0: &Obligation<T0>, arg1: &suilend::reserve::Reserve<T0>) : &Borrow {
        let v0 = find_borrow_index<T0>(arg0, arg1);
        assert!(v0 < 0x1::vector::length<Borrow>(&arg0.borrows), 2);
        0x1::vector::borrow<Borrow>(&arg0.borrows, v0)
    }
    
    fun find_borrow_index<T0>(arg0: &Obligation<T0>, arg1: &suilend::reserve::Reserve<T0>) : u64 {
        let mut v0 = 0;
        while (v0 < 0x1::vector::length<Borrow>(&arg0.borrows)) {
            if (0x1::vector::borrow<Borrow>(&arg0.borrows, v0).reserve_array_index == suilend::reserve::array_index<T0>(arg1)) {
                return v0
            };
            v0 = v0 + 1;
        };
        v0
    }
    
    fun find_deposit<T0>(arg0: &Obligation<T0>, arg1: &suilend::reserve::Reserve<T0>) : &Deposit {
        let v0 = find_deposit_index<T0>(arg0, arg1);
        assert!(v0 < 0x1::vector::length<Deposit>(&arg0.deposits), 3);
        0x1::vector::borrow<Deposit>(&arg0.deposits, v0)
    }
    
    fun find_deposit_index<T0>(arg0: &Obligation<T0>, arg1: &suilend::reserve::Reserve<T0>) : u64 {
        let mut v0 = 0;
        while (v0 < 0x1::vector::length<Deposit>(&arg0.deposits)) {
            if (0x1::vector::borrow<Deposit>(&arg0.deposits, v0).reserve_array_index == suilend::reserve::array_index<T0>(arg1)) {
                return v0
            };
            v0 = v0 + 1;
        };
        v0
    }
    
    fun find_or_add_borrow<T0>(arg0: &mut Obligation<T0>, arg1: &mut suilend::reserve::Reserve<T0>, arg2: &0x2::clock::Clock) : u64 {
        let v0 = find_borrow_index<T0>(arg0, arg1);
        if (v0 < 0x1::vector::length<Borrow>(&arg0.borrows)) {
            return v0
        };
        let (v1, _) = find_or_add_user_reward_manager<T0>(arg0, suilend::reserve::borrows_pool_reward_manager_mut<T0>(arg1), arg2);
        let v3 = Borrow{
            coin_type                 : suilend::reserve::coin_type<T0>(arg1), 
            reserve_array_index       : suilend::reserve::array_index<T0>(arg1), 
            borrowed_amount           : suilend::decimal::from(0), 
            cumulative_borrow_rate    : suilend::reserve::cumulative_borrow_rate<T0>(arg1), 
            market_value              : suilend::decimal::from(0), 
            user_reward_manager_index : v1,
        };
        0x1::vector::push_back<Borrow>(&mut arg0.borrows, v3);
        0x1::vector::length<Borrow>(&arg0.borrows) - 1
    }
    
    fun find_or_add_deposit<T0>(arg0: &mut Obligation<T0>, arg1: &mut suilend::reserve::Reserve<T0>, arg2: &0x2::clock::Clock) : u64 {
        let v0 = find_deposit_index<T0>(arg0, arg1);
        if (v0 < 0x1::vector::length<Deposit>(&arg0.deposits)) {
            return v0
        };
        let (v1, _) = find_or_add_user_reward_manager<T0>(arg0, suilend::reserve::deposits_pool_reward_manager_mut<T0>(arg1), arg2);
        let v3 = Deposit{
            coin_type                 : suilend::reserve::coin_type<T0>(arg1), 
            reserve_array_index       : suilend::reserve::array_index<T0>(arg1), 
            deposited_ctoken_amount   : 0, 
            market_value              : suilend::decimal::from(0), 
            user_reward_manager_index : v1, 
            attributed_borrow_value   : suilend::decimal::from(0),
        };
        0x1::vector::push_back<Deposit>(&mut arg0.deposits, v3);
        0x1::vector::length<Deposit>(&arg0.deposits) - 1
    }
    
    fun find_or_add_user_reward_manager<T0>(arg0: &mut Obligation<T0>, arg1: &mut suilend::liquidity_mining::PoolRewardManager, arg2: &0x2::clock::Clock) : (u64, &mut suilend::liquidity_mining::UserRewardManager) {
        let v0 = find_user_reward_manager_index<T0>(arg0, arg1);
        if (v0 < 0x1::vector::length<suilend::liquidity_mining::UserRewardManager>(&arg0.user_reward_managers)) {
            return (v0, 0x1::vector::borrow_mut<suilend::liquidity_mining::UserRewardManager>(&mut arg0.user_reward_managers, v0))
        };
        0x1::vector::push_back<suilend::liquidity_mining::UserRewardManager>(&mut arg0.user_reward_managers, suilend::liquidity_mining::new_user_reward_manager(arg1, arg2));
        let v1 = 0x1::vector::length<suilend::liquidity_mining::UserRewardManager>(&arg0.user_reward_managers);
        (v1 - 1, 0x1::vector::borrow_mut<suilend::liquidity_mining::UserRewardManager>(&mut arg0.user_reward_managers, v1 - 1))
    }
    
    fun find_user_reward_manager_index<T0>(arg0: &Obligation<T0>, arg1: &suilend::liquidity_mining::PoolRewardManager) : u64 {
        let mut v0 = 0;
        while (v0 < 0x1::vector::length<suilend::liquidity_mining::UserRewardManager>(&arg0.user_reward_managers)) {
            if (suilend::liquidity_mining::pool_reward_manager_id(0x1::vector::borrow<suilend::liquidity_mining::UserRewardManager>(&arg0.user_reward_managers, v0)) == 0x2::object::id<suilend::liquidity_mining::PoolRewardManager>(arg1)) {
                return v0
            };
            v0 = v0 + 1;
        };
        v0
    }
    
    public(package) fun forgive<T0>(arg0: &mut Obligation<T0>, arg1: &mut suilend::reserve::Reserve<T0>, arg2: &0x2::clock::Clock, arg3: suilend::decimal::Decimal) : suilend::decimal::Decimal {
        assert!(is_forgivable<T0>(arg0), 7);
        repay<T0>(arg0, arg1, arg2, arg3)
    }
    
    public fun is_forgivable<T0>(arg0: &Obligation<T0>) : bool {
        0x1::vector::length<Deposit>(&arg0.deposits) == 0
    }
    
    public fun is_healthy<T0>(arg0: &Obligation<T0>) : bool {
        suilend::decimal::le(arg0.weighted_borrowed_value_upper_bound_usd, arg0.allowed_borrow_value_usd)
    }
    
    public fun is_liquidatable<T0>(arg0: &Obligation<T0>) : bool {
        suilend::decimal::gt(arg0.weighted_borrowed_value_usd, arg0.unhealthy_borrow_value_usd)
    }
    
    fun liability_shares(arg0: &Borrow) : u64 {
        suilend::decimal::floor(suilend::decimal::div(arg0.borrowed_amount, arg0.cumulative_borrow_rate))
    }
    
    public(package) fun liquidate<T0>(arg0: &mut Obligation<T0>, arg1: &mut vector<suilend::reserve::Reserve<T0>>, arg2: u64, arg3: u64, arg4: &0x2::clock::Clock, arg5: u64) : (u64, suilend::decimal::Decimal) {
        assert!(is_liquidatable<T0>(arg0), 0);
        let v0 = 0x1::vector::borrow<suilend::reserve::Reserve<T0>>(arg1, arg2);
        let v1 = 0x1::vector::borrow<suilend::reserve::Reserve<T0>>(arg1, arg3);
        let v2 = find_borrow<T0>(arg0, v0);
        let v3 = find_deposit<T0>(arg0, v1);
        let v4 = if (suilend::decimal::le(v2.market_value, suilend::decimal::from(1))) {
            suilend::decimal::min(v2.borrowed_amount, suilend::decimal::from(arg5))
        } else {
            suilend::decimal::min(suilend::decimal::mul(suilend::decimal::div(suilend::decimal::min(suilend::decimal::mul(arg0.weighted_borrowed_value_usd, suilend::decimal::from_percent(20)), v2.market_value), v2.market_value), v2.borrowed_amount), suilend::decimal::from(arg5))
        };
        let v5 = suilend::decimal::mul(suilend::reserve::market_value<T0>(v0, v4), suilend::decimal::add(suilend::decimal::from(1), suilend::decimal::add(suilend::reserve_config::liquidation_bonus(suilend::reserve::config<T0>(v1)), suilend::reserve_config::protocol_liquidation_fee(suilend::reserve::config<T0>(v1)))));
        let (v6, v7) = if (suilend::decimal::lt(v3.market_value, v5)) {
            (suilend::decimal::mul(v4, suilend::decimal::div(v3.market_value, v5)), v3.deposited_ctoken_amount)
        } else {
            (v4, suilend::decimal::floor(suilend::decimal::mul(suilend::decimal::from(v3.deposited_ctoken_amount), suilend::decimal::div(v5, v3.market_value))))
        };
        repay<T0>(arg0, 0x1::vector::borrow_mut<suilend::reserve::Reserve<T0>>(arg1, arg2), arg4, v6);
        withdraw_unchecked<T0>(arg0, 0x1::vector::borrow_mut<suilend::reserve::Reserve<T0>>(arg1, arg3), arg4, v7);
        log_obligation_data<T0>(arg0);
        (v7, v6)
    }
    
    fun log_obligation_data<T0>(arg0: &Obligation<T0>) {
        let mut v0 = 0;
        let mut v1 = 0x1::vector::empty<DepositRecord>();
        while (v0 < 0x1::vector::length<Deposit>(&arg0.deposits)) {
            let v2 = 0x1::vector::borrow<Deposit>(&arg0.deposits, v0);
            let v3 = DepositRecord{
                coin_type                 : v2.coin_type, 
                reserve_array_index       : v2.reserve_array_index, 
                deposited_ctoken_amount   : v2.deposited_ctoken_amount, 
                market_value              : v2.market_value, 
                user_reward_manager_index : v2.user_reward_manager_index, 
                attributed_borrow_value   : v2.attributed_borrow_value,
            };
            0x1::vector::push_back<DepositRecord>(&mut v1, v3);
            v0 = v0 + 1;
        };
        let mut v4 = 0;
        let mut v5 = 0x1::vector::empty<BorrowRecord>();
        while (v4 < 0x1::vector::length<Borrow>(&arg0.borrows)) {
            let v6 = 0x1::vector::borrow<Borrow>(&arg0.borrows, v4);
            let v7 = BorrowRecord{
                coin_type                 : v6.coin_type, 
                reserve_array_index       : v6.reserve_array_index, 
                borrowed_amount           : v6.borrowed_amount, 
                cumulative_borrow_rate    : v6.cumulative_borrow_rate, 
                market_value              : v6.market_value, 
                user_reward_manager_index : v6.user_reward_manager_index,
            };
            0x1::vector::push_back<BorrowRecord>(&mut v5, v7);
            v4 = v4 + 1;
        };
        let v8 = ObligationDataEvent{
            lending_market_id                       : 0x2::object::id_to_address(&arg0.lending_market_id), 
            obligation_id                           : 0x2::object::uid_to_address(&arg0.id), 
            deposits                                : v1, 
            borrows                                 : v5, 
            deposited_value_usd                     : arg0.deposited_value_usd, 
            allowed_borrow_value_usd                : arg0.allowed_borrow_value_usd, 
            unhealthy_borrow_value_usd              : arg0.unhealthy_borrow_value_usd, 
            super_unhealthy_borrow_value_usd        : arg0.super_unhealthy_borrow_value_usd, 
            unweighted_borrowed_value_usd           : arg0.unweighted_borrowed_value_usd, 
            weighted_borrowed_value_usd             : arg0.weighted_borrowed_value_usd, 
            weighted_borrowed_value_upper_bound_usd : arg0.weighted_borrowed_value_upper_bound_usd, 
            borrowing_isolated_asset                : arg0.borrowing_isolated_asset, 
            bad_debt_usd                            : arg0.bad_debt_usd, 
            closable                                : arg0.closable,
        };
        0x2::event::emit<ObligationDataEvent>(v8);
    }
    
    public(package) fun max_borrow_amount<T0>(arg0: &Obligation<T0>, arg1: &suilend::reserve::Reserve<T0>) : u64 {
        suilend::decimal::floor(suilend::reserve::usd_to_token_amount_lower_bound<T0>(arg1, suilend::decimal::div(suilend::decimal::saturating_sub(arg0.allowed_borrow_value_usd, arg0.weighted_borrowed_value_upper_bound_usd), suilend::reserve_config::borrow_weight(suilend::reserve::config<T0>(arg1)))))
    }
    
    public(package) fun max_withdraw_amount<T0>(arg0: &Obligation<T0>, arg1: &suilend::reserve::Reserve<T0>) : u64 {
        let v0 = find_deposit_index<T0>(arg0, arg1);
        assert!(v0 < 0x1::vector::length<Deposit>(&arg0.deposits), 3);
        if (suilend::reserve_config::open_ltv(suilend::reserve::config<T0>(arg1)) == suilend::decimal::from(0) || 0x1::vector::length<Borrow>(&arg0.borrows) == 0) {
            return 0x1::vector::borrow<Deposit>(&arg0.deposits, v0).deposited_ctoken_amount
        };
        0x2::math::min(suilend::decimal::floor(suilend::decimal::div(suilend::reserve::usd_to_token_amount_upper_bound<T0>(arg1, suilend::decimal::div(suilend::decimal::saturating_sub(arg0.allowed_borrow_value_usd, arg0.weighted_borrowed_value_upper_bound_usd), suilend::reserve_config::open_ltv(suilend::reserve::config<T0>(arg1)))), suilend::reserve::ctoken_ratio<T0>(arg1))), 0x1::vector::borrow<Deposit>(&arg0.deposits, v0).deposited_ctoken_amount)
    }
    
    public(package) fun refresh<T0>(arg0: &mut Obligation<T0>, arg1: &mut vector<suilend::reserve::Reserve<T0>>, arg2: &0x2::clock::Clock) {
        let mut v0 = 0;
        let mut v1 = suilend::decimal::from(0);
        let mut v2 = suilend::decimal::from(0);
        let mut v3 = suilend::decimal::from(0);
        while (v0 < 0x1::vector::length<Deposit>(&arg0.deposits)) {
            let v4 = 0x1::vector::borrow_mut<Deposit>(&mut arg0.deposits, v0);
            let v5 = 0x1::vector::borrow_mut<suilend::reserve::Reserve<T0>>(arg1, v4.reserve_array_index);
            suilend::reserve::compound_interest<T0>(v5, arg2);
            suilend::reserve::assert_price_is_fresh<T0>(v5, arg2);
            let v6 = suilend::reserve::ctoken_market_value<T0>(v5, v4.deposited_ctoken_amount);
            v4.market_value = v6;
            v1 = suilend::decimal::add(v1, v6);
            v2 = suilend::decimal::add(v2, suilend::decimal::mul(suilend::reserve::ctoken_market_value_lower_bound<T0>(v5, v4.deposited_ctoken_amount), suilend::reserve_config::open_ltv(suilend::reserve::config<T0>(v5))));
            v3 = suilend::decimal::add(v3, suilend::decimal::mul(v6, suilend::reserve_config::close_ltv(suilend::reserve::config<T0>(v5))));
            v0 = v0 + 1;
        };
        arg0.deposited_value_usd = v1;
        arg0.allowed_borrow_value_usd = v2;
        arg0.unhealthy_borrow_value_usd = v3;
        let mut v7 = 0;
        let mut v8 = suilend::decimal::from(0);
        let mut v9 = suilend::decimal::from(0);
        let mut v10 = suilend::decimal::from(0);
        let mut v11 = false;
        while (v7 < 0x1::vector::length<Borrow>(&arg0.borrows)) {
            let v12 = 0x1::vector::borrow_mut<Borrow>(&mut arg0.borrows, v7);
            let v13 = 0x1::vector::borrow_mut<suilend::reserve::Reserve<T0>>(arg1, v12.reserve_array_index);
            suilend::reserve::compound_interest<T0>(v13, arg2);
            suilend::reserve::assert_price_is_fresh<T0>(v13, arg2);
            compound_debt<T0>(v12, v13);
            let v14 = suilend::reserve::market_value<T0>(v13, v12.borrowed_amount);
            v12.market_value = v14;
            v8 = suilend::decimal::add(v8, v14);
            v9 = suilend::decimal::add(v9, suilend::decimal::mul(v14, suilend::reserve_config::borrow_weight(suilend::reserve::config<T0>(v13))));
            v10 = suilend::decimal::add(v10, suilend::decimal::mul(suilend::reserve::market_value_upper_bound<T0>(v13, v12.borrowed_amount), suilend::reserve_config::borrow_weight(suilend::reserve::config<T0>(v13))));
            if (suilend::reserve_config::isolated(suilend::reserve::config<T0>(v13))) {
                v11 = true;
            };
            v7 = v7 + 1;
        };
        arg0.unweighted_borrowed_value_usd = v8;
        arg0.weighted_borrowed_value_usd = v9;
        arg0.weighted_borrowed_value_upper_bound_usd = v10;
        arg0.borrowing_isolated_asset = v11;
    }
    
    public(package) fun repay<T0>(arg0: &mut Obligation<T0>, arg1: &mut suilend::reserve::Reserve<T0>, arg2: &0x2::clock::Clock, arg3: suilend::decimal::Decimal) : suilend::decimal::Decimal {
        let v0 = find_borrow_index<T0>(arg0, arg1);
        assert!(v0 < 0x1::vector::length<Borrow>(&arg0.borrows), 2);
        let v1 = 0x1::vector::borrow_mut<Borrow>(&mut arg0.borrows, v0);
        compound_debt<T0>(v1, arg1);
        let v2 = suilend::decimal::min(arg3, v1.borrowed_amount);
        let v3 = suilend::decimal::sub(v1.borrowed_amount, v1.borrowed_amount);
        v1.borrowed_amount = suilend::decimal::sub(v1.borrowed_amount, v2);
        if (suilend::decimal::le(v3, v2)) {
            let v4 = suilend::decimal::saturating_sub(v2, v3);
            let v5 = suilend::reserve::market_value<T0>(arg1, v4);
            v1.market_value = suilend::decimal::saturating_sub(v1.market_value, v5);
            arg0.unweighted_borrowed_value_usd = suilend::decimal::saturating_sub(arg0.unweighted_borrowed_value_usd, v5);
            arg0.weighted_borrowed_value_usd = suilend::decimal::saturating_sub(arg0.weighted_borrowed_value_usd, suilend::decimal::mul(v5, suilend::reserve_config::borrow_weight(suilend::reserve::config<T0>(arg1))));
            arg0.weighted_borrowed_value_upper_bound_usd = suilend::decimal::saturating_sub(arg0.weighted_borrowed_value_upper_bound_usd, suilend::decimal::mul(suilend::reserve::market_value_upper_bound<T0>(arg1, v4), suilend::reserve_config::borrow_weight(suilend::reserve::config<T0>(arg1))));
        } else {
            let v6 = suilend::decimal::saturating_sub(v3, v2);
            let v7 = suilend::reserve::market_value<T0>(arg1, v6);
            v1.market_value = suilend::decimal::add(v1.market_value, v7);
            arg0.unweighted_borrowed_value_usd = suilend::decimal::add(arg0.unweighted_borrowed_value_usd, v7);
            arg0.weighted_borrowed_value_usd = suilend::decimal::add(arg0.weighted_borrowed_value_usd, suilend::decimal::mul(v7, suilend::reserve_config::borrow_weight(suilend::reserve::config<T0>(arg1))));
            arg0.weighted_borrowed_value_upper_bound_usd = suilend::decimal::add(arg0.weighted_borrowed_value_upper_bound_usd, suilend::decimal::mul(suilend::reserve::market_value_upper_bound<T0>(arg1, v6), suilend::reserve_config::borrow_weight(suilend::reserve::config<T0>(arg1))));
        };
        suilend::liquidity_mining::change_user_reward_manager_share(suilend::reserve::borrows_pool_reward_manager_mut<T0>(arg1), 0x1::vector::borrow_mut<suilend::liquidity_mining::UserRewardManager>(&mut arg0.user_reward_managers, v1.user_reward_manager_index), liability_shares(v1), arg2);
        if (suilend::decimal::eq(v1.borrowed_amount, suilend::decimal::from(0))) {
            let Borrow {
                coin_type                 : _,
                reserve_array_index       : _,
                borrowed_amount           : _,
                cumulative_borrow_rate    : _,
                market_value              : _,
                user_reward_manager_index : _,
            } = 0x1::vector::remove<Borrow>(&mut arg0.borrows, v0);
        };
        log_obligation_data<T0>(arg0);
        v2
    }
    
    public(package) fun withdraw<T0>(arg0: &mut Obligation<T0>, arg1: &mut suilend::reserve::Reserve<T0>, arg2: &0x2::clock::Clock, arg3: u64) {
        withdraw_unchecked<T0>(arg0, arg1, arg2, arg3);
        assert!(is_healthy<T0>(arg0), 1);
        log_obligation_data<T0>(arg0);
    }
    
    fun withdraw_unchecked<T0>(arg0: &mut Obligation<T0>, arg1: &mut suilend::reserve::Reserve<T0>, arg2: &0x2::clock::Clock, arg3: u64) {
        let v0 = find_deposit_index<T0>(arg0, arg1);
        assert!(v0 < 0x1::vector::length<Deposit>(&arg0.deposits), 3);
        let v1 = 0x1::vector::borrow_mut<Deposit>(&mut arg0.deposits, v0);
        let v2 = suilend::reserve::ctoken_market_value<T0>(arg1, arg3);
        v1.market_value = suilend::decimal::sub(v1.market_value, v2);
        v1.deposited_ctoken_amount = v1.deposited_ctoken_amount - arg3;
        arg0.deposited_value_usd = suilend::decimal::sub(arg0.deposited_value_usd, v2);
        arg0.allowed_borrow_value_usd = suilend::decimal::sub(arg0.allowed_borrow_value_usd, suilend::decimal::mul(suilend::reserve::ctoken_market_value_lower_bound<T0>(arg1, arg3), suilend::reserve_config::open_ltv(suilend::reserve::config<T0>(arg1))));
        arg0.unhealthy_borrow_value_usd = suilend::decimal::sub(arg0.unhealthy_borrow_value_usd, suilend::decimal::mul(v2, suilend::reserve_config::close_ltv(suilend::reserve::config<T0>(arg1))));
        suilend::liquidity_mining::change_user_reward_manager_share(suilend::reserve::deposits_pool_reward_manager_mut<T0>(arg1), 0x1::vector::borrow_mut<suilend::liquidity_mining::UserRewardManager>(&mut arg0.user_reward_managers, v1.user_reward_manager_index), v1.deposited_ctoken_amount, arg2);
        if (v1.deposited_ctoken_amount == 0) {
            let Deposit {
                coin_type                 : _,
                reserve_array_index       : _,
                deposited_ctoken_amount   : _,
                market_value              : _,
                user_reward_manager_index : _,
                attributed_borrow_value   : _,
            } = 0x1::vector::remove<Deposit>(&mut arg0.deposits, v0);
        };
    }
    
    // decompiled from Move bytecode v6
}

