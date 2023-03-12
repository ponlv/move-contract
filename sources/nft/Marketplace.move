module shoshin::marketplace {
        use sui::object::{Self, ID, UID};
        use std::string::{Self,String};
        use sui::transfer;
        use sui::tx_context::{Self, TxContext};
        use sui::coin::{Self, Coin};
        use sui::dynamic_object_field as ofield;
        use sui::sui::SUI;
        use sui::event;
        use sui::balance::{Self,Balance};

        const EAdminOnly:u64 = 0;
        const EWrongOwner: u64 = 8;
        const EAmountIncorrect:u64 = 9;
        const EWasOwned: u64 = 10;
        const EWrongOfferOwner: u64 = 11;

        struct Admin has key {
            id: UID,
            address: address
        }

        struct Offer<C: key + store> has store, key {
                id: UID,
                offer_id: u64,
                paid: C,
                offerer: address,
        }

        struct Marketplace has key {
                id: UID,
                admin : address,
                name : String,
                description : String,
                fee : u64,
        }

        struct List<T: key + store> has store, key {
                id: UID,
                seller: address,
                item: T,
                price: u64,
                last_offer_id: u64,
        }


        fun init(ctx: &mut TxContext) {
            let admin = Admin{
                id: object::new(ctx),
                address: tx_context::sender(ctx)
            };
            transfer::share_object(admin);
        }

        struct UpdateMarketplaceEvent has copy, drop {
                marketplace_id: ID,
                marketplace_name: String,
                marketplace_admin_address: address,
                fee : u64
        }

        public entry fun update_marketplace_fee(marketplace: &mut Marketplace, fee: u64, ctx: &mut TxContext) {
                let sender = tx_context::sender(ctx);
                let admin_address = marketplace.admin;
                assert!(admin_address == sender,EAdminOnly);
                event::emit(UpdateMarketplaceEvent{
                        marketplace_id: object::id(marketplace),
                        marketplace_name: marketplace.name,
                        marketplace_admin_address: marketplace.admin,
                        fee: marketplace.fee
                });
                marketplace.fee = fee;
        }

        struct CreateMarketplaceEvent has copy, drop {
                marketplace_id: ID,
                marketplace_name: String,
                marketplace_admin_address: address,
                fee : u64
        }

        public entry fun create_marketplace(admin:&mut Admin, name : vector<u8>, description : vector<u8>, fee: u64, ctx: &mut TxContext) {
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
                event::emit(CreateMarketplaceEvent{
                        marketplace_id: object::id(&marketplace),
                        marketplace_name: marketplace.name,
                        marketplace_admin_address: marketplace.admin,
                        fee: marketplace.fee
                });
                transfer::share_object(marketplace);
        } 

        struct DelistNftEvent has copy, drop {
                nft_id: ID,
                price: u64,
                seller: address,
        }

        public entry fun make_delist_item<T: store + key>(marketplace: &mut Marketplace, nft_id: ID, ctx: &mut TxContext) {
                let List<T> { id, seller, item, price, last_offer_id } = ofield::remove(&mut marketplace.id, nft_id);
                assert!(tx_context::sender(ctx) == seller, EWrongOwner);
                if (last_offer_id != 0) {
                        let Offer<Coin<SUI>> {id: idOffer,  offer_id: _, paid, offerer} = ofield::remove(&mut id, last_offer_id);
                        object::delete(idOffer);
                        transfer::transfer(paid, offerer);
                };
                event::emit(DelistNftEvent{
                        nft_id: object::id(&item),
                        price: price,
                        seller: seller,
                });
                transfer::transfer(item, tx_context::sender(ctx));
                object::delete(id);
        }

        struct BuyNftEvent has copy, drop {
                nft_id: ID,
                price: u64,
                seller: address,
                buyer: address
        }

        public entry fun make_buy_item<T: store + key>(marketplace: &mut Marketplace, nft_id: ID, coin:&mut Coin<SUI>, ctx: &mut TxContext) {
                let List<T> { id, seller, item, price, last_offer_id } = ofield::remove(&mut marketplace.id, nft_id);
                assert!(coin::value(coin) >= price , EAmountIncorrect);
                 if (last_offer_id != 0) {
                        let Offer<Coin<SUI>> {id: idOffer,  offer_id: _, paid, offerer} = ofield::remove(&mut id, last_offer_id);
                        object::delete(idOffer);
                        transfer::transfer(paid, offerer);
                };
                event::emit(BuyNftEvent{
                        nft_id: object::id(&item),
                        price: price,
                        seller: seller,
                        buyer: tx_context::sender(ctx),
                });
                let fee = price / 100 * marketplace.fee;
                let buy_fee = price - fee;
                let fee_balance:Balance<SUI> = balance::split(coin::balance_mut(coin), fee);
                transfer::transfer(coin::from_balance(fee_balance,ctx), marketplace.admin);
                let buy_balance:Balance<SUI> = balance::split(coin::balance_mut(coin), buy_fee);
                transfer::transfer(coin::from_balance(buy_balance,ctx), seller);
                transfer::transfer(item, tx_context::sender(ctx)); 
                object::delete(id);        
        }

        struct UpdateNftEvent has copy, drop {
                nft_id: ID,
                price: u64,
        }

        public entry fun make_adjust<T: key + store>(marketplace: &mut Marketplace, nft_id: ID, price: u64, ctx: &mut TxContext) {
                let current_list = ofield::borrow_mut<ID, List<T>>(&mut marketplace.id, nft_id);
                assert!(tx_context::sender(ctx) == current_list.seller, EWrongOwner);
                event::emit(UpdateNftEvent{
                        nft_id: nft_id,
                        price: price
                });
                current_list.price = price;
        }

        struct ListNftEvent has copy, drop {
                list_id: ID,
                nft_id: ID,
                price: u64,
                seller: address,
        }

        public entry fun make_list_item<T: store + key>(marketplace: &mut Marketplace, item: T, price: u64, ctx: &mut TxContext) {
                let nft_id = object::id(&item);
                let listing = List<T> {
                        id: object::new(ctx),
                        seller: tx_context::sender(ctx),
                        item: item,
                        price: price,
                        last_offer_id: 0,
                };
                event::emit(ListNftEvent{
                        list_id: object::id(&listing),
                        nft_id: nft_id,
                        price: price,
                        seller: tx_context::sender(ctx),
                });
                ofield::add(&mut marketplace.id, nft_id, listing);
        }

        struct OfferNftEvent has copy, drop {
                list_id: ID,
                nft_id: ID,
                offer_price: u64,
                offerer: address,
        }

        public entry fun make_offer<T: store + key>(marketplace: &mut Marketplace, nft_id: ID, offer_price: u64, coin: &mut Coin<SUI>, ctx: &mut TxContext) {
                let List<T> { id, seller, item, price, last_offer_id } = ofield::remove(&mut marketplace.id, nft_id);
                assert!(tx_context::sender(ctx) != seller, EWasOwned);
                let offer_balance:Balance<SUI> = balance::split(coin::balance_mut(coin), offer_price);
                let offer = Offer<Coin<SUI>> {
                        id: object::new(ctx), 
                        offer_id: last_offer_id + 1,
                        paid: coin::from_balance(offer_balance,ctx),
                        offerer: tx_context::sender(ctx),
                };
                object::delete(id);
                let new_list = List<T> {
                        id: object::new(ctx),
                        seller: seller,
                        item: item,
                        price: price,
                        last_offer_id: last_offer_id + 1,
                };
                event::emit(OfferNftEvent{
                        list_id: object::id(&new_list),
                        nft_id: nft_id,
                        offer_price: price,
                        offerer: tx_context::sender(ctx),
                });
                ofield::add(&mut new_list.id, last_offer_id + 1, offer);  
                ofield::add(&mut marketplace.id, nft_id, new_list);              
        }

        struct DeleteOfferEvent has copy, drop {
                list_id: ID,
                nft_id: ID,
                offerer: address,
                seller: address
        }

        public entry fun make_delete_offer<T: store + key>(marketplace: &mut Marketplace, nft_id: ID, offer_id: u64, ctx: &mut TxContext) {
                let List<T> { id, seller, item, price, last_offer_id } = ofield::remove(&mut marketplace.id, nft_id);
                let Offer<Coin<SUI>> {id: idOffer, offer_id: _, paid, offerer } = ofield::remove(&mut id, offer_id);
                assert!(tx_context::sender(ctx) == offerer, EWrongOfferOwner);
                object::delete(id);
                object::delete(idOffer);
                transfer::transfer(paid, tx_context::sender(ctx));
                let new_list = List<T> {
                        id: object::new(ctx),
                        seller: seller,
                        item: item,
                        price: price,
                        last_offer_id: last_offer_id,
                };
                event::emit(DeleteOfferEvent{
                        list_id: object::id(&new_list),
                        nft_id: nft_id,
                        offerer: offerer,
                        seller: seller
                });
                ofield::add(&mut marketplace.id, nft_id, new_list); 
        }

        struct AcceptOfferEvent has copy, drop {
                nft_id: ID,
                price : u64,
                offerer: address,
                seller: address
        }

        public entry fun make_accept_offer<T: store + key>(mp: &mut Marketplace, nft_id: ID, offer_id: u64, ctx: &mut TxContext) { 
                let List<T> { id, seller, item, price, last_offer_id: _ } = ofield::remove(&mut mp.id, nft_id);
                assert!(tx_context::sender(ctx) == seller, EWrongOfferOwner);
                let Offer<Coin<SUI>> {id: idOffer, offer_id: _, paid, offerer } = ofield::remove(&mut id, offer_id);
                event::emit(AcceptOfferEvent{
                        nft_id: nft_id,
                        price : price,
                        offerer: offerer,
                        seller: seller
                });
                transfer::transfer(paid, seller);
                transfer::transfer(item, offerer);
                object::delete(idOffer);
                object::delete(id);
        } 

}