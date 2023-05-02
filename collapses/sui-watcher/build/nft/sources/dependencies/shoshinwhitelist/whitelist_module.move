module shoshinwhitelist::whitelist_module{
        use sui::object::{Self,ID,UID};
        use sui::tx_context::{Self, TxContext};
        use sui::transfer;
        use std::vector;
        use sui::dynamic_object_field as ofield;
        use sui::event;



        const MAXIMUM_OBJECT_SIZE:u64 = 1000;

        const EAdminOnly:u64 = 0;
        const EWhitelistWrongLimit:u64 = 1;
        const ENotExisted:u64 = 2;
        const ENotAvailable:u64 = 3;



        struct WhiteListElement has store, drop, copy {
                wallet_address: address,
                limit: u64,
                bought: u64,
        }

        struct WhitelistContainer has key, store {
                id: UID,
                admin_address: address,
                owner: ID,
                elements: vector<ID>
        }

        struct Whitelist has key, store {
                id: UID,
                whitelist_elements: vector<WhiteListElement>,
        }


        fun init(_: &mut TxContext) {}


        /***
        * @dev change_admin_addresses : change admin address
        *
        * @param whitelist_container the whitelist you want to focus
        * @param new_address new address
        *
        */
        public entry fun change_admin_addresses(whitelist_container:&mut WhitelistContainer, new_address: address, ctx:&mut TxContext){
                let sender = tx_context::sender(ctx);
                assert!(whitelist_container.admin_address == sender,EAdminOnly);
                whitelist_container.admin_address = new_address;
        }


        
        /***
        * @dev create_whitelist_conatiner : create a whitelist container for save all whitelist address
        *
        */
        public fun create_whitelist_conatiner(owner: ID, ctx: &mut TxContext): ID {
                let sender = tx_context::sender(ctx);

                // whitelist
                let default_whitelist = Whitelist {
                        id: object::new(ctx),
                        whitelist_elements: vector::empty(),
                };

                let default_whitelist_id = object::id(&default_whitelist);

                // whitelist container
                let whitelist_elements: vector<ID> = vector::empty();
                // push default whitelist object id into to container whitelist object
                vector::push_back(&mut whitelist_elements, default_whitelist_id);
                let whitelist_container = WhitelistContainer {
                        id: object::new(ctx),
                        admin_address: sender,
                        elements: whitelist_elements,
                        owner,
                };
                let whitelist_container_id = object::id(&whitelist_container);
                // add dynamic object into container object
                ofield::add(&mut whitelist_container.id, default_whitelist_id, default_whitelist); 

                // share
                transfer::share_object(whitelist_container);

                whitelist_container_id
        }


        /***
        * @dev create_whitelist_conatiner : create a whitelist container for save all whitelist address
        *
        * @param whitelist_container the whitelist you want to focus
        * @param wallet the address you want to focus
        * 
        */
        public fun existed(whitelist_container: &mut WhitelistContainer, wallet: address): bool {
                // init 
                let existed = false;

                // get ID of whitelist object element
                let element_ids = whitelist_container.elements;

                // loop to get whitelist object array
                let index = 0;
                let element_length = vector::length(&element_ids);
                while(index < element_length) {
                        // get object whitelist with dynamic field and object id
                        let current_element = vector::borrow<ID>(&element_ids, index);
                        let whitelist_element = ofield::borrow_mut<ID, Whitelist>(&mut whitelist_container.id, *current_element);

                        // get whitelist array
                        let whitelist_elements = whitelist_element.whitelist_elements;

                        // loop array to get wallet addresse, limit, bought
                        let whitelist_loop_index = 0;
                        let current_whitelist_length = vector::length<WhiteListElement>(&whitelist_elements);
                        while(whitelist_loop_index < current_whitelist_length) {
                                // get whitelist in array with index
                                let current_whitelist_element = vector::borrow<WhiteListElement>(&whitelist_elements, whitelist_loop_index);
                                // check exist
                                if (wallet == current_whitelist_element.wallet_address) {
                                        existed = true;
                                        break
                                };
                                whitelist_loop_index = whitelist_loop_index + 1;
                        };
                        if (existed == true) {
                                break
                        };

                        index = index + 1;
                };
                existed
        }

        /***
        * @dev create_whitelist_conatiner : create a whitelist container for save all whitelist address
        *
        * @param whitelist_container the whitelist you want to focus
        * @param next_value after boght + next value
        * @param wallet wallet want check
        * @is_public unlimit
        * 
        */
        public fun available_whitelist(whitelist_container: &mut WhitelistContainer, next_value: u64, wallet: address, is_no_limit: bool): bool {
                // init 
                let available = false;
                let is_stop = false;

                // get ID of whitelist object element
                let element_ids = whitelist_container.elements;

                // loop to get whitelist object array
                let index = 0;
                let element_length = vector::length<ID>(&element_ids);
                while(index < element_length) {
                        // get object whitelist with dynamic field and object id
                        let current_element = vector::borrow<ID>(&element_ids, index);
                        let whitelist_element = ofield::borrow_mut<ID, Whitelist>(&mut whitelist_container.id, *current_element);

                        // get whitelist array
                        let whitelist_elements = whitelist_element.whitelist_elements;

                        // loop array to get wallet addresse, limit, bought
                        let whitelist_loop_index = 0;
                        let current_whitelist_length = vector::length<WhiteListElement>(&whitelist_elements);
                        while(whitelist_loop_index < current_whitelist_length) {
                                // get whitelist in array with index
                                let current_whitelist_element = vector::borrow<WhiteListElement>(&whitelist_elements, whitelist_loop_index);
                                // check exist
                                if (wallet == current_whitelist_element.wallet_address) {
                                        if (is_no_limit == true || current_whitelist_element.bought + next_value <=  current_whitelist_element.limit) {
                                                available = true;
                                        };
                                        is_stop = true;
                                        break
                                };
                                whitelist_loop_index = whitelist_loop_index + 1;
                        };
                        if (available == true || is_stop == true) {
                                break
                        };

                        index = index + 1;
                };
                available
        }



        struct AddWhitelistEvent has copy, drop {
                round_id: ID,
                wallets: vector<address>,
                limits: vector<u64>,
                boughts: vector<u64>,
        }

        /***
        * @dev add_whitelist : add more whitelist
        *
        * @param wallets all wallets want add
        * @param limits the maximum buy for every whitelist
        * 
        */
        public fun add_whitelist(whitelist_container: &mut WhitelistContainer, wallets: vector<address>, limits: vector<u64>, ctx: &mut TxContext) {
                let wallets_lenght = vector::length(&wallets);
                let limits_lenght = vector::length(&limits);
                // check length
                assert!(wallets_lenght == limits_lenght, EWhitelistWrongLimit);
                let loop_index = 0;
                // loop wallet array
                while(loop_index < wallets_lenght) {
                        // get limit and wallet
                        let current_wallet = vector::borrow<address>(&wallets, loop_index);
                        let current_limit = vector::borrow<u64>(&limits, loop_index);
                        // check existed
                        let existed = existed(whitelist_container, *current_wallet);
                        if (existed == false) {
                                // get focus dynamic whitelist object id
                                let element_ids = whitelist_container.elements;
                                let element_length = vector::length<ID>(&element_ids);
                                let focus_whitelist_object_id = vector::borrow<ID>(&element_ids, element_length - 1);
                                // get whitelist element
                                let whitelist_element = ofield::borrow_mut<ID, Whitelist>(&mut whitelist_container.id, *focus_whitelist_object_id);

                                // get whitelist array
                                let current_whitelist_array = whitelist_element.whitelist_elements;
                                let count_current_whitelist_array = vector::length(&current_whitelist_array);
                                // check not maximum
                                if (count_current_whitelist_array < MAXIMUM_OBJECT_SIZE) {
                                        vector::push_back(&mut whitelist_element.whitelist_elements, WhiteListElement {
                                                wallet_address : *current_wallet,
                                                limit : *current_limit,
                                                bought : 0,

                                        });
                                }else {
                                        // if maximum create new whitelist object
                                        let whitelists = vector::empty();
                                        vector::push_back(&mut whitelists, WhiteListElement {
                                                wallet_address : *current_wallet,
                                                limit : *current_limit,
                                                bought : 0,

                                        });
                                        let new_whitelist = Whitelist {
                                                id: object::new(ctx),
                                                whitelist_elements: whitelists,
                                        };
                                        // add dynamic field
                                        let default_whitelist_id = object::id(&new_whitelist);
                                        vector::push_back(&mut whitelist_container.elements, default_whitelist_id);
                                        ofield::add(&mut whitelist_container.id, default_whitelist_id, new_whitelist); 
                                };
                        };
                        loop_index = loop_index + 1;
                };

                let boughts:vector<u64> = vector::empty();

                event::emit(AddWhitelistEvent{
                        round_id: whitelist_container.owner,
                        wallets,
                        limits,
                        boughts,
                });
        }

        public fun add_whitelist_with_bought(whitelist_container: &mut WhitelistContainer, wallets: vector<address>, limits: vector<u64>, boughts: vector<u64>, ctx: &mut TxContext) {
                let wallets_lenght = vector::length(&wallets);
                let limits_lenght = vector::length(&limits);
                let boughts_lenght = vector::length(&boughts);
                // check length
                assert!(wallets_lenght == limits_lenght || boughts_lenght == wallets_lenght, EWhitelistWrongLimit);
                let loop_index = 0;
                // loop wallet array
                while(loop_index < wallets_lenght) {
                        // get limit and wallet
                        let current_wallet = vector::borrow<address>(&wallets, loop_index);
                        let current_limit = vector::borrow<u64>(&limits, loop_index);
                        let current_bought = vector::borrow<u64>(&boughts, loop_index);
                        // check existed
                        let existed = existed(whitelist_container, *current_wallet);
                        if (existed == false) {
                                // get focus dynamic whitelist object id
                                let element_ids = whitelist_container.elements;
                                let element_length = vector::length<ID>(&element_ids);
                                let focus_whitelist_object_id = vector::borrow<ID>(&element_ids, element_length - 1);
                                // get whitelist element
                                let whitelist_element = ofield::borrow_mut<ID, Whitelist>(&mut whitelist_container.id, *focus_whitelist_object_id);

                                // get whitelist array
                                let current_whitelist_array = whitelist_element.whitelist_elements;
                                let count_current_whitelist_array = vector::length(&current_whitelist_array);
                                // check not maximum
                                if (count_current_whitelist_array < MAXIMUM_OBJECT_SIZE) {
                                        vector::push_back(&mut whitelist_element.whitelist_elements, WhiteListElement {
                                                wallet_address : *current_wallet,
                                                limit : *current_limit,
                                                bought : *current_bought,

                                        });
                                }else {
                                        // if maximum create new whitelist object
                                        let whitelists = vector::empty();
                                        vector::push_back(&mut whitelists, WhiteListElement {
                                                wallet_address : *current_wallet,
                                                limit : *current_limit,
                                                bought : *current_bought,

                                        });
                                        let new_whitelist = Whitelist {
                                                id: object::new(ctx),
                                                whitelist_elements: whitelists,
                                        };
                                        // add dynamic field
                                        let default_whitelist_id = object::id(&new_whitelist);
                                        vector::push_back(&mut whitelist_container.elements, default_whitelist_id);
                                        ofield::add(&mut whitelist_container.id, default_whitelist_id, new_whitelist); 
                                };
                        };
                        loop_index = loop_index + 1;
                };

                event::emit(AddWhitelistEvent{
                        round_id: whitelist_container.owner,
                        wallets,
                        limits,
                        boughts,
                });
        }

        struct DeleteWhitelistEvent has copy, drop {
                round_id: ID,
                wallet: address,
        }

        /***
        * @dev delete_wallet_in_whitelist : delete wallet in whitelist
        *
        * @param whitelist_container the whitelist you want to focus
        * @param wallet wallet want delete
        * 
        */
        public fun delete_wallet_in_whitelist(whitelist_container: &mut WhitelistContainer, wallet: address, ctx: &mut TxContext) {
                // check admin
                let sender = tx_context::sender(ctx);
                let admin_address = whitelist_container.admin_address;
                assert!(admin_address == sender,EAdminOnly);
                // check existed
                let existed = existed(whitelist_container, wallet);
                assert!( existed == true ,ENotExisted);
                let is_stop = false;
                // get ID of whitelist object element
                let element_ids = whitelist_container.elements;

                // loop to get whitelist object array
                let index = 0;
                let element_length = vector::length<ID>(&element_ids);
                let delete_focus_index = 0;
                while(index < element_length) {
                        // get object whitelist with dynamic field and object id
                        let current_element = vector::borrow<ID>(&element_ids, index);
                        let whitelist_element = ofield::borrow_mut<ID, Whitelist>(&mut whitelist_container.id, *current_element);
                        // get whitelist array
                        let whitelist_elements = whitelist_element.whitelist_elements;

                        // loop array to get wallet addresse, limit, bought
                        let whitelist_loop_index = 0;
                        let current_whitelist_length = vector::length(&whitelist_elements);
                        while(whitelist_loop_index < current_whitelist_length) {
                                // get whitelist in array with index
                                let current_whitelist_element = vector::borrow<WhiteListElement>(&mut whitelist_elements, whitelist_loop_index);
                                // check exist
                                if ( wallet == current_whitelist_element.wallet_address ) {
                                        delete_focus_index = whitelist_loop_index;
                                        is_stop = true;
                                };
                                
                                whitelist_loop_index = whitelist_loop_index + 1;
                        };
                        if (is_stop == true) {
                                vector::remove(&mut whitelist_element.whitelist_elements, delete_focus_index);
                                break
                        };

                        index = index + 1;
                };
                event::emit(DeleteWhitelistEvent{
                        round_id: whitelist_container.owner,
                        wallet,
                });
        }

        /***
        * @dev update_whitelist : uodate wallet bought
        *
        * @param whitelist_container the whitelist you want to focus
        * @param next_value how many item will be buy
        * @param wallet wallet want delete
        * @param is_no_limit is not limit
        * 
        */
        public fun update_whitelist(whitelist_container: &mut WhitelistContainer, next_value: u64, wallet: address, is_no_limit: bool,_: &mut TxContext) {
                // init 
                let available = available_whitelist(whitelist_container, next_value, wallet, is_no_limit);
                assert!( available == true, ENotAvailable);
                let existed = existed(whitelist_container, wallet);
                assert!( existed == true ,ENotExisted);
                let is_stop = false;
                // get ID of whitelist object element
                let element_ids = whitelist_container.elements;

                // loop to get whitelist object array
                let index = 0;
                let element_length = vector::length<ID>(&element_ids);
                let focus_update_index = 0;
                while(index < element_length) {
                        // get object whitelist with dynamic field and object id
                        let current_element = vector::borrow<ID>(&element_ids, index);
                        let whitelist_element = ofield::borrow_mut<ID, Whitelist>(&mut whitelist_container.id, *current_element);
                        // get whitelist array
                        let whitelist_elements = whitelist_element.whitelist_elements;

                        // loop array to get wallet addresse, limit, bought
                        let whitelist_loop_index = 0;
                        let current_whitelist_length = vector::length(&whitelist_elements);
                        while(whitelist_loop_index < current_whitelist_length) {
                                // get whitelist in array with index
                                let current_whitelist_element = vector::borrow_mut(&mut whitelist_elements, whitelist_loop_index);
                                // check exist
                                if ( wallet == current_whitelist_element.wallet_address ) {
                                        focus_update_index = whitelist_loop_index;
                                        is_stop = true;
                                };
                                whitelist_loop_index = whitelist_loop_index + 1;
                        };
                        if (is_stop == true) {
                                let current_element = vector::remove(&mut whitelist_element.whitelist_elements, focus_update_index);
                                current_element.bought = current_element.bought + 1;
                                vector::push_back(&mut whitelist_element.whitelist_elements, current_element);
                                break
                        };

                        index = index + 1;
                };


        }


}