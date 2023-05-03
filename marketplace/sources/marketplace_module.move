module shoshinmarketplace::marketplace_module {
    use sui::object::{Self,ID,UID};
    use sui::tx_context::{Self, TxContext,sender};
    use std::vector;
    use sui::transfer;
    use sui::dynamic_object_field as ofield;
    use std::string::{Self,String};
    use sui::event;
    use sui::clock::{Self, Clock};
    use sui::coin::{Self, Coin};
    use sui::balance::{Self,Balance};
    use sui::sui::SUI;
    use std::type_name::{Self};
    //collection fee
    use shoshinmarketplace::collection_fee_module::{Self,FeeContainer};

    /**ERRORS*/
    const EAdminOnly:u64 = 4003;
    const EWrongSeller: u64 = 4004;
    const EAmountIncorrect:u64 = 4005;
    const EListWasEnded:u64 = 4009;
    //Offer errors
    const EWrongOfferOwner: u64 = 4007;
    const EWrongOfferPrice: u64 = 4008;
    const EOwnerOnly:u64 = 4014;
    const EOfferDuration:u64 = 4015; //Offer still alive
    const ENotTheSameNft:u64 = 4016;
    const EVectorNull:u64 = 4017;
    //Auctions
    const ENotInTheAuctionTime:u64 = 5001;
    const EPriceTooLow:u64 = 5002;
    const ENotOwner:u64 = 5003;
    const EMaximumSize:u64 = 5004;
    const EWasOwned:u64 = 5005;


    struct Admin has key {
        id: UID,
        enable_addresses: vector<address>,
        receive_address: address,
        pool: Coin<SUI>,
        total_pool: u64,
    }

    struct Marketplace has key {
        id: UID,
        containers_list : vector<Container_Status>,
        container_maximum_size: u64,
        collection_fee_container_id: ID
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
    }

    struct AuctionItem<T: key + store> has key, store {
        id: UID,
        seller: address,
        current_offerer : address,
        container_id: ID,
        item: T, 
        start_price: u64,
        current_price: u64,
        paid: Coin<SUI>,
        start_time: u64,
        end_time: u64,
    }

    fun init(ctx:&mut TxContext) {
        let enable_addresses = vector::empty();
        vector::push_back(&mut enable_addresses, sender(ctx));
        let admin = Admin{
            id: object::new(ctx),
            enable_addresses: enable_addresses,
            receive_address: tx_context::sender(ctx),
            pool: coin::from_balance(balance::zero<SUI>(), ctx),
            total_pool: 0,
        };

        let collection_fee_container_id = collection_fee_module::create_fee_container(25 ,ctx);

        let marketplace = Marketplace{
            id: object::new(ctx),
            containers_list: vector::empty(),
            collection_fee_container_id: collection_fee_container_id,
            container_maximum_size: 100
        };

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

        transfer::share_object(container);
        transfer::share_object(admin);
        transfer::share_object(marketplace)
    }

    public entry fun withdraw(admin: &mut Admin, receive_address: address, ctx: &mut TxContext) {
        let sender = sender(ctx);
        //admin only
        assert!(isAdmin(admin, sender) == true, EAdminOnly);
        let money:Balance<SUI> = balance::split(coin::balance_mut(&mut admin.pool), admin.total_pool);
        transfer::public_transfer(coin::from_balance(money, ctx), receive_address);
        admin.total_pool = 0;
    }

    /*HELPERS*/
    /*
    create new container:
    @param marketplace ID
    */

    public fun isAdmin(admin: &mut Admin, address : address) : bool {
        let rs = false;
        let list = admin.enable_addresses;

        let length = vector::length(&list);

        let index = 0;

        while(index < length) {
            let current = vector::borrow(&list, index);
            if(*current == address) {
                rs = true;
                break
            };
            index = index + 1;
        };
        rs
    }



    struct EventCreateContainer has copy, drop {
        container_id: ID
    }
    fun create_new_container(marketplace:&mut Marketplace, ctx:&mut TxContext):Container {
        
        let new_container = Container{
            id: object::new(ctx),
            objects_in_list: 1
        };
        
        let market_current_container_list = &mut marketplace.containers_list;
        //deposit new container in container list 
        vector::push_back(market_current_container_list, Container_Status{
            container_id: object::id(&new_container),
            can_deposit: true
        });
        return new_container
    }

    fun check_sender_is_in_enable_admin_addresses(admin:&mut Admin, ctx:&mut TxContext):bool {
        let index = 0;
        let enable_addresses = admin.enable_addresses;
        let length = vector::length(&enable_addresses);
        //loop
        while(index < length){
            let address_in_vector = vector::borrow(&enable_addresses, index);
            if(sender(ctx) == *address_in_vector) {
                return true
            };
            index = index + 1;
        };
        return false
    }


    public fun change_container_status(auction:&mut Marketplace, container: &mut Container, status : bool) {
        let containers = &mut auction.containers_list;
        let length = vector::length(containers);
        let index = 0;
        while(index < length){
        let current_container = vector::borrow_mut(containers, index);
            if(current_container.container_id == object::uid_to_inner(&container.id)){
                current_container.can_deposit = status;
                break
            };
            index = index + 1;
        };
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
        marketplace_id: ID,//to define which version of marketpace
        price: u64,
        seller: address,
    }
    public entry fun make_list_nft<T: key + store>(marketplace:&mut Marketplace, container:&mut Container, marketplace_package_id: ID, item: T, price: u64, ctx:&mut TxContext) {
        //check max size for container on param 
        
        if(container.objects_in_list >= marketplace.container_maximum_size){
        //update status of container.
        change_container_status(marketplace,container,false);
        let new_container = create_new_container(marketplace,ctx);
        let nft_id = object::id(&item);
        let listing = List<T>{
            id: object::new(ctx),
            container_id: object::id(&new_container),
            seller: tx_context::sender(ctx),
            item: item,
            price: price,              
        };
        event::emit(EventListNft{
            list_id: object::id(&listing),
            nft_id: nft_id,
            container_id: object::id(&new_container),
            marketplace_id: marketplace_package_id,
            price: price,
            seller: tx_context::sender(ctx),
        });
        
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
           // end_time : end_time,
            price: price,            
        };
        event::emit(EventListNft{
            list_id: object::id(&listing),
            nft_id: nft_id,
            container_id: object::uid_to_inner(&container.id),
            marketplace_id: marketplace_package_id,
            price: price,
            seller: tx_context::sender(ctx),
        });
        // check full
        if(container.objects_in_list + 1 == marketplace.container_maximum_size) {
            change_container_status(marketplace, container, false);
        };
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
    }

    public entry fun make_buy_nft<T: key + store >(marketplace:&mut Marketplace, admin: &mut Admin, container:&mut Container, nft_id: ID, coin: Coin<SUI>, collection_fees:&mut FeeContainer, ctx:&mut TxContext){
        //comission
        let seller_commission:u64;
        
        //update number of object in container
        //Notes: need emit event for this action or not?
        // check full
        change_container_status(marketplace, container, true);
        container.objects_in_list = container.objects_in_list - 1;

        //get nft in container
        let List<T> {id, container_id: _, seller, item, price} = ofield::remove(&mut container.id, nft_id);

        //fee
        let market_commission_by_nft_price = collection_fee_module::get_service_fee(collection_fees, price);
        //get collection_name from nft type
        let collection_name = string::from_ascii(type_name::into_string(type_name::get<T>()));
        let (creator_address, creator_commision) = collection_fee_module::get_creator_fee(collection_fees,collection_name, price, ctx);
        if( creator_commision > 0 ){
            seller_commission = price - creator_commision - market_commission_by_nft_price;
            let fee_for_creator:Balance<SUI> = balance::split(coin::balance_mut(&mut coin), creator_commision);
            transfer::public_transfer(coin::from_balance(fee_for_creator, ctx), creator_address)
        }else{
            seller_commission = price - market_commission_by_nft_price;
        };
        
        let fee_for_market:Balance<SUI> = balance::split(coin::balance_mut(&mut coin), market_commission_by_nft_price);
        let fee_for_seller:Balance<SUI> = balance::split(coin::balance_mut(&mut coin), seller_commission);


        event::emit(EventBuyNft{
            nft_id : nft_id,
            seller : seller,
            new_owner: sender(ctx),
        });
        /*
        transfer fee to market admin, seller
        transfer nft to buyer
        */
        coin::join(&mut admin.pool, coin::from_balance(fee_for_market, ctx));
        admin.total_pool = admin.total_pool + market_commission_by_nft_price;

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
    public entry fun make_delist_nft<T: key + store >(marketplace: &mut Marketplace, container_has_nft:&mut Container, nft_id: ID, ctx:&mut TxContext){
        //get listing nft in the container
        let List<T> {id, container_id:_, seller, item, price:_} = ofield::remove(&mut container_has_nft.id, nft_id);

        //only seller can do it!
        assert!(seller == sender(ctx), EWrongSeller);

        //update number of object in container
        //Notes: need emit event for this action or not?
        // check full
        change_container_status(marketplace, container_has_nft, true);
        container_has_nft.objects_in_list = container_has_nft.objects_in_list - 1;


        //emit event delist nft
        event::emit(EventDeListNft{
            nft_id: nft_id,
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
        let List<T> {id:_, container_id:_, seller, item: _, price} = ofield::borrow_mut(&mut container_has_nft.id, nft_id);
        
        //only seller can do it!
        assert!(seller ==&mut sender(ctx), EWrongSeller);

        //update price
        *price = new_price;
        //emit event
        event::emit(EventUpdateListingPrice{
            nft_id: nft_id,
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
        assert!(check_sender_is_in_enable_admin_addresses(admin,ctx) == true,EAdminOnly);
        admin.receive_address = new_recive_address;
        event::emit(EventAdminChangeReciveAddress{
            new_market_fee_revice_address: new_recive_address
        })
    }


    /*8
    @dev ADMIN UPDATE ENABLE ADDRESSES
    */
    public entry fun admin_update_enable_addresses(admin:&mut Admin, new_enable_addresses: vector<address>, ctx:&mut TxContext){
        let length_of_vector = vector::length(&new_enable_addresses);
        assert!(length_of_vector > 0, EVectorNull);

        //check if the sender has abilities to update this vector!
        assert!(check_sender_is_in_enable_admin_addresses(admin,ctx) == true,EAdminOnly);

        vector::append(&mut admin.enable_addresses, new_enable_addresses);
    }




    // /*--------------------------------MARKETPLACE V2-------------------------------*/
    /*Offer*/
    struct Offer<O: key + store> has key, store {
        id: UID,
        nft_id: ID,
        container_id: ID,
        paid: O, // coin sui
        offer_price: u64,
        offerer: address,
        end_time: u64,
    }
    /*User make an offer for one nft
    */
    struct OfferNftEvent has copy, drop {
        offer_id: ID,
        nft_id: ID,
        offer_price: u64,
        offerer: address,
        marketplace_id: ID,//ID of deployed contract
        expried_at: u64,
        container_id: ID,
    }
    
    public entry fun make_offer_with_nft<T: store + key>(marketplace:&mut Marketplace, container: &mut Container, marketplace_id: ID, nft_id: ID, offer_price: u64, coin: Coin<SUI>, end_time: u64, ctx:&mut TxContext){
        /*check current container on param is stable to store the offer*/
        if(container.objects_in_list >= marketplace.container_maximum_size){
            //update status of container.
            change_container_status(marketplace,container,false);
            let new_container = create_new_container(marketplace,ctx);
            //create new offer
            let offer_balance:Balance<SUI> = balance::split(coin::balance_mut(&mut coin), offer_price);
            let offer = Offer<Coin<SUI>>{
                id: object::new(ctx),
                nft_id: nft_id,
                container_id: object::uid_to_inner(&new_container.id),
                paid: coin::from_balance(offer_balance,ctx),
                offer_price: offer_price,
                offerer: tx_context::sender(ctx),
                end_time: end_time
            };

            //emit event
            event::emit(OfferNftEvent{
                offer_id: object::id(&offer),
                nft_id: nft_id,
                offer_price: offer_price,
                offerer: tx_context::sender(ctx),
                marketplace_id: marketplace_id,
                expried_at: end_time,
                container_id: object::uid_to_inner(&new_container.id)
            });

            ofield::add(&mut new_container.id, object::id(&offer), offer);

            //emit event for create container
            event::emit(EventCreateContainer{
            container_id: object::id(&new_container)
            });
            //public container on chain
            transfer::share_object(new_container);
        }
        else {
            //the lastest container is stable to store this offer
            //create new offer
            let offer_balance:Balance<SUI> = balance::split(coin::balance_mut(&mut coin), offer_price);
            let offer = Offer<Coin<SUI>>{
                id: object::new(ctx),
                nft_id: nft_id,
                container_id: object::uid_to_inner(&container.id),
                paid: coin::from_balance(offer_balance,ctx),
                offer_price: offer_price,
                offerer: tx_context::sender(ctx),
                end_time: end_time
            };

            //emit event
            event::emit(OfferNftEvent{
                offer_id: object::id(&offer),
                nft_id: nft_id,
                offer_price: offer_price,
                offerer: tx_context::sender(ctx),
                marketplace_id: marketplace_id,
                expried_at: end_time,
                container_id: object::uid_to_inner(&container.id)
            });

             // check full
            if(container.objects_in_list + 1 == marketplace.container_maximum_size) {
                change_container_status(marketplace, container, false);
            };
            //add offer to lastest container in marketplace
            container.objects_in_list = container.objects_in_list + 1;
            ofield::add(&mut container.id, object::id(&offer), offer);
        };
        transfer::public_transfer(coin,sender(ctx))   
    }


    struct DeleteOfferEvent has copy, drop {
        offer_id: ID,
        nft_id: ID,
        offerer: address
    }
    /*make delete offer*/
    public entry fun make_user_delete_offer(marketplace:&mut Marketplace, container_has_offer: &mut Container, nft_id: ID, id_offer: ID, ctx: &mut TxContext){
        
        let container_id =&mut container_has_offer.id;
        let Offer<Coin<SUI>>{id, nft_id:_, container_id:_ , paid, offer_price: _, offerer, end_time: _} = ofield::remove(container_id,id_offer);
        assert!(offerer == sender(ctx),EOwnerOnly);

        // check full
        change_container_status(marketplace, container_has_offer, true);
        container_has_offer.objects_in_list = container_has_offer.objects_in_list - 1;

        event::emit(DeleteOfferEvent{
            offer_id: object::uid_to_inner(&id),
            nft_id: nft_id,
            offerer: offerer
        });

        transfer::public_transfer(paid, offerer);
        object::delete(id)
    }


    struct AdminReturnOfferEvent has copy, drop {
        offer_id: ID,
        nft_id: ID,
        offerer: address
    }
    /*admin return offer*/
    public entry fun make_admin_return_offer(marketplace: &mut Marketplace, container_has_offer: &mut Container, admin:&mut Admin,nft_id: ID, id_offer: ID, clock: &Clock, ctx: &mut TxContext){
        
        let container_id =&mut container_has_offer.id;
        let current_time = clock::timestamp_ms(clock);
        let Offer<Coin<SUI>>{id, nft_id:_, container_id:_ , paid, offer_price: _, offerer, end_time} = ofield::remove(container_id,id_offer);
        
        //requirement
        assert!(check_sender_is_in_enable_admin_addresses(admin,ctx) == true,EAdminOnly);
        assert!(current_time > end_time, EOfferDuration);

        change_container_status(marketplace, container_has_offer, true);
        container_has_offer.objects_in_list = container_has_offer.objects_in_list - 1;
        event::emit(DeleteOfferEvent{
            offer_id: object::uid_to_inner(&id),
            nft_id: nft_id,
            offerer: offerer
        });

        //return coin back to offerer
        transfer::public_transfer(paid, offerer); 
        object::delete(id)
    }

    struct OwnerAcceptOfferEvent has copy, drop {
        nft_id: ID,
        offer_price: u64,
        seller: address,
        new_nft_owner: address
    }
    public entry fun make_accept_offer_with_listed_nft_in_different_container<T: store + key>(marketplace:&mut Marketplace, admin:&mut Admin, collection_fees:&mut FeeContainer, container_has_nft: &mut Container, container_has_offer: &mut Container, nft_id: ID, offer_id: ID, clock: &Clock, ctx: &mut TxContext){
        
        //seller commision
        let seller_commission:u64;
        let current_time = clock::timestamp_ms(clock);
        let List<T> {id: nft_in_container_id, container_id:_, seller, item:nft, price:_} = ofield::remove(&mut container_has_nft.id, nft_id);
        assert!(seller == sender(ctx), EWrongSeller);//only seller can accept offer
        //
        let Offer<Coin<SUI>>{id: offer_in_container_id, nft_id:_, container_id:_ , paid, offer_price, offerer, end_time} = ofield::remove(&mut container_has_offer.id, offer_id);
        assert!(current_time < end_time, EOfferDuration);
            
        //FEE
        //transfer fee to seller, service fee to marketplace admin, collections fee to owner.
        let marketplace_commission_by_nft_price = collection_fee_module::get_service_fee(collection_fees, offer_price);
        //get collection_name from type T
        let collection_name = string::from_ascii(type_name::into_string(type_name::get<T>()));
        let (creator_address, creator_commision) = collection_fee_module::get_creator_fee(collection_fees, collection_name, offer_price,ctx);

        if(creator_commision > 0){
            seller_commission = offer_price - creator_commision - marketplace_commission_by_nft_price;
            //split fee for creator from balance coin that user send to offer 
            let fee_for_creator:Balance<SUI> = balance::split(coin::balance_mut(&mut paid), creator_commision);
            transfer::public_transfer(coin::from_balance(fee_for_creator, ctx), creator_address)
        }else{
            seller_commission = offer_price - marketplace_commission_by_nft_price;
        };

        let fee_for_market:Balance<SUI> = balance::split(coin::balance_mut(&mut paid), marketplace_commission_by_nft_price);
        let fee_for_seller:Balance<SUI> = balance::split(coin::balance_mut(&mut paid), seller_commission);
        

        event::emit(OwnerAcceptOfferEvent{
            nft_id: nft_id,
            offer_price: offer_price,
            seller: seller,
            new_nft_owner: offerer
        });

        /*update status of containers*/
        // check full
        change_container_status(marketplace, container_has_offer, true);
        // check full
        change_container_status(marketplace, container_has_nft, true);
        container_has_offer.objects_in_list =  container_has_offer.objects_in_list - 1;
        container_has_nft.objects_in_list =  container_has_nft.objects_in_list - 1;

        /*
        Transfer fee to market admin, nft owner, collection creator
        */

        coin::join(&mut admin.pool, coin::from_balance(fee_for_market, ctx));
        admin.total_pool = admin.total_pool + marketplace_commission_by_nft_price;

        transfer::public_transfer(coin::from_balance(fee_for_seller, ctx), seller);
        //transfer nft to offerer
        transfer::public_transfer(nft,offerer);
        transfer::public_transfer(paid, offerer);
        //remove nft and offer out of their container
        object::delete(nft_in_container_id);
        object::delete(offer_in_container_id);
    }

    public entry fun make_accept_offer_with_listed_nft_in_same_container<T: store + key>(marketplace:&mut Marketplace, admin:&mut Admin, collection_fees:&mut FeeContainer, container: &mut Container, nft_id: ID, offer_id: ID, clock: &Clock, ctx: &mut TxContext){
        //seller commision
        let seller_commission:u64;
        let current_time = clock::timestamp_ms(clock);
        let List<T> {id: nft_in_container_id, container_id:_, seller, item:nft, price:_} = ofield::remove(&mut container.id, nft_id);
        assert!(seller == sender(ctx), EWrongSeller);//only seller can accept offer
        //
        let Offer<Coin<SUI>>{id: offer_in_container_id, nft_id:_, container_id:_ , paid, offer_price, offerer, end_time} = ofield::remove(&mut container.id, offer_id);
        assert!(current_time < end_time, EOfferDuration);
            
        //FEE
        //transfer fee to seller, service fee to marketplace admin, collections fee to owner.
        let marketplace_commission_by_nft_price = collection_fee_module::get_service_fee(collection_fees, offer_price);
        //get collection_name from type T
        let collection_name = string::from_ascii(type_name::into_string(type_name::get<T>()));
        let (creator_address, creator_commision) = collection_fee_module::get_creator_fee(collection_fees, collection_name, offer_price,ctx);

        if(creator_commision > 0){
            seller_commission = offer_price - creator_commision - marketplace_commission_by_nft_price;
            //split fee for creator from balance coin that user send to offer 
            let fee_for_creator:Balance<SUI> = balance::split(coin::balance_mut(&mut paid), creator_commision);
            transfer::public_transfer(coin::from_balance(fee_for_creator, ctx), creator_address)
        }else{
            seller_commission = offer_price - marketplace_commission_by_nft_price;
        };

        let fee_for_market:Balance<SUI> = balance::split(coin::balance_mut(&mut paid), marketplace_commission_by_nft_price);
        let fee_for_seller:Balance<SUI> = balance::split(coin::balance_mut(&mut paid), seller_commission);
        

        event::emit(OwnerAcceptOfferEvent{
            nft_id: nft_id,
            offer_price: offer_price,
            seller: seller,
            new_nft_owner: offerer
        });

        /*update status of containers*/
        change_container_status(marketplace,container,true);
        container.objects_in_list =  container.objects_in_list - 2;

        /*
        Transfer fee to market admin, nft owner, collection creator
        */
        coin::join(&mut admin.pool, coin::from_balance(fee_for_market, ctx));
        admin.total_pool = admin.total_pool + marketplace_commission_by_nft_price;

        transfer::public_transfer(coin::from_balance(fee_for_seller, ctx), seller);
        //transfer nft to offerer
        transfer::public_transfer(nft,offerer);
        transfer::public_transfer(paid, offerer);
        //remove nft and offer out of their container
        object::delete(nft_in_container_id);
        object::delete(offer_in_container_id);
    }

    public entry fun make_accept_offer_with_non_listed_nft<T: key + store>(marketplace:&mut Marketplace, admin:&mut Admin, collection_fees:&mut FeeContainer, container_has_offer: &mut Container, offer_id: ID, clock: &Clock, nft: T, ctx: &mut TxContext){
        
        //seller commision
        let seller_commission:u64;
        let current_time = clock::timestamp_ms(clock);
        let offer_container_id=&mut container_has_offer.id;
        
        let Offer<Coin<SUI>>{id: offer_in_container_id, nft_id, container_id:_ , paid, offer_price, offerer, end_time} = ofield::remove(offer_container_id, offer_id);
                    
        assert!(current_time < end_time, EOfferDuration);
        assert!(nft_id == object::id(&nft), ENotTheSameNft);
         
        //FEE
        //transfer fee to seller, service fee to marketplace admin, collections fee to owner.
        let marketplace_commission_by_nft_price = collection_fee_module::get_service_fee(collection_fees, offer_price);
        //get collection_name from type T
        let collection_name = string::from_ascii(type_name::into_string(type_name::get<T>()));
        let (creator_address, creator_commision) = collection_fee_module::get_creator_fee(collection_fees, collection_name, offer_price,ctx);

        if(creator_commision > 0){
            seller_commission = offer_price - creator_commision - marketplace_commission_by_nft_price;
            //split fee for creator from balance coin that user send to offer 
            let fee_for_creator:Balance<SUI> = balance::split(coin::balance_mut(&mut paid), creator_commision);
            transfer::public_transfer(coin::from_balance(fee_for_creator, ctx), creator_address)
        }else {
            seller_commission = offer_price - marketplace_commission_by_nft_price;
        };

        let fee_for_market:Balance<SUI> = balance::split(coin::balance_mut(&mut paid), marketplace_commission_by_nft_price);
        let fee_for_seller:Balance<SUI> = balance::split(coin::balance_mut(&mut paid), seller_commission);

        /*update status of containers*/
        change_container_status(marketplace, container_has_offer, true);
        container_has_offer.objects_in_list =  container_has_offer.objects_in_list - 1;  
            
        event::emit(OwnerAcceptOfferEvent{
            nft_id: nft_id,
            offer_price: offer_price,
            seller: sender(ctx),
            new_nft_owner: offerer
        });
        /*
        Transfer fee to market admin, nft owner, collection creator
        */
        coin::join(&mut admin.pool, coin::from_balance(fee_for_market, ctx));
        admin.total_pool = admin.total_pool + marketplace_commission_by_nft_price;

        transfer::public_transfer(coin::from_balance(fee_for_seller, ctx), sender(ctx));
        //transfer nft to offerer
        transfer::public_transfer(nft, offerer);
        transfer::public_transfer(paid, offerer);
        //remove nft and offer out of their container
        object::delete(offer_in_container_id);     
    }

    /**EMERCENCY CALL*/

    /**Admin delist nft
    */
    public entry fun emergency_delist_nft<T: key + store >(marketplace: &mut Marketplace, container_has_nft:&mut Container, admin: &mut Admin, nft_id: ID, ctx:&mut TxContext){
        //get listing nft in the container
        let List<T> {id, container_id:_, seller, item, price:_} = ofield::remove(&mut container_has_nft.id, nft_id);
        //only seller can do it!
        assert!(check_sender_is_in_enable_admin_addresses(admin,ctx) == true, EWrongSeller);
        //update number of object in container
        //Notes: need emit event for this action or not?
        
        change_container_status(marketplace,container_has_nft,true);
        container_has_nft.objects_in_list = container_has_nft.objects_in_list - 1;
        //emit event delist nft
        event::emit(EventDeListNft{
            nft_id: nft_id,
            seller: seller
        });
        //tranfer item back to seller
        transfer::public_transfer(item, sender(ctx));
        object::delete(id)
    }

    public entry fun emergency_cancel_offer(marketplace: &mut Marketplace, container_has_offer: &mut Container, admin:&mut Admin, nft_id: ID, id_offer: ID, ctx: &mut TxContext){
        let container_id =&mut container_has_offer.id;
        let Offer<Coin<SUI>>{id, nft_id:_, container_id:_ , paid, offer_price: _, offerer, end_time: _} = ofield::remove(container_id,id_offer);
        assert!(check_sender_is_in_enable_admin_addresses(admin,ctx) == true, EAdminOnly);
        change_container_status(marketplace,container_has_offer,true);
        container_has_offer.objects_in_list = container_has_offer.objects_in_list - 1;
        event::emit(DeleteOfferEvent{
            offer_id: object::uid_to_inner(&id),
            nft_id: nft_id,
            offerer: offerer
        });

        transfer::public_transfer(paid, offerer);
        object::delete(id)
    }



    /*------------------------------------AUCTION-----------------------------------*/
    struct ListAuctionEvent has copy, drop {
        seller: address,
        list_id: ID,
        nft_id: ID,
        container_id: ID,
        auction_id: ID,
        start_time: u64,
        end_time: u64,
        start_price: u64,
        auction_package_id: ID
    }
    
    /***
    * @dev make_list_auction_nft : list a nft for auction
    *
    *
    * @param auction_package_id is auction id
    * @param auction is container id
    * @param container is container id
    * @param item is container id
    * @param duration_price is container id
    * @param start_time is container id
    * @param end_time is container id
    * 
    */
    public entry fun make_list_auction_nft<T: key + store>(
        auction_package_id: ID,
        auction:&mut Marketplace, 
        container:&mut Container, 
        item: T, 
        start_price: u64,
        start_time: u64,
        end_time: u64,
        ctx:&mut TxContext
    ) {
        // check max size
        if (container.objects_in_list == auction.container_maximum_size ) {
            // create new container
            let new_container = create_new_container(auction, ctx);
            let nft_id = object::id(&item);

            // create new listed
            let listing = AuctionItem<T>{
                id: object::new(ctx),
                seller: tx_context::sender(ctx),
                current_offerer :  tx_context::sender(ctx),
                container_id: object::id(&new_container),
                item: item, 
                start_price,
                current_price: 0,
                paid: coin::from_balance(balance::zero<SUI>(), ctx),
                start_time,
                end_time,            
            };
            // emit event
            event::emit(ListAuctionEvent{
                list_id: object::id(&listing),
                nft_id: nft_id,
                container_id: object::id(&new_container),
                auction_id: object::id(auction),
                seller: tx_context::sender(ctx),
                auction_package_id,
                start_time,
                end_time,
                start_price,
            });
            // add dynamic field
            ofield::add(&mut new_container.id, nft_id, listing);
            transfer::share_object(new_container);
        }
        else {
            let nft_id = object::id(&item);
            // create new listed
            let listing = AuctionItem<T>{
                id: object::new(ctx),
                seller: tx_context::sender(ctx),
                current_offerer: tx_context::sender(ctx),
                container_id: object::id(container),
                item: item, 
                start_price,
                current_price: 0,
                paid: coin::from_balance(balance::zero<SUI>(), ctx),
                start_time,
                end_time,            
            };
            // emit event
            event::emit(ListAuctionEvent{
                list_id: object::id(&listing),
                nft_id: nft_id,
                container_id: object::id(container),
                auction_id: object::id(auction),
                start_price,
                seller: tx_context::sender(ctx),
                auction_package_id,
                start_time,
                end_time
            });

            // check full
            if(container.objects_in_list + 1 == auction.container_maximum_size) {
                change_container_status(auction, container, false);
            };

            container.objects_in_list =  container.objects_in_list + 1;

            // add dynamic field
            ofield::add(&mut container.id, nft_id, listing);
        }
    }


    struct AuctionEvent has copy, drop {
        nft_id: ID,
        price: u64,
        offerer: address
    }
    /***
    * @dev make_auction : auction a nft 
    *
    *
    * @param container is container id
    * @param auction_price is price want auction
    * @param coin is coin for push into pool
    * @param nft_id is id of nft
    * @param clock for time
    * 
    */
    public entry fun make_auction<T: key + store>(
        container:&mut Container,
        coin: Coin<SUI>,
        auction_price: u64,
        nft_id: ID,
        clock: &Clock,
        ctx: &mut TxContext
    ) {
        // get listed nft
        let auction_item = ofield::borrow_mut<ID, AuctionItem<T>>(&mut container.id, nft_id);
        let current_time = clock::timestamp_ms(clock);
        // check owner
        assert!(tx_context::sender(ctx) != auction_item.seller, EWasOwned);
        // check time
        assert!(current_time >= auction_item.start_time && current_time <= auction_item.end_time, ENotInTheAuctionTime);
        // check price
        assert!(auction_price > auction_item.current_price, EPriceTooLow);
        assert!(auction_price > auction_item.start_price, EPriceTooLow);
        // send coin for old auctioner
        let current_price = auction_item.current_price;
        let old_auction_balance:Balance<SUI> = balance::split(coin::balance_mut(&mut auction_item.paid), current_price);
        transfer::public_transfer(coin::from_balance(old_auction_balance, ctx), auction_item.current_offerer);
        // push new coin to pool
        let new_auction_balance: Balance<SUI> = balance::split(coin::balance_mut(&mut coin), auction_price);
        coin::join(&mut auction_item.paid, coin::from_balance(new_auction_balance, ctx));
        // update current auction
        auction_item.current_offerer = tx_context::sender(ctx);
        auction_item.current_price = auction_price;
        // end
        transfer::public_transfer(coin, tx_context::sender(ctx));

        // event
        event::emit(AuctionEvent{
            nft_id,
            price: auction_price,
            offerer: tx_context::sender(ctx)
        });
    }

    struct DeAuctionEvent has copy, drop {
        nft_id: ID,
    }

    /***
    * @dev deauction : deauction a nft 
    *
    *
    * @param container is container id
    * @param nft_id is id of nft
    * 
    */
    public entry fun deauction<T: key + store>(
        auction: &mut Marketplace,
        container:&mut Container,
        admin: &mut Admin,
        nft_id: ID,
        ctx: &mut TxContext
    ) {
        // get listed nft
        let AuctionItem<T> { id, seller, current_offerer, container_id : _, item, start_price: _, current_price, paid, start_time: _, end_time: _} = ofield::remove<ID, AuctionItem<T>>(&mut container.id, nft_id);
        assert!(seller == tx_context::sender(ctx) || check_sender_is_in_enable_admin_addresses(admin, ctx) == true, ENotOwner);
        // current coin
        let current_auction_balance:Balance<SUI> = balance::split(coin::balance_mut(&mut paid), current_price);
        transfer::public_transfer(coin::from_balance(current_auction_balance, ctx), current_offerer);
        // transfer nft to owner
        transfer::public_transfer(item, tx_context::sender(ctx));

        // update status
        change_container_status(auction, container, true);
        container.objects_in_list = container.objects_in_list - 1;

        // destroy
        object::delete(id);
        coin::destroy_zero(paid);

        // event
        event::emit(DeAuctionEvent{
            nft_id,
        })

    }

    struct AcceptAutionEvent has copy, drop {
        nft_id: ID,
    }

    /***
    * @dev accept_auction : accept a auction 
    *
    *
    * @param container is container id
    * @param nft_id is id of nft
    * 
    */
    public entry fun accept_auction<T: key + store>(
        auction: &mut Marketplace,
        container:&mut Container,
        admin: &mut Admin,
        fee_container: &mut FeeContainer,
        nft_id: ID,
        ctx: &mut TxContext
    ) {
        // get listed nft
        let AuctionItem<T> { id, seller, current_offerer, container_id : _, item, start_price: _, current_price, paid, start_time: _, end_time: _} = ofield::remove<ID, AuctionItem<T>>(&mut container.id, nft_id);
        assert!(seller == tx_context::sender(ctx) || check_sender_is_in_enable_admin_addresses(admin, ctx) == true, ENotOwner);

        // creator fee
        let (result_address, result) = collection_fee_module::get_creator_fee(fee_container, string::from_ascii(type_name::into_string(type_name::get<T>())), current_price, ctx);
        let current_creator_fee_balance:Balance<SUI> = balance::split(coin::balance_mut(&mut paid), result);
        transfer::public_transfer(coin::from_balance(current_creator_fee_balance, ctx), result_address);


        // service fee
        let service_fee = collection_fee_module::get_service_fee(fee_container, current_price);
        let current_service_fee_balance:Balance<SUI> = balance::split(coin::balance_mut(&mut paid), service_fee);
        coin::join(&mut admin.pool, coin::from_balance(current_service_fee_balance, ctx));
        admin.total_pool = admin.total_pool + service_fee;

        // current coin
        let current_auction_balance:Balance<SUI> = balance::split(coin::balance_mut(&mut paid), current_price - service_fee - result);
        transfer::public_transfer(coin::from_balance(current_auction_balance, ctx), seller);
        // transfer nft to owner
        transfer::public_transfer(item, current_offerer);

        // update status
        change_container_status(auction, container, true);
        container.objects_in_list = container.objects_in_list - 1;

        // destroy
        object::delete(id);
        coin::destroy_zero(paid);
        
        //event 
        event::emit(AcceptAutionEvent{
            nft_id,
        })
    }



    struct AddCollectionFeeEvent has copy, drop {
        collection_name: String,
        creator_fee: u64,
    }

    // ------------------------------------------ fee ----------------------------
    /***
    * @dev add_collection_fee add fee with only admin
    *
    *
    * @param admin is admin id
    * @param fee_container is id of fee_container
    * @param creator_fee is value of fee
    * @param reciver_address is address wil receive
    * 
    */
    public entry fun add_collection_fee<T: key + store>(admin: &mut Admin, fee_container: &mut FeeContainer, creator_fee: u64, receive_address: address, ctx: &mut TxContext) {
        // check admin
        let sender = tx_context::sender(ctx);
        assert!(isAdmin(admin, sender) == true, EAdminOnly);

        // create vector param
        let names = vector::empty();
        vector::push_back(&mut names, string::from_ascii(type_name::into_string(type_name::get<T>())));
        let fees = vector::empty();
        vector::push_back(&mut fees, creator_fee);
        let receive_addresses =  vector::empty();
        vector::push_back(&mut receive_addresses, receive_address);
        // add fee
        collection_fee_module::add_collection_fee(fee_container, names, fees, receive_addresses, ctx);
        //event 
        event::emit(AddCollectionFeeEvent{
            collection_name: string::from_ascii(type_name::into_string(type_name::get<T>())),
            creator_fee,
        })
    }



    struct DeleteCollectionFeeEvent has copy, drop {
        collection_name: String,
    }

    /***
    * @dev add_collection_fee add fee with only admin
    *
    *
    * @param admin is admin id
    * @param fee_container is id of fee_container
    * 
    */
    public entry fun delete_collection_fee<T: key + store>(admin: &mut Admin, fee_container: &mut FeeContainer, ctx: &mut TxContext) {
        // check admin
        let sender = tx_context::sender(ctx);
        assert!(isAdmin(admin, sender) == true, EAdminOnly);
        // add fee
        collection_fee_module::delete_collection_fee(fee_container, string::from_ascii(type_name::into_string(type_name::get<T>())), ctx);
        //event 
        event::emit(DeleteCollectionFeeEvent{
            collection_name: string::from_ascii(type_name::into_string(type_name::get<T>())),
        })
    }

    struct UpdateCollectionFeeEvent has copy, drop {
        collection_name: String,
        creator_fee: u64
    }

    /***
    * @dev update_collection_fee add fee with only admin
    *
    *
    * @param admin is admin id
    * @param fee_container is id of fee_container
    * @param fee is fee of collection you want to update
    * 
    */
    public entry fun update_collection_fee<T: key + store>(admin: &mut Admin, fee_container: &mut FeeContainer, fee: u64, ctx: &mut TxContext) {
        // check admin
        let sender = tx_context::sender(ctx);
        assert!(isAdmin(admin, sender) == true, EAdminOnly);
        // add fee
        collection_fee_module::update_collection_fee(fee_container, string::from_ascii(type_name::into_string(type_name::get<T>())), fee, ctx);
        //event 
        event::emit(UpdateCollectionFeeEvent{
            collection_name: string::from_ascii(type_name::into_string(type_name::get<T>())),
            creator_fee: fee,
        })
    }
}   

