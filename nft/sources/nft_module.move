module shoshinnft::nft_module{
    //import module
    use std::string::{Self,String,utf8};
    use sui::tx_context::{TxContext,sender};
    use sui::transfer;
    use sui::event;
    use std::vector;
    use sui::object::{Self,ID,UID};
    use sui::url::{Self,Url};
    use sui::coin::{Self,Coin};
    use sui::sui::SUI;
    use sui::balance::{Self,Balance};
    use sui::package;
    use sui::display;
    use sui::clock::{Self, Clock};
    use shoshinwhitelist::whitelist_module::{Self,WhitelistContainer};

   
   //constant
   const EAdminOnly:u64 = 0;
   const ERoundDidNotStartedYet:u64 = 1;
   const ERoundWasStarted:u64 = 2;
   const ERoundWasEnded:u64 = 3;
   const ESenderNotInWhiteList:u64 = 4;
   const ERoundNotExist:u64 = 5;
   const EMaximumMint:u64 = 6;
   const ENotValidCoinAmount:u64 = 7; 
   const ENotNftOwner:u64 = 8;
   const EMaximunRoundMinted:u64 = 9;
   const EMaximumNFTMinted:u64 = 10;
   

    struct Admin has key {
        id: UID,
        address: address,
        receive_address: address
    }

    /*--------ROUND-----------*/
    struct Container has key {
        id: UID,
        rounds: vector<Round>,
        description: String,
        total_minted: u64,
        total_supply: u64,
    }

    struct Round has key,store {
        id: UID,
        round_name: String,
        start_time: u64,
        end_time: u64,
        total_supply: u64,
        whitelist: ID,
        fee_for_mint: u64,
        is_public: bool,
        limit_minted: u64,
        total_minted: u64,
    
    }

    struct CreateRoundEvent has copy,drop {
        container_id: ID,
        round_id: ID,
        admin_address: address,
        round_name: String,
        limit_minted: u64,
        start_time: u64,
        end_time: u64,
        total_supply: u64,
        fee_for_mint: u64,
        is_public: bool,
        whitelist: ID,
    }


    struct CreateContainerEvent has copy,drop {
        container_id: ID,
        total_supply: u64,
    }



    /*---------------NFT---------------*/
    struct Nft has key,store {
        id: UID,
        round_id: ID,
        url: Url,
        owner: address
    }

    /// One-Time-Witness for the module.
    struct NFT_MODULE has drop {}

    struct MintNft has copy,drop {
        container_id: ID,
        minter: address,
        round_id: ID,
        nft_id: ID,
        price: u64,
    }

    fun init(otw: NFT_MODULE,ctx:&mut TxContext) {
        //set address of deployer to admin
        let admin = Admin{
            id: object::new(ctx),
            address: sender(ctx),
            receive_address: sender(ctx)
        };

        let keys = vector[
            utf8(b"name"),
            utf8(b"description"),
            utf8(b"url"),
            utf8(b"project_url"),
            utf8(b"image_url"),
            utf8(b"img_url"),
            utf8(b"creator"),
        ];

        let values = vector[
            utf8(b"Shoshin NFT"),
            utf8(b"Shoshin NFT"),
            utf8(b"{url}"),
            utf8(b"https://shoshinsquare.com/"),
            utf8(b"{url}"),
            utf8(b"{url}"),
            utf8(b"Shoshin square")
        ];

        // Claim the `Publisher` for the package!
        let publisher = package::claim(otw, ctx);

        // Get a new `Display` object for the `Nft` type.
        let display = display::new_with_fields<Nft>(
            &publisher, keys, values, ctx
        );

        // Commit first version of `Display` to apply changes.
        display::update_version(&mut display);       
 
        transfer::public_transfer(publisher, sender(ctx));
        transfer::public_transfer(display, sender(ctx));

        // Admin,Round objects will be saved on global storage
        // after the smart contract deployment we will get the ID to access it
        transfer::share_object(admin);
    }
    
    public entry fun create_container (total_supply: u64, admin:&mut Admin, ctx: &mut TxContext) { 
        let sender = sender(ctx);
        //admin only
        assert!(admin.address == sender,EAdminOnly);

        let container = Container{
            id: object::new(ctx),
            rounds: vector::empty(),
            description: string::utf8(b"This object use to save all the rounds"),
            total_minted: 0,
            total_supply: total_supply,
        };

        let container_id = object::id(&container);

        //emit event
        event::emit(CreateContainerEvent{
            container_id,
            total_supply
        });
        transfer::share_object(container);
    }

    public entry fun add_whitelist (whitelist_container: &mut WhitelistContainer, wallets: vector<address>, limits : vector<u64>, ctx: &mut TxContext) {
        whitelist_module::add_whitelist(whitelist_container, wallets, limits, ctx);
    }

    public entry fun add_whitelist_with_bought (whitelist_container: &mut WhitelistContainer, wallets: vector<address>, limits : vector<u64>, boughts: vector<u64>, ctx: &mut TxContext) {
        whitelist_module::add_whitelist_with_bought(whitelist_container, wallets, limits, boughts, ctx);
    }
    public entry fun delete_wallet_address_in_whitelist (whitelist_container: &mut WhitelistContainer, wallet: address, ctx: &mut TxContext) {
        whitelist_module::delete_wallet_in_whitelist(whitelist_container, wallet, ctx);
    }

    public entry fun change_receive_address(admin:&mut Admin, new_receive_address: address, ctx:&mut TxContext){
        let sender = sender(ctx);
        //admin only
        assert!(admin.address == sender,EAdminOnly);
        admin.receive_address = new_receive_address;
    }

    public entry fun create_new_round (
        admin:&mut Admin, 
        container:&mut Container, 
        round_name: String,
        start_time: u64,
        end_time: u64,
        total_supply: u64,
        fee_for_mint: u64,
        is_public: bool,
        limit_minted: u64,
        ctx:&mut TxContext
    ) {
        assert!(container.total_supply > container.total_minted, EMaximumNFTMinted);
        let sender = sender(ctx);
        //admin only
        assert!(admin.address == sender,EAdminOnly);
        let round_uid = object::new(ctx);
        let round_id = object::uid_to_inner(&round_uid);
        let whitelist_id = whitelist_module::create_whitelist_conatiner(round_id, ctx);
        
        let limit_mint = 0;

        if( is_public == true ) {
            limit_mint = limit_minted;
        };

        let round = Round{
            id: round_uid,
            round_name: round_name,
            start_time: start_time,
            end_time: end_time,
            total_supply: total_supply,
            whitelist: whitelist_id,
            fee_for_mint: fee_for_mint,
            is_public: is_public,
            limit_minted: limit_mint,
            total_minted: 0,
        };

        //emit event
        event::emit(CreateRoundEvent{
            container_id: object::id(container),
            round_id,
            admin_address: sender,
            round_name,
            limit_minted: limit_mint,
            start_time,
            end_time,
            total_supply,
            fee_for_mint,
            is_public,
            whitelist: whitelist_id,
        });
       
        //add new round into the round_vector on global storage
        let current_rounds = &mut container.rounds;
        vector::push_back(current_rounds, round);
    }

    public entry fun add_round_whitelist (
        whitelist_container: &mut WhitelistContainer,
        admin: &mut Admin,
        container: &mut Container,
        clock: &Clock, 
        wallets: vector<address>, 
        limits : vector<u64>,
        ctx:&mut TxContext
    ) {
        let sender = sender(ctx);
        // check admin
        assert!(admin.address == sender,EAdminOnly);
        let rounds = &mut container.rounds;
        let length = vector::length(rounds);
        let current_round = vector::borrow_mut(rounds, length - 1);

        // check current_time with round time
        assert!(clock::timestamp_ms(clock) < current_round.start_time, ERoundWasStarted);
        // add whitelist
        whitelist_module::add_whitelist(whitelist_container, wallets, limits, ctx);

    }

    public entry fun mint_nft(
        container: &mut Container, 
        admin: &mut Admin,
        whitelist_container: &mut WhitelistContainer,
        url: String,  
        coin: Coin<SUI>,
        clock: &Clock, 
        ctx:&mut TxContext
    ) {
        assert!(container.total_supply > container.total_minted, EMaximumNFTMinted);
        assert!(container.total_supply > 0, EMaximumNFTMinted);
        // get info
        let container_id = object::id(container);
        let sender = sender(ctx);
        let rounds = &mut container.rounds;
        let length = vector::length(rounds);
        let current_round = vector::borrow_mut(rounds, length - 1);

        // check time condition
        assert!(clock::timestamp_ms(clock) >= current_round.start_time, ERoundDidNotStartedYet);
        assert!(current_round.total_supply > 0, EMaximunRoundMinted);
        if (clock::timestamp_ms(clock) >=  current_round.end_time) {
            abort(ERoundWasEnded)
        };

        if(current_round.is_public == true) {
            let isExistedInWhitelist = whitelist_module::existed(whitelist_container, sender(ctx));
            if(isExistedInWhitelist == true) {
                whitelist_module::update_whitelist(whitelist_container, 1,sender(ctx), false, ctx);
            } else {
                    let wallets = vector::empty();
                    let limits = vector::empty();
                    vector::push_back(&mut wallets, sender(ctx));
                    vector::push_back(&mut limits, current_round.limit_minted);
                    whitelist_module::add_whitelist(whitelist_container, wallets, limits, ctx);
                    whitelist_module::update_whitelist(whitelist_container, 1, sender(ctx), false, ctx);
            };
        } else {
            whitelist_module::update_whitelist(whitelist_container, 1, sender(ctx), false, ctx);

        };

        let new_nft = Nft{
            id: object::new(ctx),
            round_id: object::uid_to_inner(&current_round.id),
            url: url::new_unsafe(string::to_ascii(url)),
            owner: sender,
        };

        event::emit(MintNft{
            container_id,
            minter: sender(ctx),
            round_id: object::uid_to_inner(&current_round.id),
            nft_id: object::id(&new_nft),
            price: current_round.fee_for_mint,
        });

        let price_balance:Balance<SUI> = balance::split(coin::balance_mut(&mut coin), current_round.fee_for_mint);
        transfer::public_transfer(coin::from_balance(price_balance, ctx), admin.receive_address);
        transfer::public_transfer(coin, sender);
        transfer::public_transfer(new_nft,sender);
        current_round.total_supply = current_round.total_supply - 1;
        current_round.total_minted = current_round.total_minted + 1;
        container.total_minted = container.total_minted + 1;
        
    }

    public entry fun transfer_nft(nft: Nft, receive_address: address, ctx:&mut TxContext){
        let sender = sender(ctx);
        assert!(nft.owner == sender, ENotNftOwner);
        transfer::public_transfer(nft,receive_address);
    }

}