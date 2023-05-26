module nft::nft{
    use shoshinlaunchpad::launchpad_module::{Self,Launchpad};
    use sui::tx_context::{TxContext,sender};
    use std::string::{Self,String,utf8};
    use sui::package;
    use sui::display;
    use sui::url::{Self, Url};
    use sui::object::{Self, UID};
    use sui::transfer;
    use std::vector;
    use sui::event;


    //constant
    const EAdminOnly:u64 = 0;
    const ECantMint:u64 = 1;
    const EMagicNotEnable:u64 = 2;


    struct Admin has key {
        id: UID,
        address: address,
    }

    struct Nft has key,store {
        id: UID,
        url: Url,
        project_url: Url,
        creator: String,
        description: String,
        name: String,
        index: u64
    }

    struct Container has key, store {
        id: UID,
        admin_address : address,
        minters : vector<address>,
        total_minted: u64,
    }

    struct NFT has drop {}
   
    fun init(otw: NFT, ctx:&mut TxContext){
        
        let admin = Admin{
            id: object::new(ctx),
            address: sender(ctx),           
        };

        let container = Container {
            id: object::new(ctx),
            minters: vector::empty(),
            admin_address: admin.address,
            total_minted: 0,
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
            utf8(b"{name} #{index}"),
            utf8(b"{description}"),
            utf8(b"{url}"),
            utf8(b"{url}"),
            utf8(b"{url}"),
            utf8(b"{project_url}"),
            utf8(b"{creator}")
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
        transfer::share_object(container); 

    }

    /***
    * @dev transfer_admin transfer both nft admin and attribute admin
    *
    *
    * @param admin is admin id
    * @param minter is minter address
    * 
    */
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
    public entry fun add_minter(admin: &mut Admin,container: &mut Container, minter: address, ctx: &mut TxContext) {
        let sender = sender(ctx);
        // check admin
        assert!(sender == admin.address,EAdminOnly);

        let index = 0;
        let minter_length = vector::length(&container.minters);
        let existed = false;
        while(index < minter_length) {
            let current_minter = vector::borrow(&container.minters, index);
            if(*current_minter == minter) {
                existed = true;
            };
            index = index + 1;
        };

        if(existed == false) {
            vector::push_back(&mut container.minters, minter);
        };

        event::emit(AddMinterEvent{
            minter,
        });
    }

    /***
    * @dev remove_minter
    *
    *
    * @param admin is admin id
    * @param minter is minter address
    * 
    */
    public entry fun remove_minter(admin: &mut Admin,container: &mut Container, minter: address, ctx: &mut TxContext) {
        let sender = sender(ctx);
        // check admin
        assert!(sender == admin.address,EAdminOnly);

        let index = 0;
        let minter_length = vector::length(&container.minters);
        let current_delete_index = 0;
        let existed = false;
        while(index < minter_length) {
            let current_minter = vector::borrow(&container.minters, index);
            if(*current_minter == minter) {
                existed = true;
                current_delete_index = index;
            };
            index = index + 1;
        };

        if( existed == true ) {
            vector::remove(&mut container.minters, current_delete_index);
        };

        event::emit(AddMinterEvent{
            minter,
        });
    }

    struct MinterEvent has copy, drop {
        minter : address,
        mint_amount : u64,
    }
    
    /***
    * @dev mint
    *
    *
    * @param minters is can mint list
    * @param mint_amount is how many nft will be mint
    * 
    */
    public entry fun mint(
        admin: &mut Admin, 
        container: &mut Container,
        image_url: String,
        project_url: String,
        creator: String,
        description: String,
        name: String,
        transfer_to : address, 
        mint_amount: u64,  
        ctx: &mut TxContext
    ) {
        let sender = sender(ctx);
        let minters = &mut container.minters;
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
        assert!(is_can_mint == true || admin.address == sender, ECantMint);
        let amount = 0;

        let current_index = container.total_minted;

        while(amount < mint_amount){
            let nft = Nft{
                id: object::new(ctx),
                url: url::new_unsafe(string::to_ascii(image_url)),
                project_url: url::new_unsafe(string::to_ascii(project_url)),
                creator,
                description,
                name,
                index: current_index,
            };
            current_index = current_index + 1;
            amount = amount + 1;
            transfer::public_transfer(nft, transfer_to);
        };

        event::emit(MinterEvent{
            minter: transfer_to,
            mint_amount,
        });
        container.total_minted = container.total_minted + mint_amount;

    }

    /***
    * @dev deposit_to_launchpad
    *
    *
    * @param admin admin id
    * @param container container id
    * @param launchpad launchpad id
    * @param mint_amount amount to mint id
    * 
    */
    public entry fun deposit_to_launchpad(
        admin: &mut Admin,  
        launchpad: &mut Launchpad, 
        container: &mut Container,
        mint_amount: u64,
        image_url: String,       
        project_url: String,
        creator: String,
        description: String,
        name: String,
        ctx: &mut TxContext
    ) {     
        let sender = sender(ctx);
        // check admin
        assert!(sender == admin.address,EAdminOnly);
        let amount = 0;
        let current_index = container.total_minted;

        while(amount < mint_amount){
            let nft = Nft{
                id: object::new(ctx),
                url: url::new_unsafe(string::to_ascii(image_url)),
                project_url: url::new_unsafe(string::to_ascii(project_url)),
                creator,
                description,
                name,
                index: current_index,
            };
            current_index = current_index + 1;
            amount = amount + 1;
            launchpad_module::deposit<Nft>(launchpad, nft, ctx);
        };
    
        container.total_minted = container.total_minted + mint_amount;

    }



}