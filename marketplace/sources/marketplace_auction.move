module shoshinmarketplace::marketplace_module {
    use sui::object::{Self,ID,UID};
    use sui::tx_context::{Self, TxContext};
    use std::vector;
    use sui::transfer;
    use sui::dynamic_object_field as ofield;
    use std::string::{Self};
    use sui::event;
    use sui::clock::{Self, Clock};
    use sui::coin::{Self, Coin};
    use sui::balance::{Self,Balance};
    use sui::sui::SUI;
    //std
    use std::type_name::{Self};
    //collection fee
    use  shoshinmarketplace::collection_fee_module::{Self,FeeContainer};

    //error
    const EAdminOnly:u64 = 4003;
    const ENotInTheAuctionTime:u64 = 5001;
    const EPriceTooLow:u64 = 5002;
    const ENotOwner:u64 = 5003;
    const EMaximumSize:u64 = 5004;
    const EWasOwned:u64 = 5005;

    const MAXIMUN_OBJECT_SIZE:u64 = 3;

    struct Admin has key {
        id: UID,
        address: address,
        receive_address: address
    }

    struct ContainerStatus has store, drop {
        id: ID,
        can_deposit: bool
    }

    struct Auction has key {
        id: UID,
        container_maximum_size: u64,
        collection_fee_container_id: ID,
        containers: vector<ContainerStatus>,
    }


    struct Container has key { 
        id: UID,
        count: u64
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
        
        let admin = Admin{
            id: object::new(ctx),
            address: tx_context::sender(ctx),
            receive_address: tx_context::sender(ctx),
        };

        let collection_fee_container_id = collection_fee_module::create_fee_container(25 ,ctx);

        //the first container of marketplace.
        let container = Container{
            id: object::new(ctx),
            count: 0      
        };

        let auction = Auction {
            id: object::new(ctx),
            container_maximum_size: MAXIMUN_OBJECT_SIZE,
            collection_fee_container_id,
            containers: vector::empty()
        };

        //deposit new container in container list 
        vector::push_back(&mut auction.containers, ContainerStatus{
            id: object::id(&container),
            can_deposit: true
        });


        transfer::share_object(container);
        transfer::share_object(admin);
        transfer::share_object(auction)
    }
    


    struct EventCreateContainer has copy, drop {
        container_id: ID
    }


    /***
    * @dev create_new_container : create project
    *
    *
    * @param auction is auction id
    * 
    */
    fun create_new_container(auction: &mut Auction, ctx:&mut TxContext):Container {
        // create container
        let container = Container{
            id: object::new(ctx),
            count: 1
        };

        //deposit new container in container list 
        vector::push_back(&mut auction.containers, ContainerStatus{
            id: object::id(&container),
            can_deposit: true
        });

        //emit event
        event::emit(EventCreateContainer {
            container_id: object::id(&container)
        });
        // return
        return container
    }

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


    public fun change_container_status(auction:&mut Auction, container: &mut Container, status : bool) {
        let containers = &mut auction.containers;
        let length = vector::length(containers);
        let index = 0;
        while(index < length){
        let current_container = vector::borrow_mut(containers, index);
            if(current_container.id == object::uid_to_inner(&container.id)){
                current_container.can_deposit = status;
                break
            };
            index = index + 1;
        };
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
        auction:&mut Auction, 
        container:&mut Container, 
        item: T, 
        start_price: u64,
        start_time: u64,
        end_time: u64,
        ctx:&mut TxContext
    ) {
        // check max size
        if (container.count == auction.container_maximum_size ) {
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
            if(container.count + 1 == auction.container_maximum_size) {
                change_container_status(auction, container, false);
            };

            container.count =  container.count + 1;

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
        assert!(tx_context::seller != auction_item.seller, EWasOwned);
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
        auction: &mut Auction,
        container:&mut Container,
        admin: &mut Admin,
        nft_id: ID,
        ctx: &mut TxContext
    ) {
        // get listed nft
        let AuctionItem<T> { id, seller, current_offerer, container_id : _, item, start_price: _, current_price, paid, start_time: _, end_time: _} = ofield::remove<ID, AuctionItem<T>>(&mut container.id, nft_id);
        assert!(seller == tx_context::sender(ctx) || tx_context::sender(ctx) == admin.address, ENotOwner);
        // current coin
        let current_auction_balance:Balance<SUI> = balance::split(coin::balance_mut(&mut paid), current_price);
        transfer::public_transfer(coin::from_balance(current_auction_balance, ctx), current_offerer);
        // transfer nft to owner
        transfer::public_transfer(item, tx_context::sender(ctx));

        // update status
        change_container_status(auction, container, true);
        container.count = container.count - 1;

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
        auction: &mut Auction,
        container:&mut Container,
        admin: &mut Admin,
        fee_container: &mut FeeContainer,
        nft_id: ID,
        ctx: &mut TxContext
    ) {
        // get listed nft
        let AuctionItem<T> { id, seller, current_offerer, container_id : _, item, start_price: _, current_price, paid, start_time: _, end_time: _} = ofield::remove<ID, AuctionItem<T>>(&mut container.id, nft_id);
        assert!(seller == tx_context::sender(ctx) || tx_context::sender(ctx) == admin.address, ENotOwner);

        // creator fee
        let (result_address, result) = collection_fee_module::get_creator_fee(fee_container, string::from_ascii(type_name::into_string(type_name::get<T>())), current_price, ctx);
        let current_creator_fee_balance:Balance<SUI> = balance::split(coin::balance_mut(&mut paid), result);
        transfer::public_transfer(coin::from_balance(current_creator_fee_balance, ctx), result_address);


        // service fee
        let service_fee = collection_fee_module::get_service_fee(fee_container, current_price);
        let current_service_fee_balance:Balance<SUI> = balance::split(coin::balance_mut(&mut paid), service_fee);
        transfer::public_transfer(coin::from_balance(current_service_fee_balance, ctx), admin.receive_address);

        // current coin
        let current_auction_balance:Balance<SUI> = balance::split(coin::balance_mut(&mut paid), current_price - service_fee - result);
        transfer::public_transfer(coin::from_balance(current_auction_balance, ctx), seller);
        // transfer nft to owner
        transfer::public_transfer(item, current_offerer);

        // update status
        change_container_status(auction, container, true);
        container.count = container.count - 1;

        // destroy
        object::delete(id);
        coin::destroy_zero(paid);
        
        //event 
        event::emit(AcceptAution{
            nft_id,
        })
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
        assert!(sender == admin.address, EAdminOnly);

        // create vector param
        let names = vector::empty();
        vector::push_back(&mut names, string::from_ascii(type_name::into_string(type_name::get<T>())));
        let fees = vector::empty();
        vector::push_back(&mut fees, creator_fee);
        let receive_addresses =  vector::empty();
        vector::push_back(&mut receive_addresses, receive_address);
        // add fee
        collection_fee_module::add_collection_fee(fee_container, names, fees, receive_addresses, ctx);
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
        assert!(sender == admin.address, EAdminOnly);
        // add fee
        collection_fee_module::delete_collection_fee(fee_container, string::from_ascii(type_name::into_string(type_name::get<T>())), ctx);
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
        assert!(sender == admin.address, EAdminOnly);
        // add fee
        collection_fee_module::update_collection_fee(fee_container, string::from_ascii(type_name::into_string(type_name::get<T>())), fee, ctx);
    }

}   