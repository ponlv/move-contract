module nft::nft{
    use shoshinlaunchpad::launchpad_module::{Self,Launchpad};
    // use shoshinwhitelist::whitelist_module::{Self,WhitelistContainer};
    use sui::tx_context::{TxContext,sender};
    use std::string::{Self,String,utf8};
    use sui::package;
    use sui::display;
    use sui::object::{Self,UID};
    use sui::transfer;
    use std::vector;
    use sui::event;


    //constant
    const EAdminOnly:u64 = 0;
    const ECantMint:u64 = 1;


    struct Admin has key {
        id: UID,
        address: address,
    }

    struct Nft has key,store {
        id: UID,
    }

    struct Minters has key, store {
        id: UID,
        admin_address : address,
        minters : vector<address>
    }

    struct NFT has drop {}
   
    fun init(otw: NFT, ctx:&mut TxContext){
        
        let admin = Admin{
            id: object::new(ctx),
            address: sender(ctx),           
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
            utf8(b"LOA SUI OG Pass"),
            utf8(b"Introducing the LOA Sui OG Pass Collection a unique offering for Legend of Arcadia players that fuses traditional gaming with the cutting-edge Web3 GameFi 2.0 ecosystem. Legend of Arcadia, a free-to-play and play-to-earn strategy-casual action card game, invites players to dive deep into its immersive universe while reaping rewards through staking, battling, and mining. Launching on Sui, the LOA Sui OG Pass Collection provides an array of exclusive benefits for its holders. Pass holders will enjoy priority access to IDO whitelists, Genesis NFT whitelists, and Alpha Test 2, allowing them to stay ahead of the curve in the evolving world of Legend of Arcadia. Additionally, Pass holders will have the chance to join in the exciting USDT raffle, adding an extra layer of reward to their gaming experience. Do not miss your opportunity to be a part of the LOA Sui OG Pass Collection a game-changing experience that brings together the best of gaming and blockchain technology."),
            utf8(b"https://shoshinsquare.infura-ipfs.io/ipfs/QmaVJytn4m41rwysFhWRZ4cswZ4PX9xX8fN9iUmZysSYT2"),
            utf8(b"https://shoshinsquare.infura-ipfs.io/ipfs/QmaVJytn4m41rwysFhWRZ4cswZ4PX9xX8fN9iUmZysSYT2"),
            utf8(b"https://shoshinsquare.infura-ipfs.io/ipfs/QmaVJytn4m41rwysFhWRZ4cswZ4PX9xX8fN9iUmZysSYT2"),
            utf8(b""),
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
        };
        transfer::public_transfer(nft, sender(ctx));

    }

    public entry fun transfer_admin(admin: &mut Admin, new_admin: address, ctx: &mut TxContext) {
        let sender = sender(ctx);
        // check admin
        assert!(sender == admin.address,EAdminOnly);
        admin.address = new_admin;
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


    public entry fun deposit_to_launchpad(admin: &mut Admin, launchpad: &mut Launchpad, mint_amount: u64, ctx: &mut TxContext) {
        let sender = sender(ctx);
        // check admin
        assert!(sender == admin.address,EAdminOnly);
        let amount = 0;
        while(amount < mint_amount){
            let nft = Nft{
                id: object::new(ctx),
            };
            launchpad_module::deposit<Nft>(launchpad, nft, ctx);
            amount = amount + 1;
        };
    }


}