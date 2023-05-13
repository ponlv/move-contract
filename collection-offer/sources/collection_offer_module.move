module shoshinwcollectionoffer::collection_offer_module{
        use sui::object::{Self,ID,UID};
        use sui::tx_context::{Self, TxContext,sender};
        use std::vector;
        use sui::transfer;
        use sui::dynamic_object_field as ofield;
        use sui::event;
        use std::type_name::{Self, TypeName};
        use sui::coin::{Self, Coin};
        use sui::balance::{Self,Balance};
        use sui::sui::SUI;
        use shoshinmarketplace::collection_fee_module::{Self,FeeContainer};
        use std::string::{Self,String};
        use sui::clock::{Self, Clock};


        /**ERRORS*/
        const EAdminOnly:u64 = 0;
        const EWasNotOwner:u64 = 7001;
        const EEnoguhOffer:u64 = 7002;
        const EAcceptEnded:u64 = 7003;

        struct Admin has key {
                id: UID,
                admins: vector<address>,
                pool: Coin<SUI>,
                total_pool: u64,
        }

        struct Status has store, drop {
                id: ID,
                can_deposit: bool
        }

        struct CollectionOffer has key {
                id: UID,
                containers: vector<Status>,
                container_maximum_size: u64,
        }


        struct Container has key { 
                id: UID,
                count: u64,
        }

        struct CollectionOfferPool has key, store {
                id: UID,
                collection: TypeName,
                container_id: ID,
                owner: address,
                pool: Coin<SUI>,
                total_pool: u64,
                price_per_item: u64,
                total_item_offer: u64,
                accepted: u64,
                duration: u64,
        }
        

        fun init(ctx:&mut TxContext) {
                let sender = tx_context::sender(ctx);
                let addresses = vector::empty();
                vector::push_back(&mut addresses, sender);
                let admin = Admin{
                id: object::new(ctx),
                        admins: addresses,
                        pool: coin::from_balance(balance::zero<SUI>(), ctx),
                        total_pool: 0,
                };

        
                let collectionOffer = CollectionOffer{
                        id: object::new(ctx),
                        containers: vector::empty(),
                        container_maximum_size: 100,
                };

                let container = Container{
                        id: object::new(ctx),
                        count: 0      
                };


                transfer::share_object(container);
                transfer::share_object(admin);
                transfer::share_object(collectionOffer)
        }


        /***
        * @dev add_admin
        *
        *
        * @param admin is admin id
        * @param addresses
        * 
        */
        public entry fun add_admin(admin:&mut Admin, addresses: vector<address>, ctx:&mut TxContext){
                let sender = sender(ctx);
                //admin only
                assert!(isAdmin(admin, sender) == true, EAdminOnly);

                vector::append(&mut admin.admins, addresses);
        }


        /***
        * @dev remove_admin
        *
        *
        * @param admin is admin id
        * @param delete_address
        * 
        */
        public entry fun remove_admin(admin:&mut Admin, delete_address: address, ctx:&mut TxContext){
                // check admin
                let sender = tx_context::sender(ctx);
                assert!(isAdmin(admin, sender) == true, EAdminOnly);

                let index = 0;
                let admins = admin.admins;
                let admins_length = vector::length(&admins);
                let current_index = 0;
                let is_existed = false;
                while(index < admins_length) {
                        if(*vector::borrow(&admins, index) == delete_address) {
                                is_existed = true;
                                current_index = index;
                        };

                        index = index + 1;
                };

                if(is_existed == true) {
                        vector::remove(&mut admins, current_index);
                };
        }

        /***
        * @dev isAdmin
        *
        *
        * @param admin is admin id
        * @param new_address
        * 
        */
        public fun isAdmin(admin: &mut Admin, address : address) : bool {
                let rs = false;
                let list = admin.admins;

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

        /***
        * @dev create_new_container
        *
        *
        * @param collectionOffer is collection offer id
        * 
        */
        fun create_new_container(collectionOffer:&mut CollectionOffer, ctx:&mut TxContext):Container {
                
                let new_container = Container{
                        id: object::new(ctx),
                        count: 1
                };
                
                //deposit new container in container list 
                vector::push_back(&mut collectionOffer.containers, Status{
                        id: object::id(&new_container),
                        can_deposit: true
                });
                
                return new_container
        }

        /***
        * @dev change_container_status
        *
        *
        * @param collectionOffer is collection offer id
        * @param container is container id
        * @param status is container status 
        * 
        */
        public fun change_container_status(collectionOffer:&mut CollectionOffer, container: &mut Container, status : bool) {
                
                let containers = &mut collectionOffer.containers;
                let length = vector::length(containers);
                let index = 0;
                while(index < length){
                        let current_container = vector::borrow_mut(containers, index);
                        if(current_container.id == object::id(container)){
                                current_container.can_deposit = status;
                                break
                        };
                        index = index + 1;
                };
        }


        struct MakeOfferCollectionEvent has copy, drop {
                collection_offer_id: ID,
                container: ID,
                total_item_offer: u64,
                price_per_item: u64,
                duration: u64,
        }

        /***
        * @dev make_offer_collection
        *
        *
        * @param collectionOffer is collection offer id
        * @param container is container id
        * @param coin is coin object
        * @param total_item_offer is total item
        * @param price_per_item is price per item
        * 
        */
        public entry fun make_offer_collection<T: store + key>(
                collectionOffer: &mut CollectionOffer, 
                container: &mut Container, 
                duration: u64,
                total_item_offer: u64,  
                price_per_item: u64,
                coin: Coin<SUI>,
                ctx:&mut TxContext
        ) {
                let sender = tx_context::sender(ctx);
                if(container.count >= collectionOffer.container_maximum_size) {
                        let new_container = create_new_container(collectionOffer, ctx);
                        let offer_balance: Balance<SUI> = balance::split(coin::balance_mut(&mut coin), price_per_item * total_item_offer);
                        let collectionOfferPool = CollectionOfferPool {
                                id: object::new(ctx),
                                collection: type_name::get<T>(),
                                container_id: object::id(&new_container),
                                owner: sender,
                                pool: coin::from_balance(offer_balance, ctx),
                                total_pool: price_per_item * total_item_offer,
                                price_per_item,
                                total_item_offer,
                                accepted: 0,
                                duration,
                        };
                        event::emit(MakeOfferCollectionEvent{
                                collection_offer_id: object::id(&collectionOfferPool),
                                container: object::id(&new_container),
                                total_item_offer,
                                price_per_item,
                                duration,
                        });

                        ofield::add(&mut new_container.id, object::id(&collectionOfferPool), collectionOfferPool);
                        transfer::share_object(new_container);
                }else {
                        let offer_balance: Balance<SUI> = balance::split(coin::balance_mut(&mut coin), price_per_item * total_item_offer);
                        let collectionOfferPool = CollectionOfferPool {
                                id: object::new(ctx),
                                collection: type_name::get<T>(),
                                container_id: object::id(container),
                                owner: sender,
                                pool: coin::from_balance(offer_balance, ctx),
                                total_pool: price_per_item * total_item_offer,
                                price_per_item,
                                total_item_offer,
                                accepted: 0,
                                duration,
                        };     

                        event::emit(MakeOfferCollectionEvent{
                                collection_offer_id: object::id(&collectionOfferPool),
                                container: object::id(container),
                                total_item_offer,
                                price_per_item,
                                duration,
                        });
                        // check full
                        if(container.count + 1 == collectionOffer.container_maximum_size) {
                                change_container_status(collectionOffer, container, false);
                        };
                        container.count =  container.count + 1;
                        ofield::add(&mut container.id, object::id(&collectionOfferPool), collectionOfferPool);
                };
                transfer::public_transfer(coin, sender);
        }

        struct CancelOfferEvent has copy, drop {
                collection_offer_id: ID,
        }


        /***
        * @dev make_cancel_offer_collection
        *
        * 
        */
        public entry fun make_cancel_offer_collection<T: store + key>(
                collectionOffer: &mut CollectionOffer, 
                container: &mut Container, 
                collection_offer_id: ID,
                admin: &mut Admin,
                ctx:&mut TxContext,
        ) {
                let sender = tx_context::sender(ctx);
                let CollectionOfferPool{
                        id,
                        collection: _,
                        container_id: _,
                        owner,
                        pool,
                        total_pool,
                        price_per_item: _,
                        total_item_offer: _,
                        accepted: _,
                        duration: _,
                } = ofield::remove(&mut container.id, collection_offer_id);

                assert!(sender == owner || isAdmin(admin, sender) == true, EWasNotOwner);

                let current_collection_offer_balance:Balance<SUI> = balance::split(coin::balance_mut(&mut pool), total_pool);
                transfer::public_transfer(coin::from_balance(current_collection_offer_balance, ctx), owner);
                
                change_container_status(collectionOffer, container, true);
                container.count = container.count - 1;

                object::delete(id);
                coin::destroy_zero(pool);

                event::emit(CancelOfferEvent{
                        collection_offer_id,
                })
        }

        public fun check_enough(                
                container: &mut Container, 
                collection_offer_id: ID
        ):bool {
                let rs;
                let CollectionOfferPool{
                        id: _,
                        collection: _,
                        container_id: _,
                        owner: _,
                        pool: _,
                        total_pool: _,
                        price_per_item: _,
                        total_item_offer,
                        accepted,
                        duration: _,
                } = ofield::borrow(&mut container.id, collection_offer_id);

                if(*total_item_offer - *accepted == 1) {
                        rs = true;
                } else {
                        rs = false;
                };
                rs
        }

        struct MakeAcceptCollectionEvent has copy, drop {
                collection_offer_id: ID,
                nft_id: ID,
                accepter: address,
                price: u64,
        }

        /***
        * @dev make_offer_collection
        *
        *
        * @param collectionOffer is collection offer id
        * @param container is container id
        * @param coin is coin object
        * @param collection_offer_id is collection offer id
        * @param item is nft
        * 
        */
        public entry fun make_accept_collection_offer<T: store + key>(  
                admin: &mut Admin,     
                fee_container: &mut FeeContainer,         
                collectionOffer: &mut CollectionOffer, 
                container: &mut Container, 
                collection_offer_id: ID,
                item: T,
                clock: &Clock,
                ctx:&mut TxContext
        ) {
                let check = check_enough(container, collection_offer_id);
                if(check == false) {
                        let sender = tx_context::sender(ctx);
                        let CollectionOfferPool{
                                id: _,
                                collection: _,
                                container_id: _,
                                owner,
                                pool,
                                total_pool,
                                price_per_item,
                                total_item_offer,
                                accepted,
                                duration,
                        } = ofield::borrow_mut(&mut container.id, collection_offer_id);

                        assert!(*accepted < *total_item_offer, EEnoguhOffer);
                        let current_time = clock::timestamp_ms(clock);
                        assert!(current_time <= *duration, EAcceptEnded);


                        event::emit(MakeAcceptCollectionEvent{
                                collection_offer_id,
                                nft_id: object::id(&item),
                                accepter: sender,
                                price: *price_per_item,
                        });

                        let (result_address, result) = collection_fee_module::get_creator_fee(fee_container, string::from_ascii(type_name::into_string(type_name::get<T>())), *price_per_item, ctx);
                        let current_creator_fee_balance:Balance<SUI> = balance::split(coin::balance_mut(pool), result);
                        transfer::public_transfer(coin::from_balance(current_creator_fee_balance, ctx), result_address);


                        let service_fee = collection_fee_module::get_service_fee(fee_container, *price_per_item);
                        let current_service_fee_balance:Balance<SUI> = balance::split(coin::balance_mut(pool), service_fee);
                        coin::join(&mut admin.pool, coin::from_balance(current_service_fee_balance, ctx));
                        admin.total_pool = admin.total_pool + service_fee;

                        let offer_balance:Balance<SUI> = balance::split(coin::balance_mut(pool), *price_per_item - service_fee - result);
                        transfer::public_transfer(coin::from_balance(offer_balance, ctx), sender);

                        transfer::public_transfer(item, *owner);
                        *accepted = *accepted + 1;
                        *total_pool = *total_pool - *price_per_item;
                } else {
                        let sender = tx_context::sender(ctx);
                        let CollectionOfferPool{
                                id,
                                collection: _,
                                container_id: _,
                                owner,
                                pool,
                                total_pool: _,
                                price_per_item,
                                total_item_offer,
                                accepted,
                                duration,
                        } = ofield::remove(&mut container.id, collection_offer_id);

                        assert!(accepted < total_item_offer, EEnoguhOffer);
                        let current_time = clock::timestamp_ms(clock);
                        assert!(current_time <= duration, EAcceptEnded);

                        event::emit(MakeAcceptCollectionEvent{
                                collection_offer_id,
                                nft_id: object::id(&item),
                                accepter: sender,
                                price: price_per_item,
                        });

                        let (result_address, result) = collection_fee_module::get_creator_fee(fee_container, string::from_ascii(type_name::into_string(type_name::get<T>())), price_per_item, ctx);
                        let current_creator_fee_balance:Balance<SUI> = balance::split(coin::balance_mut(&mut pool), result);
                        transfer::public_transfer(coin::from_balance(current_creator_fee_balance, ctx), result_address);

                        let service_fee = collection_fee_module::get_service_fee(fee_container, price_per_item);
                        let current_service_fee_balance:Balance<SUI> = balance::split(coin::balance_mut(&mut pool), service_fee);
                        coin::join(&mut admin.pool, coin::from_balance(current_service_fee_balance, ctx));
                        admin.total_pool = admin.total_pool + service_fee;


                        let offer_balance:Balance<SUI> = balance::split(coin::balance_mut(&mut pool), price_per_item - service_fee - result);
                        transfer::public_transfer(coin::from_balance(offer_balance, ctx), sender);

                        transfer::public_transfer(item, owner);
                        change_container_status(collectionOffer, container, true);
                        container.count = container.count - 1;

                        object::delete(id);
                        coin::destroy_zero(pool);
                };
        }

        /***
        * @dev withdraw : withdraw coin
        *
        *
        * @param launchpad launchpad project
        * @param admin admin id
        * @param receive_address address to get sui
        * 
        */
        public entry fun withdraw(admin: &mut Admin, receive_address: address, ctx: &mut TxContext) {
                let sender = sender(ctx);
                //admin only
                assert!(isAdmin(admin, sender) == true, EAdminOnly);
                let money:Balance<SUI> = balance::split(coin::balance_mut(&mut admin.pool), admin.total_pool);
                transfer::public_transfer(coin::from_balance(money, ctx), receive_address);
                admin.total_pool = 0;
        }



        public entry fun existed<T: store + key>(
                admin: &mut Admin,
                collectionOffer: &mut CollectionOffer, 
                container: &mut Container, 
                collection_offer_id: ID,
                ctx:&mut TxContext
        ) {
                let sender = tx_context::sender(ctx);
                assert!(isAdmin(admin, sender) == true, EAdminOnly);

                let CollectionOfferPool{
                        id,
                        collection: _,
                        container_id: _,
                        owner,
                        pool,
                        total_pool,
                        price_per_item: _,
                        total_item_offer: _,
                        accepted: _,
                        duration: _,
                } = ofield::remove(&mut container.id, collection_offer_id);

                let current_collection_offer_balance:Balance<SUI> = balance::split(coin::balance_mut(&mut pool), total_pool);
                transfer::public_transfer(coin::from_balance(current_collection_offer_balance, ctx), owner);
                
                change_container_status(collectionOffer, container, true);
                container.count = container.count - 1;

                object::delete(id);
                coin::destroy_zero(pool);

                event::emit(CancelOfferEvent{
                        collection_offer_id,
                })
        }

}