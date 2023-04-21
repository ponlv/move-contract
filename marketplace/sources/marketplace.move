module shoshinmarketplace::marketplace_module {
    use sui::object::{Self,ID,UID};
    use sui::tx_context::{Self, TxContext,sender};
    use std::vector;
    use sui::transfer;
    use sui::dynamic_object_field as ofield;
    use sui::package;
    use sui::display;
    use std::string::{Self,String,utf8};
    use sui::event;
    use sui::clock::{Self, Clock};
    use sui::coin::{Self, Coin};
    use sui::balance::{Self,Balance};
    use sui::sui::SUI;

    //constant
    //const MAXIMUM_CONTAINER_SIZE:u64 = 1;

    //error
    const EAdminOnly:u64 = 4003;
    const EWrongSeller: u64 = 4003+1;
    const EAmountIncorrect:u64 = 4003+2;
    const EWasOwned: u64 = 4003+3;
    const EWrongOfferOwner: u64 = 4003+4;
    const EWrongOfferPrice: u64 = 4003+5;
    const EListWasEnded:u64 = 4003+6;
    const EBidAmountIncorrect:u64 = 4003+7;
    const ESoonBid:u64 = 4003+8;
    const ELateBid:u64 = 4003+9;
    const EDenominatorInValid:u64 = 4003+10;

    struct Admin has key {
        id: UID,
        address: address,
        receive_address: address
    }

    struct Marketplace has key {
        id: UID,
        containers_list : vector<Container_Status>,
        market_commission_numerator: u64,
        market_commission_denominator: u64,
        container_maximum_size: u64
    }

    struct Container_Status has store, drop {
        container_id: ID,
        can_deposit: bool
    } 

    /*
    Container:
    one container has many dynamic object fields.
    */
    struct Container has key { 
        id: UID,
        objects_in_list: u64
    }

    /*List
    */
    struct List<T: key + store> has key, store {
        id: UID,
        container_id: ID,
        seller: address,
        item: T, 
        price: u64,
        end_time: u64,
        current_offer : u64,
        last_offer_id: u64
    }

    /*TEST*/
    struct Nft has key,store {
        id: UID,
        //url: Url,
    }
    struct MARKETPLACE has drop {}
    /*------*/


    fun init(otw: MARKETPLACE, ctx:&mut TxContext) {
        
        let admin = Admin{
            id: object::new(ctx),
            address: tx_context::sender(ctx),
            receive_address: tx_context::sender(ctx),
        };

        let marketplace = Marketplace{
            id: object::new(ctx),
            containers_list: vector::empty(),
            market_commission_numerator: 250,
            market_commission_denominator: 100,
            container_maximum_size: 3
        }; // marketplace comision fee 2.5% on each nft

        //the first container of marketplace.
        let container = Container{
            id: object::new(ctx),
            objects_in_list: 0      
        };

        let market_current_container_list = &mut marketplace.containers_list;
        //deposit new container in container list 
        vector::push_back(market_current_container_list, Container_Status{
            container_id: object::id(&container),
            can_deposit: true
        });

        /*------TEST------*/        
        let keys = vector[
            utf8(b"name"),
            utf8(b"description"),
            utf8(b"url"),
            utf8(b"project_url"),
            utf8(b"image_url"),
            utf8(b"img_url"),
            utf8(b"creator"),
        ];
        let values = vector[
            utf8(b"NFT OF ZAYN"),
            utf8(b"Zayn tr from AnnT family - nft for test"),
            utf8(b"https://i.scdn.co/image/ab67616d0000b27337f7fc54cf2701b2aeadbac5"),
            utf8(b"https://shoshinsquare.com/"),
            utf8(b"https://i.scdn.co/image/ab67616d0000b27337f7fc54cf2701b2aeadbac5"),
            utf8(b"https://i.scdn.co/image/ab67616d0000b27337f7fc54cf2701b2aeadbac5"),
            utf8(b"Zayn Tr")
        ];
        // Claim the `Publisher` for the package!
        let publisher = package::claim(otw, ctx);
        // Get a new `Display` object for the `Nft` type.
        let display = display::new_with_fields<Nft>(
            &publisher, keys, values, ctx
        );
        // Commit first version of `Display` to apply changes.
        display::update_version(&mut display);       
        transfer::public_transfer(publisher, sender(ctx));
        transfer::public_transfer(display, sender(ctx));       
        /*----*/        

        transfer::share_object(container);
        transfer::share_object(admin);
        transfer::share_object(marketplace)
    }

    /*HELPERS*/
    /*
    create new container:
    @param marketplace ID
    */
    struct EventCreateContainer has copy, drop {
        container_id: ID
    }
    fun create_new_container(marketplace:&mut Marketplace, ctx:&mut TxContext):Container {
        
        let new_container = Container{
            id: object::new(ctx),
            objects_in_list: 0
        };
        
        let market_current_container_list = &mut marketplace.containers_list;
        //deposit new container in container list 
        vector::push_back(market_current_container_list, Container_Status{
            container_id: object::id(&new_container),
            can_deposit: true
        });
        return new_container
    }

    /* check if current container is stable for deposit the object.
    */
    fun check_need_create_new_container(marketplace:&mut Marketplace, container:&mut Container):bool {

        let market_current_container_list = &mut marketplace.containers_list;
        let current_container_list_length = vector::length(market_current_container_list);
        if( current_container_list_length <= 0 ){
            return true
        };
        let current_latest_container = vector::borrow_mut(market_current_container_list, current_container_list_length-1);
        //check if this container is the lastest container in marketplace
        if(current_latest_container.container_id == object::uid_to_inner(&container.id)){
            if(current_latest_container.can_deposit == true){
            return false
            } else { return true }
        } 
        else {
            if(container.objects_in_list >= marketplace.container_maximum_size){
            return true
            } else { return false }
        };
        //TO-DO: check if any container in list can deposit
        //let index = 0;
        // while(index < current_container_list_length){
        //     let container_in_list = vector::borrow_mut(market_current_container_list,index);
        //     if(container_in_list.can_deposit == true){
        //         return false
        //     }
        // };
        return false
    }

    fun update_status_of_container_by_shared_ID(marketplace:&mut Marketplace, container:&mut Container):bool {
        let market_current_containers_list =&mut marketplace.containers_list;
        let length = vector::length(market_current_containers_list);
        let index = 0;
        while(index < length){
        let container_in_list = vector::borrow_mut(market_current_containers_list, index);
        if(container_in_list.container_id == object::uid_to_inner(&container.id)){
        container_in_list.can_deposit = false;
        };
        index = index + 1;
        };
        return true
    }


    /*ACTIONS*/
    
    /*1
    @dev USER LIST NFT TO MARKET
    @param ID marketplace 
    @param ID of the lastest container in container list
    */
    struct EventListNft has copy, drop {
        list_id: ID,
        nft_id: ID,
        container_id: ID,
        price: u64,
        seller: address,
    }
    public entry fun make_list_nft<T: key + store>(marketplace:&mut Marketplace, container:&mut Container, item: T, price: u64, end_time: u64, ctx:&mut TxContext) {
        //check max size for container on param 
        let need_to_create_new_container = check_need_create_new_container(marketplace,container);
        if(need_to_create_new_container == true){
        //update status of container.
        let _ = update_status_of_container_by_shared_ID(marketplace, container);
        let new_container = create_new_container(marketplace,ctx);
        let nft_id = object::id(&item);
        let listing = List<T>{
            id: object::new(ctx),
            container_id: object::id(&new_container),
            seller: tx_context::sender(ctx),
            item: item,
            end_time : end_time,
            price: price,
            current_offer: 0,
            last_offer_id: 0,                
        };
        event::emit(EventListNft{
            list_id: object::id(&listing),
            nft_id: nft_id,
            container_id: object::id(&new_container),
            price: price,
            seller: tx_context::sender(ctx),
        });
        
        //add the new listing nft to container
        new_container.objects_in_list =  new_container.objects_in_list + 1;
        ofield::add(&mut new_container.id, nft_id, listing);
        //emit event for create container
        event::emit(EventCreateContainer{
            container_id: object::id(&new_container)
        });
        //public container on chain
        transfer::share_object(new_container);
        }
        else {
        let nft_id = object::id(&item);
        //deposit nft in container
        let listing = List<T>{
            id: object::new(ctx),
            container_id: object::uid_to_inner(&container.id),
            seller: tx_context::sender(ctx),
            item: item,
            end_time : end_time,
            price: price,
            current_offer: 0,
            last_offer_id: 0,                
        };
        event::emit(EventListNft{
            list_id: object::id(&listing),
            nft_id: nft_id,
            container_id: object::uid_to_inner(&container.id),
            price: price,
            seller: tx_context::sender(ctx),
        });
        //add the new listing nft to container
        container.objects_in_list = container.objects_in_list + 1;
        ofield::add(&mut container.id, nft_id, listing);      
        };
    }

    /*2
    @dev USER BUY NFT
    @param 
    */
    struct EventBuyNft has copy,drop {
        nft_id : ID,
        seller : address,
        new_owner: address,
        market_fee: u64,
        seller_fee: u64,
    }
    public entry fun make_buy_nft<T: key + store >(marketplace:&mut Marketplace, admin: &Admin, container:&mut Container, nft_id: ID, coin: Coin<SUI>, ctx:&mut TxContext){
        //update number of object in container
        //Notes: need emit event for this action or not?
        container.objects_in_list = container.objects_in_list - 1;

        //get nft in container
        let List<T> {id, container_id: _, seller, item, price, end_time:_, current_offer:_, last_offer_id:_} = ofield::remove(&mut container.id, nft_id);

        //fee
        let market_commission_by_nft_price = (price * marketplace.market_commission_numerator) / (100 * marketplace.market_commission_denominator);
        let fee_for_market:Balance<SUI> = balance::split(coin::balance_mut(&mut coin), market_commission_by_nft_price);
        let fee_for_seller:Balance<SUI> = balance::split(coin::balance_mut(&mut coin), price - market_commission_by_nft_price);


        event::emit(EventBuyNft{
            nft_id : object::uid_to_inner(&id),
            seller : seller,
            new_owner: sender(ctx),
            market_fee: market_commission_by_nft_price,
            seller_fee: price - market_commission_by_nft_price,           
        });
        /*
        transfer fee to market admin, seller
        transfer nft to buyer
        */
        transfer::public_transfer(coin::from_balance(fee_for_market, ctx), admin.receive_address);
        transfer::public_transfer(coin::from_balance(fee_for_seller, ctx), seller);
        transfer::public_transfer(item, sender(ctx));
        transfer::public_transfer(coin, sender(ctx));
        object::delete(id)
    }

    /*3
    @dev USER DELIST NFT
    @param
    */ 
    struct EventDeListNft has copy, drop {
        nft_id : ID,
        seller : address
    }
    public entry fun make_delist_nft<T: key + store >(container_has_nft:&mut Container, nft_id: ID, ctx:&mut TxContext){
        //get listing nft in the container
        let List<T> {id, container_id:_, seller, item, price:_, end_time:_, current_offer:_, last_offer_id:_} = ofield::remove(&mut container_has_nft.id, nft_id);

        //only seller can do it!
        assert!(seller == sender(ctx), EWrongSeller);

        //update number of object in container
        //Notes: need emit event for this action or not?
        container_has_nft.objects_in_list = container_has_nft.objects_in_list - 1;

        
        //emit event delist nft
        event::emit(EventDeListNft{
            nft_id: object::uid_to_inner(&id),
            seller: seller
        });

        //tranfer item back to seller
        transfer::public_transfer(item, sender(ctx));
        object::delete(id)
    }

    /*4
    @dev USER UPDATE LISTING NFT PRICE
    @param
    */
    struct EventUpdateListingPrice has copy, drop {
        nft_id: ID,
        new_price: u64
    }
    public entry fun make_update_listing_price<T: store + key>(container_has_nft:&mut Container, nft_id: ID, new_price: u64, ctx:&mut TxContext){
        //get listing nft in the container
        let List<T> {id, container_id:_, seller, item, price, end_time:_, current_offer:_, last_offer_id:_} = ofield::borrow_mut(&mut container_has_nft.id, nft_id);
        
        //only seller can do it!
        assert!(seller ==&mut sender(ctx), EWrongSeller);

        //update price
        price =&mut new_price;
        //emit event
        event::emit(EventUpdateListingPrice{
            nft_id: object::uid_to_inner(id),
            new_price: new_price,
        });
    }

    /*5
    @dev ADMIN CHANGE MARKET FEE RECIVER ADRRESS
    @param
    */
    struct EventAdminChangeReciveAddress has copy, drop {
        new_market_fee_revice_address: address
    }
    public entry fun admin_change_market_fee_reciver_address(admin:&mut Admin, new_recive_address: address, ctx:&mut TxContext) {
        assert!(admin.address == sender(ctx),EAdminOnly);
        admin.receive_address = new_recive_address;
        event::emit(EventAdminChangeReciveAddress{
            new_market_fee_revice_address: new_recive_address
        })
    }

    /*6
    @dev ADMIN CHANGE MARKET COMMISSION FEE
    @param
    */
    struct EventAdminChangeMarketFee has copy, drop {
        market_commission_numerator: u64,
        market_commission_denominator: u64
    }
    public entry fun admin_update_market_fee_commission(marketplace:&mut Marketplace, admin:&mut Admin, market_commission_numerator: u64, market_commission_denominator: u64, ctx:&mut TxContext) {
        assert!(admin.address == sender(ctx), EAdminOnly);
        assert!(market_commission_denominator > 0, EDenominatorInValid);
        marketplace.market_commission_numerator = market_commission_numerator;
        marketplace.market_commission_denominator = market_commission_denominator;

        event::emit(EventAdminChangeMarketFee{
            market_commission_numerator: market_commission_numerator,
            market_commission_denominator: market_commission_denominator
        })
    }

    /*7
    @dev ADMIN CHANGE MAXIMUM SIZE OF EACH CONTAINER
    */
    public entry fun admin_change_maximum_container_size(marketplace:&mut Marketplace, admin:&mut Admin, maximum_size: u64, ctx:&mut TxContext) {
        assert!(admin.address == sender(ctx), EAdminOnly);
        marketplace.container_maximum_size = maximum_size;
    }

    /*EMERCENCY CALL*/
    /*1
    @dev ADMIN WITHRAW ALL NFTs IN CONTAINER AND CHANGE THEM TO ANOTHER
    @param
    */
    // public entry fun admin_withdraw_nfts_change_to_new_container(marketplace:&mut Marketplace, current_container:&mut Container, nfts_list: vector<ID>, ctx:&mut TxContext){

    // }

    /*TEST*/
    /*1
    @dev DEPOSIT NFTs TO CONTAINER
    */
    public entry fun test_deposit_nfts_to_container(marketplace:&mut Marketplace, container:&mut Container, ) {

    }

    /*2
    @dev MINT NFT BY AMOUNT
    */
    public entry fun mint_nfts_to_test(amount: u64, ctx:&mut TxContext){
        let index = 0;
        while( index < amount ){
            let nfts = Nft{
                id: object::new(ctx),
            };
            transfer::public_transfer(nfts,sender(ctx));
            index = index + 1;
        };
    }

    /*3
    @dev 
    */
    



    /*--------------------------------MARKETPLACE V2-------------------------------*/
    // /*Offer*/
    // struct Offer<O: key + store> has key, store {
    //     id: UID,
    //     container_id: ID,
    //     offer_id: u64,
    //     paid: O, // coin sui
    //     offer_price: u64,
    //     offerer: address,
    // }

    // /*Auctions*/
    // struct Nft_Auction<T: key + store, C: key + store> has key, store {
    //     id: UID,
    //     container_id: ID,
    //     item: T,
    //     min_bid: u64,
    //     min_bid_increment: u64,
    //     start_time: u64,
    //     end_time: u64,
    //     current_bid: u64,
    //     owner: address,
    //     bid: C,
    //     bidder: address,
    // }

    // /*Owner make offer for nft
    // */
    // struct OfferNftEvent has copy, drop {
    //     offer_id: ID,
    //     nft_id: ID,
    //     offer_price: u64,
    //     offerer: address,
    // }
    // public entry fun make_offer<T: store + key>(marketplace:&mut Marketplace, container_have_nft:&mut Container, lastest_container:&mut Container, nft_id: ID, clock:& Clock, offer_price: u64, coin:&mut Coin<SUI>, ctx:&mut TxContext){
    //     //get nft as dynamic filed in container
    //     let id_of_container_have_nft = object::uid_to_inner(&container_have_nft.id);
    //     let current_listing = ofield::borrow_mut<ID,List<T>>(&mut container_have_nft.id, nft_id);
    //     let current_time = clock::timestamp_ms(clock);
    //     //condition checking
    //     assert!(tx_context::sender(ctx) != current_listing.seller, EWasOwned);
    //     assert!(offer_price > current_listing.current_offer, EWrongOfferPrice);
    //     assert!(offer_price > current_listing.price, EWrongOfferPrice);
    //     assert!(current_listing.end_time > current_time, EListWasEnded);
    //     //check current container stored the nft is stable to store offer
    //     if( vector::length(&container_have_nft.objects_in_list) < MAXIMUM_CONTAINER_SIZE ){
    //         //create new offer
    //         let offer_balance:Balance<SUI> = balance::split(coin::balance_mut(coin), offer_price);
    //         let offer = Offer<Coin<SUI>>{
    //             id: object::new(ctx),
    //             container_id: id_of_container_have_nft,
    //             offer_id: current_listing.last_offer_id + 1,
    //             paid: coin::from_balance(offer_balance,ctx),
    //             offerer: tx_context::sender(ctx),
    //             offer_price : offer_price
    //         };

    //         //update current listing data: offer_price, last_offer_id
    //         current_listing.current_offer = offer_price;
    //         current_listing.last_offer_id = current_listing.last_offer_id+1;
    //         //emit event
    //         event::emit(OfferNftEvent{
    //             offer_id: object::id(&offer),
    //             nft_id: nft_id,
    //             offer_price: offer_price,
    //             offerer: tx_context::sender(ctx),
    //         });

    //         //add offer to current container that store the nfts in marketplace
    //         vector::push_back(&mut container_have_nft.objects_in_list,object::id(&offer));
    //         ofield::add(&mut container_have_nft.id, object::id(&offer), offer);
    //     }
    //     else {
    //     /*check current container on param is stable to store the offer*/
    //     let need_to_create_new_container = check_need_create_new_container(marketplace,lastest_container);
    //     if(need_to_create_new_container == true){
    //         //update status of container.
    //         let _ = update_status_of_container_by_shared_ID(marketplace, lastest_container);
    //         let new_container = create_new_container(marketplace,ctx);
    //         //create new offer
    //         let offer_balance:Balance<SUI> = balance::split(coin::balance_mut(coin), offer_price);
    //         let offer = Offer<Coin<SUI>>{
    //             id: object::new(ctx),
    //             container_id: object::uid_to_inner(&new_container.id),
    //             offer_id: current_listing.last_offer_id + 1,
    //             paid: coin::from_balance(offer_balance,ctx),
    //             offerer: tx_context::sender(ctx),
    //             offer_price : offer_price
    //         };

    //         //update current listing data: offer_price, last_offer_id
    //         current_listing.current_offer = offer_price;
    //         current_listing.last_offer_id = current_listing.last_offer_id+1;
    //         //emit event
    //         event::emit(OfferNftEvent{
    //             offer_id: object::id(&offer),
    //             nft_id: nft_id,
    //             offer_price: offer_price,
    //             offerer: tx_context::sender(ctx),
    //         });
    //         //add offer to the newest container in marketplace
    //         vector::push_back(&mut new_container.objects_in_list,object::id(&offer));
    //         ofield::add(&mut new_container.id, object::id(&offer), offer);

    //         //emit event for create container
    //         event::emit(EventCreateContainer{
    //         container_id: object::id(&new_container)
    //         });
    //         //public container on chain
    //         transfer::share_object(new_container);
    //     }
    //     else {
    //         //the lastest container is stable to store this offer
    //         //create new offer
    //         let offer_balance:Balance<SUI> = balance::split(coin::balance_mut(coin), offer_price);
    //         let offer = Offer<Coin<SUI>>{
    //             id: object::new(ctx),
    //             container_id: object::uid_to_inner(&lastest_container.id),
    //             offer_id: current_listing.last_offer_id + 1,
    //             paid: coin::from_balance(offer_balance,ctx),
    //             offerer: tx_context::sender(ctx),
    //             offer_price : offer_price
    //         };

    //         //update current listing data: offer_price, last_offer_id
    //         current_listing.current_offer = offer_price;
    //         current_listing.last_offer_id = current_listing.last_offer_id+1;
    //         //emit event
    //         event::emit(OfferNftEvent{
    //             offer_id: object::id(&offer),
    //             nft_id: nft_id,
    //             offer_price: offer_price,
    //             offerer: tx_context::sender(ctx),
    //         });

    //         //add offer to lastest container in marketplace
    //         vector::push_back(&mut lastest_container.objects_in_list,object::id(&offer));
    //         ofield::add(&mut lastest_container.id, object::id(&offer), offer);
    //     }
    // }
    // }

    // struct DeleteOfferEvent has copy, drop {
    //     nft_id: ID,
    //     offerer: address
    // }
    // /*make delete offer*/
    // public entry fun make_delete_offer<T: store + key>(container_have_offer: &mut Container, nft_id: ID, id_offer: ID, ctx: &mut TxContext){
        
    //     //remove id of offer in current container
    //     let index = 0;
    //     let id_list =&mut container_have_offer.objects_in_list;
    //     let length_of_id_list = vector::length(id_list);
       

    //     let Offer<Coin<SUI>>{id, container_id:_ ,offer_id:_, paid, offer_price, offerer} = ofield::remove(&mut container_have_offer.id,id_offer);
    //     event::emit(DeleteOfferEvent{
    //         nft_id: nft_id,
    //         offerer: *offerer
    //     });

    //     while( index < length_of_id_list){
    //     let item_in_id_list = vector::borrow(id_list,index);
        
    //     if(*item_in_id_list == id_offer){
    //         let id_need_rm = vector::remove(id_list,index);
    //         object::delete(id)
    //     };
    //     index = index + 1;
    //     };

    //     let offer_balance:Balance<SUI> = balance::split(coin::balance_mut(paid), *offer_price);
    //     transfer::public_transfer(coin::from_balance(offer_balance, ctx), *offerer); 
    //     object::delete(id)
    // }
}   