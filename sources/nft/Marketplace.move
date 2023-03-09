module shoshin::Marketplace {
    // modules
    use std::type_name::{Self, TypeName};
    use std::string::{Self,String};
    use sui::tx_context::{Self, TxContext};
    use sui::dynamic_field;
    use sui::transfer;
    use sui::event;
    use sui::object::{Self, ID, UID};
    use sui::coin::{Self,Coin};
    use sui::sui::SUI;
    use shoshin::Nfts::{Self, Admin};
        

    const EAdminOnly:u64 = 0;
    const EWrongOwner: u64 = 8;
    const EAmountIncorrect:u64 = 9;
    const EWasOwned: u64 = 10;
    
    // // admin

    // struct Admin has key {
    //     id: UID,
    //     address: address
    // }

    // list

    struct List<T: key + store> has store, key {
        id: UID,
        seller: address,
        item: T,
        price: u64,
    }

    struct Marketplace has key {
        id: UID,
        admin : address,
        name : String,
        description : String,
        fee : u64
    }

    // event
    struct ListNftEvent has copy, drop {
        nft_id: ID,
        price: u64,
        type_name: TypeName,
    }

    struct DelistNftEvent has copy, drop {
        nft_id: ID,
        price: u64,
        type_name: TypeName,
    }

     struct AdjustNftEvent has copy, drop {
        nft_id: ID,
        price: u64,
        type_name: TypeName,
    }

    // init

   fun init(_: &mut TxContext) {
        // Nfts::create_admin(ctx);
   }

   // create new marketplace

    public entry fun create_marketplace(
        admin:&mut Admin, 
        name : vector<u8>,
        description : vector<u8>,
        fee: u64,
        ctx: &mut TxContext
    ) {
        let sender = tx_context::sender(ctx);
        let admin_address = Nfts::get_address(admin);
        assert!(admin_address == sender,EAdminOnly);
        let marketplace = Marketplace {
            id: object::new(ctx),
            admin: admin_address,
            name: string::utf8(name),
            description: string::utf8(description),
            fee: fee
        };
        transfer::share_object(marketplace);
    }

    // adjust a item
    public fun make_adjust<T: key + store>(
        marketplace: &mut Marketplace,
        nft_id: ID,
        price: u64,
        ctx: &mut TxContext
    ) {
      
        let current_list = dynamic_field::borrow_mut<ID, List<T>>(&mut marketplace.id, nft_id);
        assert!(tx_context::sender(ctx) == current_list.seller, EWrongOwner);
        // emit event
        event::emit(ListNftEvent {
            nft_id: nft_id,
            price: price,
            type_name: type_name::get<T>(),
        });
        // adjust
        current_list.price = price;
    }

    // list a item
    public entry fun make_list<T: store + key>(marketplace: &mut Marketplace, item: T, price: u64, ctx: &mut TxContext) {
        // emit event
        event::emit(ListNftEvent {
            nft_id: object::id(&item),
            price: price,
            type_name: type_name::get<T>(),
        });

        // do list
        let nft_id = object::id(&item);
        let new_list = List<T> {
                id: object::new(ctx),
                seller: tx_context::sender(ctx),
                item: item,
                price: price,
        };
        dynamic_field::add(&mut marketplace.id, nft_id, new_list);
    }

    // delist a item
    public entry fun make_delist<T: store + key>(marketplace: &mut Marketplace, nft_id: ID, ctx: &mut TxContext) {
        // get current nft list
        let List<T> { id, seller, item, price: _} = dynamic_field::remove(&mut marketplace.id, nft_id);
        // check owner
        assert!(tx_context::sender(ctx) == seller, EWrongOwner);
        // emit event
        event::emit(DelistNftEvent {
            nft_id: object::id(&item),
            price: 0,
            type_name: type_name::get<T>(),
        });
        // delete and transfer
        object::delete(id);
        transfer::transfer(item, tx_context::sender(ctx));
    }

    // buy and take
    public fun buy_and_take<T: key + store + drop>(
        admin:&mut Admin, 
        marketplace: &mut Marketplace,
        nft_id: ID,
        paid: Coin<SUI>,
        ctx: &mut TxContext
    ) {
        let List<T> { id, seller, item, price } = dynamic_field::remove(&mut marketplace.id, nft_id);
        object::delete(id);
        assert!(tx_context::sender(ctx) == seller, EWasOwned);
        event::emit(DelistNftEvent {
            nft_id: object::id(&item),
            price: price,
            type_name: type_name::get<T>(),
        });

        let sent = coin::value(&paid);
        assert!(price <= sent, EAmountIncorrect);
        let marketFee = (price * (marketplace.fee as u64)) / 10000u64;
        let admin_address = Nfts::get_address(admin);
        if(sent > price){
            transfer::transfer(coin::split(&mut paid, marketFee, ctx), admin_address);
            transfer::transfer(coin::split(&mut paid, price - marketFee, ctx), seller);
            transfer::transfer(paid, tx_context::sender(ctx));
            transfer::transfer(item, tx_context::sender(ctx));
        } else {
            transfer::transfer(paid, seller);
        };
    }
    
}