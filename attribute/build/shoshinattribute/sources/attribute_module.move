module shoshinattribute::attribute_module{
        use sui::object::{Self,ID,UID};
        use sui::tx_context::{Self, TxContext};
        use sui::transfer;
        use std::vector;
        use sui::vec_map::{Self, VecMap};
        use sui::dynamic_object_field as ofield;
        use std::string::{Self,String};

        const EAdminOnly:u64 = 0;
        const EAttributeWrongLimit:u64 = 1;
        const ENotExisted:u64 = 2;
        

        const DEFAULT_SERVICE_FEE:u64 = 25; // fee x 10
        const MAXIMUM_OBJECT_SIZE:u64 = 3000;



        struct AttributeContainer has key, store {
                id: UID,
                admin_address: address,
                elements: vector<ID>,
        }

        struct Attribute has key, store {
                id: UID,
                attributes: vector<VecMap<String, String>>
        }


        fun init(_: &mut TxContext) {}

        public entry fun change_admin_address(attribute_container:&mut AttributeContainer, new_address: address, ctx:&mut TxContext) {
                let sender = tx_context::sender(ctx);
                assert!(attribute_container.admin_address == sender,EAdminOnly);
                attribute_container.admin_address = new_address;
        }   

        public fun create_attribute_container(ctx: &mut TxContext) : ID {
                let sender = tx_context::sender(ctx);
                // whitelist
                let default_attribute = Attribute {
                        id: object::new(ctx),
                        attributes: vector::empty(),
                };

                let default_attribute_id = object::id(&default_attribute);

                // fee elements
                let attribute_elements: vector<ID> = vector::empty();
                vector::push_back(&mut attribute_elements, default_attribute_id);

                // create container
                let attribute_container = AttributeContainer {
                        id: object::new(ctx),
                        admin_address: sender,
                        elements: attribute_elements,
                };
                let attributecontainer_id = object::id(&attribute_container);

                // add dynamic field
                ofield::add(&mut attribute_container.id, default_attribute_id, default_attribute);

                // share
                transfer::share_object(attribute_container);

                attributecontainer_id 
        } 

        public fun push_attributes(attribute_container: &mut AttributeContainer, attribute_keys: vector<vector<String>>,attribute_values: vector<vector<String>>, ctx: &mut TxContext) {
                let attribute_keys_lenght = vector::length(&attribute_keys);
                let attribute_values_lenght = vector::length(&attribute_values);
                // check length
                assert!(attribute_keys_lenght == attribute_values_lenght, EAttributeWrongLimit);
                let loop_index = 0;
                // loop wallet array
                while(loop_index < attribute_keys_lenght) {
                        // get limit and wallet
                        let current_attribute_key = vector::remove<vector<String>>(&mut attribute_keys, loop_index);
                        let current_attribute_value = vector::remove<vector<String>>(&mut attribute_values, loop_index);
                        let current_map_value: VecMap<String, String> = vec_map::empty();

                        let vec_map_length = vector::length(&current_attribute_key);
                        let map_index = 0;
                        
                        while(map_index < vec_map_length) {
                                vec_map::insert(&mut current_map_value, vector::pop_back(&mut current_attribute_key), vector::pop_back(&mut current_attribute_value));
                                map_index = map_index + 1;
                        };

                        // get focus dynamic whitelist object id
                        let element_ids = attribute_container.elements;
                        let element_length = vector::length<ID>(&element_ids);
                        let focus_attribute_object_id = vector::borrow<ID>(&element_ids, element_length - 1);
                        // get whitelist element
                        let attribute_element = ofield::borrow_mut<ID, Attribute>(&mut attribute_container.id, *focus_attribute_object_id);

                        // get whitelist array
                        let current_attribute_array = attribute_element.attributes;
                        let count_current_attribute_array = vector::length(&current_attribute_array);
                        // check not maximum
                        if (count_current_attribute_array < MAXIMUM_OBJECT_SIZE) {
                                vector::push_back(&mut attribute_element.attributes, current_map_value);
                        }else {
                                // if maximum create new whitelist object
                                let attributes = vector::empty();
                                vector::push_back(&mut attribute_element.attributes, current_map_value);
                                let new_attribute = Attribute {
                                        id: object::new(ctx),
                                        attributes: attributes,
                                };
                                // add dynamic field
                                let default_attribute_id = object::id(&new_attribute);
                                vector::push_back(&mut attribute_container.elements, default_attribute_id);
                                ofield::add(&mut attribute_container.id, default_attribute_id, new_attribute); 
                        };
                        loop_index = loop_index + 1;
                };
        }

        public fun pop_attributes(attribute_container: &mut AttributeContainer):VecMap<String, String> {
                let results = vec_map::empty();
                // get ID of whitelist object element
                let element_ids = attribute_container.elements;

                // loop to get whitelist object array
                let index = 0;
                let element_length = vector::length<ID>(&element_ids);
                while(index < element_length) {
                        // get object whitelist with dynamic field and object id
                        let current_element = vector::borrow<ID>(&element_ids, index);
                        let attribute_element = ofield::borrow_mut<ID, Attribute>(&mut attribute_container.id, *current_element);
                        // get whitelist array
                        let attribute_elements = attribute_element.attributes;
                        if(vector::length(&attribute_elements) != 0) {
                                results = vector::pop_back(&mut attribute_element.attributes);
                                break
                        };
                        
                        index = index + 1;
                };
                results
        }

}