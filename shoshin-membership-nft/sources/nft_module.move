module shoshinnft::nft_module{
    //import module
    use std::string::{Self,String,utf8};
    use sui::tx_context::{TxContext,sender};
    use sui::transfer;
    use sui::event;
    use std::vector;
    use sui::object::{Self,ID,UID};
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
        enable_addresses: vector<address>,
        receive_address: address,
        pool: Coin<SUI>,
        total_pool: u64,
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
    }

    /// One-Time-Witness for the module.
    struct NFT_MODULE has drop {}

    struct MintNft has copy,drop {
        container_id: ID,
        minter: address,
        round_id: ID,
        price: u64,
        amount: u64,
        nft_ids: vector<ID>
    }

    fun init(otw: NFT_MODULE,ctx:&mut TxContext) {

        let sender = sender(ctx);
        let enable_addresses = vector::empty();
        vector::push_back(&mut enable_addresses, sender);

        let admin = Admin{
            id: object::new(ctx),
            enable_addresses: enable_addresses,
            receive_address: sender,
            pool: coin::from_balance(balance::zero<SUI>(), ctx),
            total_pool: 0,
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
            utf8(b"https://storage.googleapis.com/shoshinsquare/s0-banner.webp"),
            utf8(b"https://shoshinsquare.com/"),
            utf8(b"https://storage.googleapis.com/shoshinsquare/s0-banner.webp"),
            utf8(b"https://storage.googleapis.com/shoshinsquare/s0-banner.webp"),
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
    

    /***
    * @dev isAdmin
    *
    *
    * @param admin is admin id
    * @param new_address
    * 
    */
    public fun isAdmin(admin: &mut Admin, address : address) : bool {
            let rs = false;
            let list = admin.enable_addresses;

            let length = vector::length(&list);

            let index = 0;

            while(index < length) {
            let current = vector::borrow(&list, index);
            if(*current == address) {
                    rs = true;
                    break
            };
            index = index + 1;
            };
            rs
    }
    

    public entry fun withdraw(admin: &mut Admin, receive_address: address, ctx: &mut TxContext) {
        let sender = sender(ctx);
        //admin only
        assert!(isAdmin(admin, sender) == true, EAdminOnly);
        let money:Balance<SUI> = balance::split(coin::balance_mut(&mut admin.pool), admin.total_pool);
        transfer::public_transfer(coin::from_balance(money, ctx), receive_address);
        admin.total_pool = 0;
    }

    public entry fun create_container (total_supply: u64, admin:&mut Admin, ctx: &mut TxContext) { 
        let sender = sender(ctx);
        //admin only
        assert!(isAdmin(admin, sender) == true, EAdminOnly);

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

    public entry fun add_whitelist (admin: &mut Admin, whitelist_container: &mut WhitelistContainer, wallets: vector<address>, limits : vector<u64>, ctx: &mut TxContext) {
        let sender = sender(ctx);
        // check admin
        assert!(isAdmin(admin, sender) == true, EAdminOnly);
        whitelist_module::add_whitelist(whitelist_container, wallets, limits, ctx);
    }

    public entry fun add_whitelist_with_bought (admin: &mut Admin, whitelist_container: &mut WhitelistContainer, wallets: vector<address>, limits : vector<u64>, boughts: vector<u64>, ctx: &mut TxContext) {
        let sender = sender(ctx);
        // check admin
        assert!(isAdmin(admin, sender) == true, EAdminOnly);
        whitelist_module::add_whitelist_with_bought(whitelist_container, wallets, limits, boughts, ctx);
    }
    public entry fun delete_wallet_address_in_whitelist (whitelist_container: &mut WhitelistContainer, wallet: address, ctx: &mut TxContext) {
        whitelist_module::delete_wallet_in_whitelist(whitelist_container, wallet, ctx);
    }

    public entry fun change_receive_address(admin:&mut Admin, new_receive_address: address, ctx:&mut TxContext){
        let sender = sender(ctx);
        //admin only
        assert!(isAdmin(admin, sender) == true, EAdminOnly);
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
        assert!(isAdmin(admin, sender) == true, EAdminOnly);
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

    public entry fun mint_nft(
        container: &mut Container, 
        admin: &mut Admin,
        whitelist_container: &mut WhitelistContainer,
        coin: Coin<SUI>,
        amount: u64,
        clock: &Clock, 
        ctx: &mut TxContext
    ) {
        assert!(container.total_supply > container.total_minted, EMaximumNFTMinted);
        assert!(container.total_supply >= amount, EMaximumNFTMinted);
        // get info
        let container_id = object::id(container);
        let sender = sender(ctx);
        let rounds = &mut container.rounds;
        let length = vector::length(rounds);
        let current_round = vector::borrow_mut(rounds, length - 1);

        // check time condition
        assert!(clock::timestamp_ms(clock) >= current_round.start_time, ERoundDidNotStartedYet);
        assert!(current_round.total_supply >= amount, EMaximunRoundMinted);
        if (clock::timestamp_ms(clock) >=  current_round.end_time) {
            abort(ERoundWasEnded)
        };

        if(current_round.is_public == true) {
            let isExistedInWhitelist = whitelist_module::existed(whitelist_container, sender);
            if(isExistedInWhitelist == true) {
                whitelist_module::update_whitelist(whitelist_container, amount, sender, false, ctx);
            } else {
                    let wallets = vector::empty();
                    let limits = vector::empty();
                    vector::push_back(&mut wallets, sender);
                    vector::push_back(&mut limits, current_round.limit_minted);
                    whitelist_module::add_whitelist(whitelist_container, wallets, limits, ctx);
                    whitelist_module::update_whitelist(whitelist_container, amount, sender, false, ctx);
            };
        } else {
            whitelist_module::update_whitelist(whitelist_container, amount, sender, false, ctx);
        };
        let nft_index = 0;

        let nft_ids = vector::empty();

        while(nft_index < amount) {
            let new_nft = Nft{
                id: object::new(ctx),
                round_id: object::id(current_round),
            };
            vector::push_back(&mut nft_ids, object::id(&new_nft));
            transfer::public_transfer(new_nft,sender);
            nft_index = nft_index + 1;
        };

        event::emit(MintNft{
            container_id,
            minter: sender,
            round_id: object::id(current_round),
            price: current_round.fee_for_mint,
            amount,
            nft_ids
        });

        let price_balance:Balance<SUI> = balance::split(coin::balance_mut(&mut coin), current_round.fee_for_mint * amount);
        coin::join(&mut admin.pool, coin::from_balance(price_balance, ctx));
        admin.total_pool = admin.total_pool + current_round.fee_for_mint * amount;
        transfer::public_transfer(coin, sender);
        current_round.total_supply = current_round.total_supply - amount;
        current_round.total_minted = current_round.total_minted + amount;
        container.total_minted = container.total_minted + amount;
        
    }

    public entry fun transfer_nft(nft: Nft, receive_address: address, _:&mut TxContext){
        transfer::public_transfer(nft,receive_address);
    }

}