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
        total_supply: u32,
        white_list: ID,
        fee_for_mint: u64,
        is_public: bool,
        limit_minted: u64,
        total_minted: u64,
    }

    struct CreateRoundEvent has copy,drop {
        round_id: ID,
        admin_address: address,
        round_name: String,
        limit_minted: u64,
        start_time: u64,
        end_time: u64,
        total_supply: u32,
        fee_for_mint: u64,
        is_public: bool,
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
        owner: address,
        round_id: ID,
    }


    fun init(otw: NFT_MODULE,ctx:&mut TxContext) {
        //set address of deployer to admin
        let admin = Admin{
            id: object::new(ctx),
            address: sender(ctx),
            receive_address: sender(ctx)
        };
        let container = Container{
            id: object::new(ctx),
            rounds: vector::empty(),
            description: string::utf8(b"This object use to save all the rounds"),
            total_minted: 0,
            total_supply: 5000,
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
        transfer::share_object(container);

    }

    public entry fun add_whitelist (whitelist_container: &mut WhitelistContainer, wallets: vector<address>, limits : vector<u64>, ctx: &mut TxContext) {
        whitelist_module::add_whitelist(whitelist_container, wallets, limits, ctx);
    }

    public entry fun mint_nft_with_whitelist (whitelist_container: &mut WhitelistContainer, mint_amount: u64, wallet: address,  is_no_limit : bool, ctx: &mut TxContext) {
        whitelist_module::update_whitelist(whitelist_container, mint_amount, wallet, is_no_limit, ctx);
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
        total_supply: u32,
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
        let white_list_id = whitelist_module::create_whitelist_conatiner(round_id, ctx);

        let round = Round{
            id: round_uid,
            round_name: round_name,
            start_time: start_time,
            end_time: end_time,
            total_supply: total_supply,
            white_list: white_list_id,
            fee_for_mint: fee_for_mint,
            is_public: is_public,
            limit_minted: limit_minted,
            total_minted: 0,
        };

        //emit event
        event::emit(CreateRoundEvent{
            round_id,
            admin_address: sender,
            round_name,
            limit_minted,
            start_time,
            end_time,
            total_supply,
            fee_for_mint,
            is_public,
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

    public entry fun buy_nft (
        admin:&mut Admin, 
        current_time: u64, 
        coin:&mut Coin<SUI>,
        container:&mut Container, 
        ctx:&mut TxContext
    ) {
        // get info
        let rounds = &mut container.rounds;
        let length = vector::length(rounds);
        let current_round = vector::borrow_mut(rounds, length - 1);

        // check time condition
        assert!(container.total_supply > container.total_minted, EMaximumNFTMinted);
        assert!(current_time >= current_round.start_time, ERoundDidNotStartedYet);
        assert!(current_round.total_supply != 0, EMaximunRoundMinted);


        if (current_time >=  current_round.end_time) {
            abort(ERoundWasEnded)
        };

        let current_round_mint_fee = current_round.fee_for_mint;
        assert!(coin::value(coin) >= current_round_mint_fee,ENotValidCoinAmount); 

        let mint_balance:Balance<SUI> = balance::split(coin::balance_mut(coin), current_round_mint_fee);
        transfer::public_transfer(coin::from_balance(mint_balance,ctx), admin.receive_address);

        // emit event
        event::emit(MintNft{
            owner: sender(ctx),
            round_id: object::uid_to_inner(&current_round.id),
        });
    }  

    public entry fun mint_nft(
        container: &mut Container, 
        whitelist_container: &mut WhitelistContainer,
        url: String,  
        clock: &Clock, 
        ctx:&mut TxContext
    ) {
        assert!(container.total_supply > container.total_minted, EMaximumNFTMinted);
        // get info
        let sender = sender(ctx);
        let rounds = &mut container.rounds;
        let length = vector::length(rounds);
        let current_round = vector::borrow_mut(rounds, length - 1);



        // check time condition
        assert!(clock::timestamp_ms(clock) >= current_round.start_time, ERoundDidNotStartedYet);
        assert!(current_round.total_supply != 0, EMaximunRoundMinted);
        if (clock::timestamp_ms(clock) >=  current_round.end_time) {
            abort(ERoundWasEnded)
        };

        whitelist_module::update_whitelist(whitelist_container, 1, sender, current_round.is_public, ctx);

        let new_nft = Nft{
            id: object::new(ctx),
            round_id: object::uid_to_inner(&current_round.id),
            url: url::new_unsafe(string::to_ascii(url)),
            owner: sender,
        };
        
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