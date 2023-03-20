module shoshinmarketplace::marketplace_module {
        use sui::object::{Self, ID, UID};
        use std::string::{Self,String};
        use sui::transfer;
        use sui::tx_context::{Self, TxContext};
        use sui::coin::{Self, Coin};
        use sui::dynamic_object_field as ofield;
        use sui::sui::SUI;
        use sui::event;
        use std::vector;
        use sui::balance::{Self,Balance};

        const EAdminOnly:u64 = 0;
        const EWrongOwner: u64 = 8;
        const EAmountIncorrect:u64 = 9;
        const EWasOwned: u64 = 10;
        const EWrongOfferOwner: u64 = 11;
        const EWrongOfferPrice: u64 = 12;
        const EListWasEnded:u64 = 13;


        struct Admin has key {
            id: UID,
            address: address,
            receive_address : address
        }

        
        struct Offer<C: key + store> has store, key {
                id: UID,
                offer_id: u64,
                paid: C,
                offer_price: u64,
                offerer: address,
        }

        struct ListOffer<C: key + store> has store, key {
                id: UID,
                offers : vector<Offer<C>>
        }

        struct Marketplace has key {
                id: UID,
                admin : address,
                receive_address : address,
                name : String,
                description : String,
                fee : u64,
        }

        struct List<T: key + store> has store, key {
                id: UID,
                seller: address,
                item: T,
                price: u64,
                end_time: u64,
                current_offer : u64,
                last_offer_id: u64,
        }

        fun init(ctx: &mut TxContext) {
            let admin = Admin{
                id: object::new(ctx),
                address: tx_context::sender(ctx),
                receive_address: tx_context::sender(ctx),
            };
            transfer::share_object(admin);
        }


        public entry fun update_admin_receive_address(admin: &mut Admin, admin_addresss: address, ctx: &mut TxContext) {
                let sender = tx_context::sender(ctx);
                assert!(sender == admin.address, EAdminOnly);
                admin.receive_address = admin_addresss;
        }

        struct UpdateReceiveAddressMarketplaceEvent has copy, drop {
                marketplace_id: ID,
                receive_address: address
        }

        public entry fun update_marketplace_fee(marketplace: &mut Marketplace, receive_address : address, ctx: &mut TxContext) {
                let sender = tx_context::sender(ctx);
                let admin_address = marketplace.admin;
                assert!(admin_address == sender,EAdminOnly);
                event::emit(UpdateReceiveAddressMarketplaceEvent{
                        marketplace_id: object::id(marketplace),
                        receive_address: receive_address
                });
                marketplace.receive_address = receive_address;
        }


        struct UpdateFeeMarketplaceEvent has copy, drop {
                marketplace_id: ID,
                fee : u64
        }

        public entry fun update_marketplace_receive_address(marketplace: &mut Marketplace, fee: u64, ctx: &mut TxContext) {
                let sender = tx_context::sender(ctx);
                let admin_address = marketplace.admin;
                assert!(admin_address == sender,EAdminOnly);
                event::emit(UpdateFeeMarketplaceEvent{
                        marketplace_id: object::id(marketplace),
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
                        receive_address: admin.receive_address,
                        admin : admin_address,
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
                let List<T> { id, seller, item, price,current_offer: _, end_time: _, last_offer_id } = ofield::remove(&mut marketplace.id, nft_id);
                assert!(tx_context::sender(ctx) == seller, EWrongOwner);
                 if (last_offer_id != 0) {
                        let ListOffer<Coin<SUI>> {id: offer_id, offers} = ofield::remove(&mut marketplace.id, 0);
                        let index = 0;
                        let duration = vector::length(&mut offers);
                        while (index < duration) {
                                let Offer<Coin<SUI>> {id : offerId, offer_id : _, paid, offer_price, offerer} = vector::remove(&mut offers, 0);
                                if(coin::value(&mut paid) != 0 ) {
                                        let offer_balance:Balance<SUI> = balance::split(coin::balance_mut(&mut paid), offer_price);
                                        transfer::transfer(coin::from_balance(offer_balance, ctx), offerer);
                                        coin::destroy_zero(paid);
                                        object::delete(offerId);
                                        index = index + 1;
                                }
                                else {
                                        coin::destroy_zero(paid);
                                        object::delete(offerId);
                                        index = index + 1;
                                }
                        }; 
                        vector::destroy_empty(offers);
                        object::delete(offer_id);     
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

        public entry fun make_buy_item<T: store + key>(marketplace: &mut Marketplace, nft_id: ID, current_time: u64, coin:&mut Coin<SUI>, ctx: &mut TxContext) {
                let List<T> { id, seller, item, price, current_offer: _, end_time, last_offer_id} = ofield::remove(&mut marketplace.id, nft_id);
                assert!(coin::value(coin) >= price , EAmountIncorrect);
                assert!(end_time > current_time, EListWasEnded);

                 if (last_offer_id != 0) {
                        let ListOffer<Coin<SUI>> {id: offer_id, offers} = ofield::remove(&mut marketplace.id, 0);
                        let index = 0;
                        let duration = vector::length(&mut offers);
                        while (index < duration) {
                                let Offer<Coin<SUI>> {id : offerId, offer_id : _, paid, offer_price, offerer} = vector::remove(&mut offers, 0);
                                if(coin::value(&mut paid) != 0 ) {
                                        let offer_balance:Balance<SUI> = balance::split(coin::balance_mut(&mut paid), offer_price);
                                        transfer::transfer(coin::from_balance(offer_balance, ctx), offerer);
                                        coin::destroy_zero(paid);
                                        object::delete(offerId);
                                        index = index + 1;
                                }
                                else {
                                        coin::destroy_zero(paid);
                                        object::delete(offerId);
                                        index = index + 1;
                                }
                        }; 
                        vector::destroy_empty(offers);
                        object::delete(offer_id);     
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
                transfer::transfer(coin::from_balance(fee_balance,ctx), marketplace.receive_address);
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

        public entry fun make_list_item<T: store + key>(marketplace: &mut Marketplace, item: T, price: u64, end_time: u64, ctx: &mut TxContext) {
                let nft_id = object::id(&item);
                let listing = List<T> {
                        id: object::new(ctx),
                        seller: tx_context::sender(ctx),
                        item: item,
                        end_time : end_time,
                        price: price,
                        current_offer: 0,
                        last_offer_id: 0,
                };
                event::emit(ListNftEvent{
                        list_id: object::id(&listing),
                        nft_id: nft_id,
                        price: price,
                        seller: tx_context::sender(ctx),
                });   

                let init_offer = ListOffer<Coin<SUI>> {
                        id: object::new(ctx),
                        offers : vector::empty(),
                };

                ofield::add(&mut marketplace.id, 0, init_offer); 
                ofield::add(&mut marketplace.id, nft_id, listing);
        }

        struct OfferNftEvent has copy, drop {
                list_id: ID,
                nft_id: ID,
                offer_price: u64,
                offerer: address,
        }

        public entry fun make_offer<T: store + key>(marketplace: &mut Marketplace, nft_id: ID, offer_price: u64, current_time: u64, coin: &mut Coin<SUI>, ctx: &mut TxContext) {
                let List<T> { id, seller, item, price, current_offer, end_time, last_offer_id } = ofield::remove(&mut marketplace.id, nft_id);
                assert!(tx_context::sender(ctx) != seller, EWasOwned);
                assert!(offer_price > current_offer, EWrongOfferPrice);
                assert!(offer_price > price, EWrongOfferPrice);
                assert!(end_time > current_time, EListWasEnded);
                let ListOffer<Coin<SUI>> { id : _, offers} = ofield::borrow_mut(&mut marketplace.id, 0);
                let offer_balance:Balance<SUI> = balance::split(coin::balance_mut(coin), offer_price);
                vector::push_back(offers, Offer<Coin<SUI>> {
                        id: object::new(ctx),
                        offer_id: last_offer_id + 1,
                        paid: coin::from_balance(offer_balance,ctx),
                        offerer: tx_context::sender(ctx),
                        offer_price : offer_price
                });
                let new_list = List<T> {
                        id: object::new(ctx),
                        seller: seller,
                        item: item,
                        price: price,
                        end_time : end_time,
                        current_offer: offer_price,
                        last_offer_id: last_offer_id + 1,
                };
                event::emit(OfferNftEvent{
                        list_id: object::id(&new_list),
                        nft_id: nft_id,
                        offer_price: price,
                        offerer: tx_context::sender(ctx),
                });
                object::delete(id);
                ofield::add(&mut marketplace.id, nft_id, new_list);              
        }

        struct DeleteOfferEvent has copy, drop {
                nft_id: ID,
                offerer: address
        }

        public entry fun make_delete_offer<T: store + key>(marketplace: &mut Marketplace, nft_id: ID, offer_id: u64, ctx: &mut TxContext) {
                let List<T> { id : _, seller: _, item: _, price : _, current_offer: _, end_time: _, last_offer_id: _ } = ofield::borrow_mut(&mut marketplace.id, nft_id);
                let ListOffer<Coin<SUI>> {id: _, offers} = ofield::borrow_mut(&mut marketplace.id, 0);
                let index = 0;
                let duration = vector::length(offers);
                while (index < duration) {
                        let Offer<Coin<SUI>> {id : _, offer_id : current_offer_id, paid, offer_price, offerer} = vector::borrow_mut(offers, index);
                        if(offer_id == *current_offer_id) {
                                event::emit(DeleteOfferEvent{
                                        nft_id: nft_id,
                                        offerer: *offerer,
                                });
                                let offer_balance:Balance<SUI> = balance::split(coin::balance_mut(paid), *offer_price);
                                transfer::transfer(coin::from_balance(offer_balance, ctx), *offerer);
                        };
                        index = index + 1;
                };
        }

        struct AcceptOfferEvent has copy, drop {
                nft_id: ID,
                price : u64,
                offerer: address,
                seller: address
        }

        public entry fun make_accept_offer<T: store + key>(marketplace: &mut Marketplace, nft_id: ID, offer_id: u64, ctx: &mut TxContext) { 
                let List<T> { id, seller, item, price : _, current_offer: _, end_time: _, last_offer_id } = ofield::remove(&mut marketplace.id, nft_id);
                assert!(tx_context::sender(ctx) == seller, EWrongOfferOwner);
                let offer_address : address = tx_context::sender(ctx);
                if (last_offer_id != 0) {
                        let ListOffer<Coin<SUI>> {id: list_offer_id, offers} = ofield::remove(&mut marketplace.id, 0);
                        let index = 0;
                        let duration = vector::length(&mut offers);
                        while (index < duration) {
                                let Offer<Coin<SUI>> {id : offerId, offer_id : current_offer_id, paid, offer_price, offerer} = vector::remove(&mut offers, 0);
                                if(coin::value(&mut paid) != 0 ) {
                                        if(current_offer_id == offer_id) {
                                                offer_address = offerer;
                                                event::emit(AcceptOfferEvent{
                                                        nft_id: nft_id,
                                                        price : offer_price,
                                                        offerer: offerer,
                                                        seller: seller
                                                });
                                                let fee_price = offer_price * marketplace.fee / 100;
                                                let buy_balance:Balance<SUI> = balance::split(coin::balance_mut(&mut paid), offer_price - fee_price);
                                                let fee_balance:Balance<SUI> = balance::split(coin::balance_mut(&mut paid), fee_price);
                                                transfer::transfer(coin::from_balance(buy_balance, ctx), seller);
                                                transfer::transfer(coin::from_balance(fee_balance, ctx), marketplace.receive_address);
                                                coin::destroy_zero(paid);
                                                object::delete(offerId);
                                                index = index + 1;
                                        } else {
                                                let offer_balance:Balance<SUI> = balance::split(coin::balance_mut(&mut paid), offer_price);
                                                transfer::transfer(coin::from_balance(offer_balance, ctx), offerer);
                                                coin::destroy_zero(paid);
                                                object::delete(offerId);
                                                index = index + 1;
                                        }
                                }
                                else {
                                        coin::destroy_zero(paid);
                                        object::delete(offerId);
                                        index = index + 1;
                                }
                        }; 
                        vector::destroy_empty(offers);
                        object::delete(list_offer_id);     
                };
                transfer::transfer(item, offer_address);
                object::delete(id);
        } 

}