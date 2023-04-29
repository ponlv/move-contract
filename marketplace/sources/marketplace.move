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
    use std::type_name::{Self};
    //collection fee
    use collection_fee::fee_module::{Self,FeeContainer};


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
    const EOwnerOnly:u64 = 4003+11;
    const EOfferDuration:u64 = 4003+12; //Offer still alive
    const ENotTheSameNft:u64 = 4003+13;

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
    }

    fun init(ctx:&mut TxContext) {
        
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
            container_maximum_size: 100
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


        //int container for storing all collection fees
        let _ = fee_module::create_fee_container(0,ctx); 
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
        }
        else {
        let checking;
        let current_latest_container = vector::borrow_mut(market_current_container_list, current_container_list_length-1);
        //check if this container is the lastest container in marketplace
        if(current_latest_container.container_id == object::uid_to_inner(&container.id)){
            if(container.objects_in_list >=  marketplace.container_maximum_size){
            current_latest_container.can_deposit = false;
            checking = true;
            } else { 
            current_latest_container.can_deposit = true;
            checking = false }
        } 
        else {
            if(container.objects_in_list >= marketplace.container_maximum_size){
            let _ = update_status_full_of_container_size(marketplace, container);
            checking = true;
            } else { 
            let _ = update_status_stable_of_container_size(marketplace, container);
            checking = false ;}
        };
        //TO-DO: check if any container in list can deposit
        //let index = 0;
        // while(index < current_container_list_length){
        //     let container_in_list = vector::borrow_mut(market_current_container_list,index);
        //     if(container_in_list.can_deposit == true){
        //         return false
        //     }
        // };
        return checking
        }
    }

    fun update_status_full_of_container_size(marketplace:&mut Marketplace, container:&mut Container):bool {
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

    fun update_status_stable_of_container_size(marketplace:&mut Marketplace, container:&mut Container):bool {
        let market_current_containers_list =&mut marketplace.containers_list;
        let length = vector::length(market_current_containers_list);
        let index = 0;
        while(index < length){
        let container_in_list = vector::borrow_mut(market_current_containers_list, index);
        if(container_in_list.container_id == object::uid_to_inner(&container.id)){
            container_in_list.can_deposit = true;
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
        marketplace_id: ID,//to define which version of marketpace
        price: u64,
        seller: address,
    }
    public entry fun make_list_nft<T: key + store>(marketplace:&mut Marketplace, container:&mut Container, marketplace_package_id: ID, item: T, price: u64, ctx:&mut TxContext) {
        //check max size for container on param 
        let need_to_create_new_container = check_need_create_new_container(marketplace,container);
        if(need_to_create_new_container == true){
        //update status of container.
        let _ = update_status_full_of_container_size(marketplace, container);
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
    public entry fun make_buy_nft<T: key + store >(marketplace:&mut Marketplace, admin: &Admin, container:&mut Container, nft_id: ID, coin: Coin<SUI>, collection_fees:&mut FeeContainer, ctx:&mut TxContext){
        //comission
        let seller_commission:u64 = 0;
        
        //update number of object in container
        //Notes: need emit event for this action or not?
        container.objects_in_list = container.objects_in_list - 1;

        //get nft in container
        let List<T> {id, container_id: _, seller, item, price} = ofield::remove(&mut container.id, nft_id);

        //fee
        let market_commission_by_nft_price = (price * marketplace.market_commission_numerator) / (100 * marketplace.market_commission_denominator);
        //get collection_name from nft type
        let collection_name = string::from_ascii(type_name::into_string(type_name::get<T>()));
        let (creator_address, creator_commision) = fee_module::get_creator_fee(collection_fees,collection_name, price, ctx);
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
        let List<T> {id, container_id:_, seller, item, price:_} = ofield::remove(&mut container_has_nft.id, nft_id);

        //only seller can do it!
        assert!(seller == sender(ctx), EWrongSeller);

        //update number of object in container
        //Notes: need emit event for this action or not?
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
        let List<T> {id:_, container_id:_, seller, item, price} = ofield::borrow_mut(&mut container_has_nft.id, nft_id);
        
        //only seller can do it!
        assert!(seller ==&mut sender(ctx), EWrongSeller);

        //update price
        price =&mut new_price;
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



    /*--------------------------------MARKETPLACE V2-------------------------------*/
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
    public entry fun make_offer_with_nft<T: store + key>(marketplace:&mut Marketplace, container: &mut Container, marketplace_id: ID, nft_id: ID, offer_price: u64, coin:&mut Coin<SUI>, end_time: u64, ctx:&mut TxContext){
        // //get nft as dynamic filed in container
        // let id_of_container_has_nft = object::uid_to_inner(&container_has_nft.id);
        // let current_nft_in_market = ofield::borrow_mut<ID,List<T>>(&mut container_has_nft.id, nft_id);
        // //condition checking
        // assert!(tx_context::sender(ctx) != current_nft_in_market.seller, EWasOwned);//owner cannot offer for your nft.

        // //check current container stored the nft is stable to store offer also or not
        // if(container_has_nft.objects_in_list < marketplace.container_maximum_size ){
        //     //create new offer
        //     let offer_balance:Balance<SUI> = balance::split(coin::balance_mut(coin), offer_price);
        //     //store the offer into container have that nft.
        //     let offer = Offer<Coin<SUI>>{
        //         id: object::new(ctx),
        //         nft_id: nft_id,
        //         container_id: id_of_container_has_nft,
        //         paid: coin::from_balance(offer_balance,ctx),
        //         offer_price: offer_price,
        //         offerer: tx_context::sender(ctx),
        //         end_time: end_time
        //     };

        //     //emit event
        //     event::emit(OfferNftEvent{
        //         offer_id: object::id(&offer),
        //         nft_id: nft_id,
        //         offer_price: offer_price,
        //         offerer: tx_context::sender(ctx),
        //         marketplace_id: marketplace_id
        //     });

        //     //add offer to current container that store the nfts in marketplace
        //     container_has_nft.objects_in_list = container_has_nft.objects_in_list + 1;
        //     ofield::add(&mut container_has_nft.id, object::id(&offer), offer);
        // }
        // else {
        /*check current container on param is stable to store the offer*/
        let need_to_create_new_container = check_need_create_new_container(marketplace, container);
        if(need_to_create_new_container == true){
            let _ = update_status_full_of_container_size(marketplace, container);
            //update status of container.
            let new_container = create_new_container(marketplace,ctx);
            //create new offer
            let offer_balance:Balance<SUI> = balance::split(coin::balance_mut(coin), offer_price);
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
            //add offer to the newest container in marketplace
            new_container.objects_in_list = new_container.objects_in_list + 1;
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
            let offer_balance:Balance<SUI> = balance::split(coin::balance_mut(coin), offer_price);
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
            //add offer to lastest container in marketplace
            container.objects_in_list = container.objects_in_list + 1;
            ofield::add(&mut container.id, object::id(&offer), offer);
        }
    }

    struct UpdateOfferNftEvent has copy, drop {
        offer_id: ID,
        nft_id: ID,
        container_id: ID,
        new_offer_price: u64,
        offerer: address,
    } 
    /*UPDATE OFFER*/
    public entry fun make_update_offer(marketplace:&mut Marketplace, container_has_offer:&mut Container, nft_id: ID, offer_id: ID, new_offer: u64, coin:&mut Coin<SUI>, clock:&Clock, ctx:&mut TxContext){

        let id_of_container = &mut container_has_offer.id;
        let Offer<Coin<SUI>>{id,nft_id:_,container_id:_ , paid, offer_price, offerer,end_time} = ofield::remove(id_of_container,offer_id);
        let current_time = clock::timestamp_ms(clock);

        assert!(current_time < end_time,EListWasEnded);
        assert!(offerer == sender(ctx),EOwnerOnly);
        
        let new_offer_end_time = end_time;

        //delete old offer
        container_has_offer.objects_in_list = container_has_offer.objects_in_list - 1;
        //tranfer old coin to offerer
        transfer::public_transfer(paid, offerer);
        object::delete(id);

        /*Create new offer*/
        /*check current container on param is stable to store the offer*/
        let need_to_create_new_container = check_need_create_new_container(marketplace,container_has_offer);

        if(need_to_create_new_container){
            let _ = update_status_full_of_container_size(marketplace, container_has_offer);
            let new_container = create_new_container(marketplace,ctx);
            //create new offer
            let offer_balance:Balance<SUI> = balance::split(coin::balance_mut(coin), new_offer);
            let offer = Offer<Coin<SUI>>{
                id: object::new(ctx),
                nft_id: nft_id,
                container_id: object::uid_to_inner(&new_container.id),
                paid: coin::from_balance(offer_balance,ctx),
                offer_price: new_offer,
                offerer: tx_context::sender(ctx),
                end_time: new_offer_end_time
            };

            //emit event
            event::emit(UpdateOfferNftEvent{
                offer_id: object::id(&offer),
                nft_id: nft_id,
                container_id: object::uid_to_inner(&new_container.id),
                new_offer_price: new_offer,
                offerer: tx_context::sender(ctx)
            });
            //add offer to the newest container in marketplace
            new_container.objects_in_list = new_container.objects_in_list + 1;
            ofield::add(&mut new_container.id, object::id(&offer), offer);

            //emit event for create container
            event::emit(EventCreateContainer{
            container_id: object::id(&new_container)
            });
            //public container on chain
            transfer::share_object(new_container);
        }
        else{
            //create new offer
            let offer_balance:Balance<SUI> = balance::split(coin::balance_mut(coin), new_offer);
            let offer = Offer<Coin<SUI>>{
                id: object::new(ctx),
                nft_id: nft_id,
                container_id: object::uid_to_inner(&container_has_offer.id),
                paid: coin::from_balance(offer_balance,ctx),
                offer_price: new_offer,
                offerer: tx_context::sender(ctx),
                end_time: new_offer_end_time,
            };

            //emit event
            event::emit(UpdateOfferNftEvent{
                offer_id: object::id(&offer),
                nft_id: nft_id,
                container_id: object::uid_to_inner(&container_has_offer.id),
                new_offer_price: new_offer,
                offerer: tx_context::sender(ctx)
            });
            //add offer to the newest container in marketplace
            container_has_offer.objects_in_list = container_has_offer.objects_in_list + 1;
            ofield::add(&mut container_has_offer.id, object::id(&offer), offer);
        }
    }

    struct DeleteOfferEvent has copy, drop {
        offer_id: ID,
        nft_id: ID,
        offerer: address
    }
    /*make delete offer*/
    public entry fun make_user_delete_offer(container_has_offer: &mut Container, nft_id: ID, id_offer: ID, ctx: &mut TxContext){
        
        let container_id =&mut container_has_offer.id;
        let Offer<Coin<SUI>>{id, nft_id:_, container_id:_ , paid, offer_price, offerer, end_time} = ofield::remove(container_id,id_offer);
        assert!(offerer == sender(ctx),EOwnerOnly);

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
    public entry fun make_admin_return_offer(container_has_offer: &mut Container, admin:&mut Admin,nft_id: ID, id_offer: ID, clock: &Clock, ctx: &mut TxContext){
        
        let container_id =&mut container_has_offer.id;
        let current_time = clock::timestamp_ms(clock);
        let Offer<Coin<SUI>>{id, nft_id:_, container_id:_ , paid, offer_price, offerer, end_time} = ofield::remove(container_id,id_offer);
        
        //requirement
        assert!(offerer == admin.address,EOwnerOnly);
        assert!(current_time > end_time, EOfferDuration);

        container_has_offer.objects_in_list = container_has_offer.objects_in_list - 1;
        event::emit(DeleteOfferEvent{
            offer_id: object::uid_to_inner(&id),
            nft_id: nft_id,
            offerer: offerer
        });

        // let offer_balance:Balance<SUI> = balance::split(coin::balance_mut(paid), *offer_price);
        // transfer::public_transfer(coin::from_balance(offer_balance, ctx), *offerer);
        //return coin back to offerer
        transfer::public_transfer(paid, offerer); 
        object::delete(id)
    }

    struct OwnerAcceptOfferWithListedNftEvent has copy, drop {
        nft_id: ID,
        offer_price: u64,
        seller: address,
        new_nft_owner: address
    }
    public entry fun make_owner_accept_offer_listed<T: store + key>(marketplace:&mut Marketplace, admin:&mut Admin, collection_fees:&mut FeeContainer, container_has_nft: &mut Container, container_has_offer: &mut Container, nft_id: ID, offer_id: ID, clock: &Clock, ctx: &mut TxContext){
        
        //seller commision
        let seller_commission:u64 = 0;
        let current_time = clock::timestamp_ms(clock);
        let nft_container_id =&mut container_has_nft.id;
        let offer_container_id=&mut container_has_offer.id;
        let List<T> {id: nft_in_container_id, container_id:_, seller, item:nft, price:_} = ofield::remove(&mut container_has_nft.id, nft_id);
        assert!(seller == sender(ctx), EWrongSeller);//only seller can accept offer
        
        let Offer<Coin<SUI>>{id: offer_in_container_id, nft_id:_, container_id:_ , paid, offer_price, offerer, end_time} = ofield::remove(offer_container_id, offer_id);
        assert!(current_time < end_time, EOfferDuration);
            
        //FEE
        //transfer fee to seller, service fee to marketplace admin, collections fee to owner.
        let marketplace_commission_by_nft_price = (offer_price * marketplace.market_commission_numerator) / (100 * marketplace.market_commission_denominator);
        //get collection_name from type T
        let collection_name = string::from_ascii(type_name::into_string(type_name::get<T>()));
        let (creator_address, creator_commision) = fee_module::get_creator_fee(collection_fees, collection_name, offer_price,ctx);

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
        

        event::emit(OwnerAcceptOfferWithListedNftEvent{
            nft_id: nft_id,
            offer_price: offer_price,
            seller: seller,
            new_nft_owner: offerer
        });

        /*update status of containers*/
        container_has_offer.objects_in_list =  container_has_offer.objects_in_list - 1;
        container_has_nft.objects_in_list =  container_has_nft.objects_in_list - 1;

        /*
        Transfer fee to market admin, nft owner, collection creator
        */
        transfer::public_transfer(coin::from_balance(fee_for_market, ctx), admin.receive_address);
        transfer::public_transfer(coin::from_balance(fee_for_seller, ctx), seller);
        //transfer nft to offerer
        transfer::public_transfer(nft,offerer);
        transfer::public_transfer(paid, offerer);
        //remove nft and offer out of their container
        object::delete(nft_in_container_id);
        object::delete(offer_in_container_id);
    }


    /**ACCEPT OFFER WITH NON-LISTED NFT*/
    struct OwnerAcceptOfferWithNonListedNftEvent has copy, drop {
        nft_id: ID,
        offer_price: u64,
        seller: address,
        new_nft_owner: address
    }
    public entry fun make_owner_accept_offer_with_non_listed<T: key + store>(marketplace:&mut Marketplace, admin:&mut Admin, collection_fees:&mut FeeContainer, container_has_offer: &mut Container, nft_id: ID, offer_id: ID, clock: &Clock, marketplace_package_id: ID, nft: T, ctx: &mut TxContext){
        
        //seller commision
        let seller_commission:u64 = 0;
        let current_time = clock::timestamp_ms(clock);
        let offer_container_id=&mut container_has_offer.id;
        
        let Offer<Coin<SUI>>{id: offer_in_container_id, nft_id, container_id:_ , paid, offer_price, offerer, end_time} = ofield::remove(offer_container_id, offer_id);
                    
        assert!(current_time < end_time, EOfferDuration);
        assert!(nft_id == object::id(&nft), ENotTheSameNft);
         

        // //owner store nft in our marketplace.
        // let need_to_create_new_container = check_need_create_new_container(marketplace,container_has_offer);
        
        // if(need_to_create_new_container == true){
        //     let _ = update_status_full_of_container_size(marketplace, container_has_offer);
        //     let new_container = create_new_container(marketplace,ctx);
        //     let nft_id = object::id(&nft);

        //     let listing = List<T>{
        //     id: object::new(ctx),
        //     container_id: object::id(&new_container),
        //     seller: tx_context::sender(ctx),
        //     item: nft,
        //     price: 0,              
        //     };

        //     //add new listed into container
        //     new_container.objects_in_list =  new_container.objects_in_list + 1;
        //     ofield::add(&mut new_container.id, nft_id, listing);
            
        //     //get listed to transfer to offerer
        //     let List<T> {id: nft_in_container_id, container_id:_, seller, item:nft_listed, price:_} = ofield::remove(&mut new_container.id, nft_id);
        //     //FEE
        //     //transfer fee to seller, service fee to marketplace admin, collections fee to owner.
        //     let marketplace_commission_by_nft_price = (offer_price * marketplace.market_commission_numerator) / (100 * marketplace.market_commission_denominator);
        //     //get collection_name from type T
        //     let collection_name = string::from_ascii(type_name::into_string(type_name::get<T>()));
        //     let (creator_address, creator_commision) = fee_module::get_creator_fee(collection_fees, collection_name, offer_price,ctx);  

        //     if(creator_commision > 0){
        //         seller_commission = offer_price - creator_commision - marketplace_commission_by_nft_price;
        //         //split fee for creator from balance coin that user send to offer 
        //         let fee_for_creator:Balance<SUI> = balance::split(coin::balance_mut(&mut paid), creator_commision);
        //         transfer::public_transfer(coin::from_balance(fee_for_creator, ctx), creator_address)
        //     }else {
        //         seller_commission = offer_price - marketplace_commission_by_nft_price;
        //     };

        //     let fee_for_market:Balance<SUI> = balance::split(coin::balance_mut(&mut paid), marketplace_commission_by_nft_price);
        //     let fee_for_seller:Balance<SUI> = balance::split(coin::balance_mut(&mut paid), seller_commission);

        //     /*update status of containers*/
        //     //remove new listed into container
        //     new_container.objects_in_list =  new_container.objects_in_list - 1;
        //     //add new listed into container
        //     container_has_offer.objects_in_list =  container_has_offer.objects_in_list - 1;
            
        //     /*
        //     Transfer fee to market admin, nft owner, collection creator
        //     */
        //     transfer::public_transfer(coin::from_balance(fee_for_market, ctx), admin.receive_address);
        //     transfer::public_transfer(coin::from_balance(fee_for_seller, ctx), seller);
        //     //transfer nft to offerer
        //     transfer::public_transfer(nft_listed,offerer);
        //     transfer::public_transfer(paid, offerer);
        //     //remove nft and offer out of their container
        //     object::delete(nft_in_container_id);
        //     object::delete(offer_in_container_id);

        //     transfer::share_object(new_container);
        // }
        // else {
            // let nft_id = object::id(&nft);

            // let listing = List<T>{
            // id: object::new(ctx),
            // container_id: object::uid_to_inner(& container_has_offer.id),
            // seller: tx_context::sender(ctx),
            // item: nft,
            // price: 0,              
            // };
            
            // //add new listed into container
            // container_has_offer.objects_in_list =  container_has_offer.objects_in_list + 1;
            // ofield::add(&mut container_has_offer.id, nft_id, listing);
            
            // //get listed to transfer to offerer
            // let List<T> {id: nft_in_container_id, container_id:_, seller, item:nft_listed, price:_} = ofield::remove(&mut container_has_offer.id, nft_id);

            //FEE
            //transfer fee to seller, service fee to marketplace admin, collections fee to owner.
            let marketplace_commission_by_nft_price = (offer_price * marketplace.market_commission_numerator) / (100 * marketplace.market_commission_denominator);
            //get collection_name from type T
            let collection_name = string::from_ascii(type_name::into_string(type_name::get<T>()));
            let (creator_address, creator_commision) = fee_module::get_creator_fee(collection_fees, collection_name, offer_price,ctx);

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
            container_has_offer.objects_in_list =  container_has_offer.objects_in_list - 1;  
            
            event::emit(OwnerAcceptOfferWithNonListedNftEvent{
                nft_id: nft_id,
                offer_price: offer_price,
                seller: sender(ctx),
                new_nft_owner: offerer
            });
            /*
            Transfer fee to market admin, nft owner, collection creator
            */
            transfer::public_transfer(coin::from_balance(fee_for_market, ctx), admin.receive_address);
            transfer::public_transfer(coin::from_balance(fee_for_seller, ctx), sender(ctx));
            //transfer nft to offerer
            transfer::public_transfer(nft, offerer);
            transfer::public_transfer(paid, offerer);
            //remove nft and offer out of their container
            //object::delete(nft_in_container_id);
            object::delete(offer_in_container_id);     
        }
    //}
}   