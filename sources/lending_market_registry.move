module suilend::lending_market_registry {
    use sui::table::{Self, Table};
    use std::type_name::{Self, TypeName};
    use suilend::lending_market::{Self, LendingMarket, LendingMarketOwnerCap};

    public struct Registry has key {
        id: UID,
        version: u64,
        lending_markets: Table<TypeName, ID>,
    }
    
    public struct LENDING_MARKET_2 {
        dummy_field: bool,
    }
    
    public fun create_lending_market<T0>(
        arg0: &mut Registry, 
        arg1: &mut TxContext
    ) : (LendingMarketOwnerCap<T0>, LendingMarket<T0>) {
        assert!(arg0.version == 1, 1);
        let (v0, v1) = lending_market::create_lending_market<T0>(arg1);
        let v2 = v1;
        table::add<TypeName, ID>(&mut arg0.lending_markets, type_name::get<T0>(), object::id<LendingMarket<T0>>(&v2));
        (v0, v2)
    }
    
    fun init(arg0: &mut tx_context::TxContext) {
        let v0 = Registry{
            id              : object::new(arg0), 
            version         : 1, 
            lending_markets : table::new<TypeName, ID>(arg0),
        };
        transfer::share_object<Registry>(v0);
    }
    
    // decompiled from Move bytecode v6
}

