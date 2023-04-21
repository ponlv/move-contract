module shoshinmintattribute::nft{
    use shoshinattribute::attribute_module::{Self,AttributeContainer};
    // use shoshinwhitelist::whitelist_module::{Self,WhitelistContainer};
    use sui::tx_context::{TxContext,sender};
    use std::string::{Self,String,utf8};
    use sui::package;
    use sui::display;
    use sui::url::{Self,Url};
    use sui::object::{Self,ID,UID};
    use sui::transfer;
    use std::vector;
    use sui::event;


    //constant
    const EAdminOnly:u64 = 0;
    const ECantMint:u64 = 1;


    struct Admin has key {
        id: UID,
        address: address,
        attribute_id: ID
    }

    struct Nft has key,store {
        id: UID,
        owner : address
    }

    struct Minters has key, store {
        id: UID,
        admin_address : address,
        minters : vector<address>
    }

    struct NFT has drop {}
   
    fun init(otw: NFT, ctx:&mut TxContext){
        let attribute_id = attribute_module::create_attribute_container(ctx);
        let admin = Admin{
            id: object::new(ctx),
            address: sender(ctx),  
            attribute_id         
        };

        let minters = Minters {
            id: object::new(ctx),
            minters: vector::empty(),
            admin_address : admin.address
        };

        let keys = vector[
            utf8(b"name"),
            utf8(b"description"),
            utf8(b"url"),
            utf8(b"image_url"),
            utf8(b"img_url"),
            utf8(b"project_url"),
            utf8(b"creator"),
        ];

        let values = vector[
            utf8(b"SUI Zero: NFT Testnet"),
            utf8(b"NFT SUI Zero testnet in SUI network power by Shoshin Square. Become the pioneer in the SUInami."),
            utf8(b"https://i.pinimg.com/564x/fc/b0/9b/fcb09b7dbc1d3696f416c5f2c911173b.jpg"),
            utf8(b"https://i.pinimg.com/564x/fc/b0/9b/fcb09b7dbc1d3696f416c5f2c911173b.jpg"),
            utf8(b"https://i.pinimg.com/564x/fc/b0/9b/fcb09b7dbc1d3696f416c5f2c911173b.jpg"),
            utf8(b"https://shoshinsquare.com/"),
            utf8(b"Shoshin square")
        ];

        let publisher = package::claim(otw,ctx);

        let display = display::new_with_fields<Nft>(
                &publisher, keys, values, ctx
        );
        // Commit first version of `Display` to apply changes.
        display::update_version(&mut display);       
    
        transfer::public_transfer(publisher, sender(ctx));
        transfer::public_transfer(display, sender(ctx));
        
        transfer::share_object(admin); 
        transfer::share_object(minters); 

        // raw nft 
        let nft = Nft{
            id: object::new(ctx),
             owner: sender(ctx)
        };
        transfer::public_transfer(nft, sender(ctx));

    }



    struct AddMinterEvent has copy, drop {
        minter : address
    }


    /***
    * @dev add_minter
    *
    *
    * @param admin is admin id
    * @param minter is minter address
    * 
    */
    public entry fun add_minter(admin: &mut Admin,minters: &mut Minters, minter: address, ctx: &mut TxContext) {
        let sender = sender(ctx);
        // check admin
        assert!(sender == admin.address,EAdminOnly);

        //push
        vector::push_back(&mut minters.minters, minter);

        event::emit(AddMinterEvent{
            minter,
        });
    }
    
    /***
    * @dev mint
    *
    *
    * @param minters is can mint list
    * @param mint_amount is how many nft will be mint
    * 
    */

    struct MinterEvent has copy, drop {
        minter : address,
        mint_amount : u64,
    }
    public entry fun mint(minters: &mut Minters, transfer_to : address, mint_amount: u64, ctx: &mut TxContext) {
        let sender = sender(ctx);
        let minters = &mut minters.minters;
        let minters_length = vector::length(minters);
        let minter_index = 0;
        let is_can_mint = false;
        // check in minters list
        while(minter_index < minters_length) {
            let current_element = vector::borrow(minters, minter_index);
            if(*current_element == sender) {
                is_can_mint = true;
            };
            minter_index = minter_index + 1;
        };
        // check can mint
        assert!(is_can_mint == true, ECantMint);
        if(is_can_mint){
            let amount = 0;

            // mint with amount
            while(amount < mint_amount){
                let nft = Nft{
                    id: object::new(ctx),
                    owner: sender
                };
                transfer::public_transfer(nft, transfer_to);
                amount = amount + 1;
            };
        };

        event::emit(MinterEvent{
            minter: transfer_to,
            mint_amount,
        });

    }

    public entry fun push_attributes(attribute_container: &mut AttributeContainer, admin: &mut Admin, attribute_keys: vector<vector<String>>,attribute_values: vector<vector<String>>, ctx: &mut TxContext) {
        let sender = sender(ctx);
        // check admin
        assert!(sender == admin.address,EAdminOnly);

        attribute_module::push_attributes(attribute_container, attribute_keys, attribute_values, ctx);
    }


}