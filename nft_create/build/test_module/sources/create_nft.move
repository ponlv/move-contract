module test_module::create_nft{
    use sui::tx_context::{TxContext,sender};
    use std::string::{Self,String,utf8};
    use sui::package;
    use sui::display;
    use shoshinlaunchpad::launchpad_module::{Self,Launchpad};
    use sui::url::{Self,Url};
    use sui::object::{Self,ID,UID};
    use sui::transfer;


    struct Nft has key,store {
        id: UID,
        name: String,
        desciption: String,
        url: Url,
        total_supply: u64,
    }

    struct CREATE_NFT has drop {}
   
    fun init(otw: CREATE_NFT, ctx:&mut TxContext){
        let keys = vector[
            utf8(b"name"),
            utf8(b"description"),
            utf8(b"url"),
        ];

        let values = vector[
            utf8(b"{name}"),
            utf8(b"{description}"),
            utf8(b"{url}"),
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

    public entry fun mint_nfts(lauchpad:&mut Launchpad, project_id: ID, name: String, description: String, url: String, total_supply: u64, mint_amount: u64, ctx:&mut TxContext){
        let amount = 0;
        // get info
        let sender = sender(ctx);

        while(amount < mint_amount){
            //mint nft
            let new_nft = Nft{
                id: object::new(ctx),
                name: name,
                desciption: description,
                url: url::new_unsafe(string::to_ascii(url)),
                total_supply: total_supply,
            };

            launchpad_module::deposit<Nft>(lauchpad,project_id,new_nft,ctx);

            amount = amount + 1;
        };
    }

}