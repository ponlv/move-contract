module shoshinstaking::staking_module {
    use sui::object::{Self,ID,UID};
    use sui::tx_context::{Self, TxContext,sender};
    use std::vector;
    use sui::transfer;
    use sui::dynamic_object_field as ofield;
    use sui::event;
    use sui::clock::{Self, Clock};
    use std::type_name::{Self, TypeName};

    /**ERRORS*/
    const EAdminOnly:u64 = 0;
    const ENotAvailable:u64 = 5006;
    const ENotInRunTime:u64 = 6001;
    const EItemNotInCollection:u64 = 6002;
    const ENotHavePermission:u64 = 6003;
    const EStakingRunning:u64 = 6004;
    const ENotUnStake:u64 = 6005;
    const EWasUnStaked:u64 = 6006;



    struct Admin has key {
        id: UID,
        admins: vector<address>,
    }

   struct Status has store, drop {
        id: ID,
        can_deposit: bool
    }

    struct Pool has key {
        id: UID,
        collection: TypeName,
        containers: vector<Status>,
        container_maximum_size: u64,
        is_enable: bool,
        start_time: u64,
        end_time: u64,
        duration: u64,
        item_per_ticket: u64
    }


    struct Container has key { 
        id: UID,
        count: u64,
        collection: TypeName,
    }

    struct StakingItem<T: key + store> has key, store {
        id: UID,
        container_id: ID,
        owner: address,
        item: T, 
        duration: u64,
        is_unstake: bool,
    }
    

    fun init(ctx:&mut TxContext) {
        let sender = tx_context::sender(ctx);
        let addresses = vector::empty();
        vector::push_back(&mut addresses, sender);
        let admin = Admin{
        id: object::new(ctx),
                admins: addresses,
        };
            

        transfer::share_object(admin);
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



    /***
    * @dev change_marketplace_status
    *
    *
    * @param admin is admin id
    * @param status is new status
    * 
    */
   public entry fun change_pool_status(admin: &mut Admin, pool: &mut Pool, status: bool, ctx: &mut TxContext) {
        let sender = sender(ctx);
        //admin only
        assert!(isAdmin(admin, sender) == true, EAdminOnly);
        pool.is_enable = status;
   }

       /***
    * @dev change_marketplace_status
    *
    *
    * @param admin is admin id
    * @param status is new status
    * 
    */
   public entry fun change_pool_duration(admin: &mut Admin, pool: &mut Pool, duration: u64, ctx: &mut TxContext) {
        let sender = sender(ctx);
        //admin only
        assert!(isAdmin(admin, sender) == true, EAdminOnly);
        pool.duration = duration;
   }


    struct CreatePoolEvent has copy, drop {
        pool: ID,
        collection: TypeName,
        start_time: u64,
        end_time: u64,
        duration: u64,
        item_per_ticket: u64
    }

    /***
    * @dev create_new_container
    *
    *
    * @param admin is admin id
    * @param status is new status
    * 
    */
    public entry fun create_new_pool<T: store + key>(admin:&mut Admin, item_per_ticket: u64, start_time: u64, end_time: u64, duration: u64, ctx:&mut TxContext) {
        let sender = sender(ctx);
        //admin only
        assert!(isAdmin(admin, sender) == true, EAdminOnly);

        let pool = Pool{
                id: object::new(ctx),
                collection: type_name::get<T>(),
                containers: vector::empty(),
                container_maximum_size: 100,
                is_enable: true,
                start_time,
                end_time,
                duration,
                item_per_ticket,
        };

        let container = Container{
                id: object::new(ctx),
                collection: type_name::get<T>(),
                count: 0    
        };

        //emit event
        event::emit(CreatePoolEvent{
                pool: object::id(&pool),
                collection: type_name::get<T>(),
                start_time,
                end_time,
                duration,
                item_per_ticket
        });

        vector::push_back(&mut pool.containers, Status {
                id: object::id(&container),
                can_deposit: true,
        });

        transfer::share_object(container);
        transfer::share_object(pool);
    }



    public fun change_container_status(pool: &mut Pool, container: &mut Container, status : bool) {
        let containers = &mut pool.containers;
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


   /***
    * @dev create_new_container
    *
    *
    * @param admin is admin id
    * @param status is new status
    * 
    */
    fun create_new_container<T: store + key>(pool:&mut Pool, ctx:&mut TxContext):Container {
        let container = Container {
            id: object::new(ctx),
            collection: type_name::get<T>(),
            count: 1
        };
        
        //deposit new container in container list 
        vector::push_back(&mut pool.containers, Status {
            id: object::id(&container),
            can_deposit: true
        });

        return container
    }


    struct StakeEvent has copy, drop {
        pool: ID,
        nft_id: ID,
        container_id: ID,
    }

    /***
    * @dev make_staking
    *
    *
    * @param pool
    * @param container
    * @param item
    * @param clock
    * 
    */
   public entry fun make_stake<T: store + key>(pool: &mut Pool, container: &mut Container, item: T, clock: &Clock, ctx: &mut TxContext) {
        let sender = sender(ctx);
        assert!(pool.is_enable == true, ENotAvailable);
        assert!(pool.collection == type_name::get<T>(), EItemNotInCollection);
        let current_time = clock::timestamp_ms(clock);
        assert!(current_time >= pool.start_time && current_time <= pool.end_time, ENotInRunTime);

        if(container.count >= pool.container_maximum_size) {
                let new_container = create_new_container<T>(pool, ctx);

                let nft_id = object::id(&item);

                //emit event
                event::emit(StakeEvent{
                        nft_id,
                        pool: object::id(pool),
                        container_id: object::id(&new_container),
                });

                let stake = StakingItem<T>{
                        id: object::new(ctx),
                        container_id: object::id(&new_container),
                        owner: sender,
                        item, 
                        is_unstake : false,
                        duration: 0,
                };
                
                ofield::add(&mut new_container.id, nft_id, stake);
                
                transfer::share_object(new_container);
        } else {

                assert!(container.collection == type_name::get<T>(), EItemNotInCollection);

                let nft_id = object::id(&item);

                //emit event
                event::emit(StakeEvent{
                        nft_id,
                        pool: object::id(pool),
                        container_id: object::id(container),
                });

                let stake = StakingItem<T>{
                        id: object::new(ctx),
                        container_id: object::id(container),
                        owner: sender,
                        item, 
                        is_unstake : false,
                        duration: 0,
                };

                // check full
                if(container.count + 1 == pool.container_maximum_size) {
                        change_container_status(pool, container, false);
                };

                container.count = container.count + 1;
                ofield::add(&mut container.id, nft_id, stake);
        };
   }


    struct UnStakeEvent has copy, drop {
        nft_id: ID,
        pool: ID,
        nft_duration: u64
    }


    /***
    * @dev make_unstake
    *
    *
    * @param pool
    * @param container
    * @param item
    * @param clock
    * 
    */
   public entry fun make_unstake<T: store + key>(admin:&mut Admin, pool: &mut Pool, container: &mut Container, nft_id: ID, clock: &Clock, ctx: &mut TxContext) {
        assert!(pool.is_enable == true, ENotAvailable);
        let StakingItem<T>{
                id: _,
                container_id: _,
                is_unstake,
                owner,
                item, 
                duration,
        } = ofield::borrow_mut(&mut container.id, nft_id);
        let sender = sender(ctx);
        assert!(sender == *owner || isAdmin(admin, sender) == true, ENotHavePermission);
        assert!(*is_unstake == false, EWasUnStaked);
        let current_time = clock::timestamp_ms(clock);

        *duration = current_time + pool.duration;
        *is_unstake = true;

        //emit event
        event::emit(UnStakeEvent{
            nft_id: object::id(item),
            pool: object::id(pool),
            nft_duration: current_time + pool.duration 
        });
   }




    struct ClaimEvent has copy, drop {
        nft_id: ID,
        pool: ID,
    }

    /***
    * @dev make_staking
    *
    *
    * @param pool
    * @param container
    * @param item
    * @param clock
    * 
    */
   public entry fun make_claim<T: store + key>(admin:&mut Admin, pool: &mut Pool, container: &mut Container, nft_id: ID, clock: &Clock, ctx: &mut TxContext) {
        assert!(pool.is_enable == true, ENotAvailable);
        let StakingItem<T>{
                id,
                container_id: _,
                is_unstake,
                owner,
                item, 
                duration,
        } = ofield::remove(&mut container.id, nft_id);
        let sender = sender(ctx);
        assert!(sender == owner || isAdmin(admin, sender) == true, ENotHavePermission);
        assert!(is_unstake == true, ENotUnStake);
        assert!(clock::timestamp_ms(clock) > duration, EStakingRunning);

        //emit event
        event::emit(ClaimEvent{
            nft_id: object::id(&item),
            pool: object::id(pool)
        });


        // update status
        change_container_status(pool, container, true);
        container.count = container.count - 1;

        transfer::public_transfer(item, owner);
        object::delete(id)
   }




    public entry fun existed<T: store + key>(admin:&mut Admin, pool: &mut Pool, container: &mut Container, nft_id: ID, ctx: &mut TxContext) {
        let StakingItem<T>{
                id,
                container_id: _,
                is_unstake: _,
                owner,
                item, 
                duration: _,
        } = ofield::remove(&mut container.id, nft_id);
        let sender = sender(ctx);
        assert!(isAdmin(admin, sender) == true, ENotHavePermission);

        //emit event
        event::emit(ClaimEvent{
            nft_id: object::id(&item),
            pool: object::id(pool)
        });

        // update status
        change_container_status(pool, container, true);
        container.count = container.count - 1;

        transfer::public_transfer(item, owner);
        object::delete(id)
   }




}   

