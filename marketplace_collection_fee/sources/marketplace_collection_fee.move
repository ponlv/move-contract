module shoshinmarketplace_collection_fee::collection_fee_module{
    use sui::object::{Self,ID,UID};
    use sui::tx_context::{Self, TxContext};
    use sui::transfer;
    use std::vector;
    use sui::dynamic_object_field as ofield;
    use sui::event;
    use std::string::{Self,String};

    //error
    const EAdminOnly:u64 = 0;
    const EFeeWrongLimit:u64 = 1;
    const ENotExisted:u64 = 2;
        
    //constant
    const DEFAULT_SERVICE_FEE:u64 = 25; // fee x 10
    const MAXIMUM_OBJECT_SIZE:u64 = 3000;

    /*Object*/
    struct FeeElement has store, drop, copy {
        collection_name: String,
        creator_fee: u64,
    }

    struct FeeContainer has key, store {
        id: UID,
        admin_address: address,
        elements: vector<ID>,
        default_service_fee: u64,
    }

    struct Fee has key, store {
        id: UID,
        fee_elements: vector<FeeElement>,
    }


    fun init(ctx: &mut TxContext) {}

    public entry fun change_admin_address(fee_container:&mut FeeContainer, new_address: address, ctx:&mut TxContext) {
        let sender = tx_context::sender(ctx);
        assert!(fee_container.admin_address == sender,EAdminOnly);
        fee_container.admin_address = new_address;
    }

    public entry fun change_default_service_fee(fee_container:&mut FeeContainer, new_service_fee: u64, ctx: &mut TxContext) {
        let sender = tx_context::sender(ctx);
        assert!(fee_container.admin_address == sender,EAdminOnly);
        fee_container.default_service_fee = new_service_fee;
    }      

    public fun create_fee_container(default_service_fee: u64, ctx: &mut TxContext) : ID {
        let sender = tx_context::sender(ctx);
        // whitelist
        let default_fee = Fee {
            id: object::new(ctx),
            fee_elements: vector::empty(),
        };

        let default_fee_id = object::id(&default_fee);

        // fee elements
        let fee_elements: vector<ID> = vector::empty();
        vector::push_back(&mut fee_elements, default_fee_id);

        // create container
        let fee_container = FeeContainer {
            id: object::new(ctx),
            admin_address: sender,
            elements: fee_elements,
            default_service_fee,
        };

        let fee_container_id = object::id(&fee_container);

        // add dynamic field
        ofield::add(&mut fee_container.id, default_fee_id, default_fee);

        // share
        transfer::share_object(fee_container);

        return fee_container_id 
    } 

    public fun existed(fee_container: &mut FeeContainer, collection_name: String): bool {
        // init 
        let existed = false;

        // get ID of fee object element
        let element_ids = fee_container.elements;

        // loop to get fee object array
        let index = 0;
        let element_length = vector::length(&element_ids);
        while(index < element_length) {
        // get object fee with dynamic field and object id
            let current_element = vector::borrow<ID>(&element_ids, index);
            let fee_element = ofield::borrow_mut<ID, Fee>(&mut fee_container.id, *current_element);

            // get fee array
            let fee_elements = fee_element.fee_elements;

            // loop array to get wallet addresse, limit, bought
            let fee_loop_index = 0;
            let current_fee_length = vector::length<FeeElement>(&fee_elements);
            while(fee_loop_index < current_fee_length) {
                // get fee in array with index
                let current_fee_element = vector::borrow<FeeElement>(&fee_elements, fee_loop_index);
                // check exist
                if (collection_name == current_fee_element.collection_name) {
                    existed = true;
                    break
                };
                fee_loop_index = fee_loop_index + 1;
            };
                
            if (existed == true) {
                break
            };

            index = index + 1;
            
        };
            
        existed
    }

    struct AddCollectionFeeEvent has copy, drop {
        collection_names: vector<String>,
        creator_fees: vector<u64>,
        service_fee: u64,
    }

    public fun add_collection_fee(fee_container: &mut FeeContainer, collection_names: vector<String>, creator_fees: vector<u64>, ctx: &mut TxContext) {
        let collection_name_lenght = vector::length(&collection_names);
        let creator_fee_lenght = vector::length(&creator_fees);
        
        // check length
        assert!(collection_name_lenght == creator_fee_lenght, EFeeWrongLimit);
        let loop_index = 0;
        // loop wallet array
        while(loop_index < collection_name_lenght) {
            // get limit and wallet
            let current_collection_name = vector::borrow<String>(&collection_names, loop_index);
            let current_fee = vector::borrow<u64>(&creator_fees, loop_index);
            // check existed
            let existed = existed(fee_container, *current_collection_name);
            if (existed == false) {
                // get focus dynamic whitelist object id
                let element_ids = fee_container.elements;
                let element_length = vector::length<ID>(&element_ids);
                let focus_fee_object_id = vector::borrow<ID>(&element_ids, element_length - 1);
                // get whitelist element
                let fee_element = ofield::borrow_mut<ID, Fee>(&mut fee_container.id, *focus_fee_object_id);

                // get whitelist array
                let current_fee_array = fee_element.fee_elements;
                let count_current_fee_array = vector::length(&current_fee_array);
                // check not maximum
                if (count_current_fee_array < MAXIMUM_OBJECT_SIZE) {
                    vector::push_back(&mut fee_element.fee_elements, FeeElement {
                    collection_name : *current_collection_name,
                    creator_fee : *current_fee,
                });
                }else {
                    // if maximum create new whitelist object
                    let fees = vector::empty();
                    vector::push_back(&mut fees, FeeElement {
                    collection_name : *current_collection_name,
                    creator_fee : *current_fee,
                    });

                    let new_fee = Fee {
                        id: object::new(ctx),
                        fee_elements: fees,
                    };
                        
                    // add dynamic field
                    let default_fee_id = object::id(&new_fee);
                    vector::push_back(&mut fee_container.elements, default_fee_id);
                    ofield::add(&mut fee_container.id, default_fee_id, new_fee); 
                };
            };
                
            loop_index = loop_index + 1;
        };

        event::emit(AddCollectionFeeEvent{
            collection_names: collection_names,
            creator_fees: creator_fees,
            service_fee: fee_container.default_service_fee,
        });
    }

    struct UpdateCollectionFeeEvent has copy, drop {
        collection_name: String,
        creator_fee: u64,
    }
    public fun update_collection_fee(fee_container: &mut FeeContainer, collection_name: String, creator_fee: u64, _: &mut TxContext) {
        // init 
        let existed = existed(fee_container, collection_name);
        assert!( existed == true ,ENotExisted);
        let is_stop = false;
        // get ID of whitelist object element
        let element_ids = fee_container.elements;

        // loop to get whitelist object array
        let index = 0;
        let element_length = vector::length<ID>(&element_ids);
        while(index < element_length) {
            // get object whitelist with dynamic field and object id
            let current_element = vector::borrow<ID>(&element_ids, index);
            let fee_element = ofield::borrow_mut<ID, Fee>(&mut fee_container.id, *current_element);
            // get whitelist array
            let fee_elements = fee_element.fee_elements;

            // loop array to get wallet addresse, limit, bought
            let fee_loop_index = 0;
            let current_fee_length = vector::length(&fee_elements);
            let new_fee = vector::empty();
            while(fee_loop_index < current_fee_length) {
                // get whitelist in array with index
                let current_fee_element = vector::pop_back(&mut fee_elements);
                // check exist
                if ( collection_name == current_fee_element.collection_name ) {
                    current_fee_element.creator_fee = creator_fee;
                    is_stop = true;
                };
                vector::push_back(&mut new_fee, current_fee_element);
                fee_loop_index = fee_loop_index + 1;
            };
            
            if (is_stop == true) {
                fee_element.fee_elements = new_fee;
                break
            };

            index = index + 1;
        };

        event::emit(UpdateCollectionFeeEvent{
            collection_name,
            creator_fee,
        });
    
    }

    struct DeleteCollectionFeeEvent has copy, drop {
        collection_name: String,
    }

    public fun delete_collection_fee(fee_container: &mut FeeContainer, collection_name: String, ctx: &mut TxContext) {
        // check admin
        let sender = tx_context::sender(ctx);
        let admin_address = fee_container.admin_address;
        assert!(admin_address == sender,EAdminOnly);
        // check existed
        let existed = existed(fee_container, collection_name);
        assert!( existed == true ,ENotExisted);
        let is_stop = false;
        // get ID of whitelist object element
        let element_ids = fee_container.elements;

        // loop to get whitelist object array
        let index = 0;
        let element_length = vector::length<ID>(&element_ids);
        while(index < element_length) {
            // get object whitelist with dynamic field and object id
            let current_element = vector::borrow<ID>(&element_ids, index);
            let fee_element = ofield::borrow_mut<ID, Fee>(&mut fee_container.id, *current_element);
            // get whitelist array
            let fee_elements = fee_element.fee_elements;

            // loop array to get wallet addresse, limit, bought
            let fee_loop_index = 0;
            let current_fee_length = vector::length(&fee_elements);
            let new_fee = vector::empty();
            while(fee_loop_index < current_fee_length) {
                // get whitelist in array with index
                let current_fee_element = vector::pop_back<FeeElement>(&mut fee_elements);
                // check exist
                if ( collection_name != current_fee_element.collection_name ) {
                    vector::push_back(&mut new_fee, current_fee_element);
                }else {
                    is_stop = true;
                };
                                
                fee_loop_index = fee_loop_index + 1;
            };
            
            if (is_stop == true) {
                fee_element.fee_elements = new_fee;
                break
            };

            index = index + 1;
        };
        event::emit(DeleteCollectionFeeEvent{
            collection_name: collection_name,
        });
    }

    public fun get_creator_fee(fee_container: &mut FeeContainer, collection_name: String, amount: u64):u64 {
        // init 
        let result = 0;
        let existed = existed(fee_container, collection_name);
        assert!( existed == true ,ENotExisted);
        if(existed == false) {
            result    
        } else {
            let is_stop = false;
            // get ID of whitelist object element
            let element_ids = fee_container.elements;

            // loop to get whitelist object array
            let index = 0;
            let element_length = vector::length<ID>(&element_ids);
            while(index < element_length) {
                // get object whitelist with dynamic field and object id
                let current_element = vector::borrow<ID>(&element_ids, index);
                let fee_element = ofield::borrow_mut<ID, Fee>(&mut fee_container.id, *current_element);
                // get whitelist array
                let fee_elements = fee_element.fee_elements;

                // loop array to get wallet addresse, limit, bought
                let fee_loop_index = 0;
                let current_fee_length = vector::length(&fee_elements);
                
                while(fee_loop_index < current_fee_length) {
                    // get whitelist in array with index
                    let current_fee_element = vector::borrow(&mut fee_elements, fee_loop_index);
                    // check exist
                    if ( collection_name == current_fee_element.collection_name ) {
                        result = current_fee_element.creator_fee * amount / 1000;
                        is_stop = true;
                    };
                    fee_loop_index = fee_loop_index + 1;
                };
                
                if (is_stop == true) {
                    break
                };

            index = index + 1;
            };
            result
        }
    }

    public fun get_service_fee(fee_container: &mut FeeContainer, amount: u64):u64 {
        fee_container.default_service_fee * amount / 1000
    }

}