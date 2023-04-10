module launchpad_nft::sui_zero_testnet{
    use sui::tx_context::{TxContext,sender};
    use std::string::{Self,String,utf8};
    use sui::package;
    use sui::display;
    use shoshinlaunchpad::launchpad_module::{Self,Launchpad};
    use sui::url::{Self,Url};
    use sui::object::{Self,ID,UID};
    use sui::transfer;
    use std::vector;



    struct Nft has key,store {
        id: UID,
        owner : address
    }

    struct SUI_ZERO_TESTNET has drop {}
   
    fun init(otw: SUI_ZERO_TESTNET, ctx:&mut TxContext){
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
            utf8(b"https://storage.googleapis.com/shoshinsquare/ezgif.com-video-to-gif.gif"),
            utf8(b"https://storage.googleapis.com/shoshinsquare/ezgif.com-video-to-gif.gif"),
            utf8(b"https://storage.googleapis.com/shoshinsquare/ezgif.com-video-to-gif.gif"),
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
    }

    public entry fun mint_only_one(ctx:&mut TxContext){
        // get info
        let sender = sender(ctx);
            let new_nft = Nft{
                id: object::new(ctx),
                owner: sender
            };
            transfer::public_transfer(new_nft,sender(ctx))
    }

    public entry fun deposit_multiple_nfts_into_launchpad(lauchpad:&mut Launchpad, project_id: ID, mint_amount: u64, ctx:&mut TxContext){
        let amount = 0;
        // get info
        let sender = sender(ctx);

        while(amount < mint_amount){
            //mint nft
            let new_nft = Nft{
                id: object::new(ctx),
                owner: sender
            };

            launchpad_module::deposit<Nft>(lauchpad,project_id,new_nft,ctx);

            amount = amount + 1;
        };
    }

}