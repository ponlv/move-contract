module shoshin::Marketplace {
    // modules
    use std::string::{Self,String};
    use sui::tx_context::{Self, TxContext};
    use sui::dynamic_field;
    use sui::transfer;
    use sui::object::{Self, ID, UID};
    use sui::coin::{Self,Coin};
    use sui::sui::SUI;

    const EAdminOnly:u64 = 0;
    const EWrongOwner: u64 = 8;
    const EAmountIncorrect:u64 = 9;
    const EWasOwned: u64 = 10;
    
    // // admin

    struct Admin has key {
        id: UID,
        address: address
    }

    // list

    struct Offer has store, key {
        id: UID,
        status: u64,
        offer_id: u64,
        paid: Coin<SUI>,
        offerer: address,
    }

    struct List<T: key + store> has store, key {
        id: UID,
        seller: address,
        item: T,
        price: u64,
        last_offer_id: u64,
    }

    struct Marketplace has key {
        id: UID,
        admin : address,
        name : String,
        description : String,
        fee : u64,
    }
    // init

   fun init(ctx: &mut TxContext) {
        let admin = Admin{
            id: object::new(ctx),
            address: tx_context::sender(ctx)
        };
        transfer::share_object(admin);
   }

   // create new marketplace

    entry fun create_marketplace(
        admin:&mut Admin, 
        name : vector<u8>,
        description : vector<u8>,
        fee: u64,
        ctx: &mut TxContext
    ) {
        let sender = tx_context::sender(ctx);
        let admin_address = admin.address;
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

    // list a item
    entry fun make_list<T: store + key>(marketplace: &mut Marketplace, item: T, price: u64, ctx: &mut TxContext) {        
        let nft_id = object::id(&item);
        let new_list = List<T> {
            id: object::new(ctx),
            seller: tx_context::sender(ctx),
            item: item,
            price: price,
            last_offer_id: 0,
        };
        dynamic_field::add(&mut marketplace.id, nft_id, new_list);
    }

    // delist a item
    entry fun make_delist<T: store + key>(marketplace: &mut Marketplace, nft_id: ID, ctx: &mut TxContext) {
        let List<T> { id, seller, item, price: _, last_offer_id : _} = dynamic_field::remove(&mut marketplace.id, nft_id);
        assert!(tx_context::sender(ctx) == seller, EWrongOwner);
        object::delete(id);
        transfer::transfer(item, tx_context::sender(ctx));
    }


    // adjust a item
    entry fun adjust<T: key + store>(
        marketplace: &mut Marketplace,
        nft_id: ID,
        price: u64,
        ctx: &mut TxContext
    ) {
      
        let current_list = dynamic_field::borrow_mut<ID, List<T>>(&mut marketplace.id, nft_id);
        assert!(tx_context::sender(ctx) == current_list.seller, EWrongOwner);
        current_list.price = price;
    }

    //buy and take
    public fun buy<T: key + store>(
        marketplace: &mut Marketplace,
        nft_id: ID,
        paid: Coin<SUI>,
        ctx: &mut TxContext
    ) {
        let List<T> { id, seller, item, price: price, last_offer_id: _ } = dynamic_field::remove(&mut marketplace.id, nft_id);
        assert!(price == coin::value(&paid), EAmountIncorrect);
        object::delete(id);
        transfer::transfer(paid, seller);
        transfer::transfer(item, tx_context::sender(ctx));
    }

    // // make offer
    // public entry fun make_offer<T: store + key>(mp: &mut Marketplace, nft_id: ID, coin: Coin<SUI>, ctx: &mut TxContext) {
    //     let List<T> { id, seller, item, price, last_offer_id } = dynamic_field::remove(&mut mp.id, nft_id);
    //     let offer = Offer {
    //             id: object::new(ctx), 
    //             status: 0,
    //             offer_id: last_offer_id + 1,
    //             paid: coin,
    //             offerer: tx_context::sender(ctx),
    //     };
    //     let new_list = List<T> {
    //             id: id,
    //             seller: seller,
    //             item: item,
    //             price: price,
    //             last_offer_id: last_offer_id + 1,
    //     };

    //     dynamic_field::add(&mut new_list.id, last_offer_id + 1, offer);  
    //     dynamic_field::add(&mut mp.id, nft_id, new_list);              
    // }
    
}