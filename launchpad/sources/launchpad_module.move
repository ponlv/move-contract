module shoshinlaunchpad::launchpad_module {
        use shoshinwhitelist::whitelist_module::{Self,WhitelistContainer};
        use sui::clock::{Self, Clock};
        use std::type_name::{Self, TypeName};
        use sui::dynamic_object_field as ofield;
        use sui::object::{Self,ID,UID};
        use sui::transfer;
        use std::string::{Self,String};
        use sui::coin::{Self,Coin};
        use sui::balance::{Self,Balance};
        use sui::sui::SUI;
        use sui::tx_context::{Self, TxContext};
        use sui::event;
        use std::vector;

        const EAdminOnly:u64 = 0;
        const ECantBuyNft:u64 = 14;
        const ETooSoonToBuy:u64 = 15;
        const ETooLateToBuy:u64 = 16;
        const ECantBuy:u64 = 17;
        const EWhiteListInCorrect:u64 = 18;
        const EWrongProjectOwner:u64 = 19;
        const ERoundStarted:u64 = 20;
        const EWasOwned:u64 = 21;
        const EWrongTotalSupply:u64 = 22;
        const ENotEnoughNft:u64 = 23;
        const EBuyLimit:u64 = 24;
        const ENotHavePermistion:u64 = 25;
        const ENotVailableToDeposit:u64 = 26;
        const EBuyFail:u64 = 27;
        const ERoundNotPublic:u64 = 28;
        const EIsRoundPublic:u64 = 29;
        const ERoundClosed:u64 = 30;

        const MAXIMUM_OBJECT_SIZE:u64 = 100;


        struct Admin has key {
                id: UID,
                enable_addresses: vector<address>,
        }

        struct Round has key,store {
                id: UID,
                name: String,
                start_time: u64,
                end_time: u64,
                is_public : bool,
                total_supply: u64,
                price: u64,
                limit_mint: u64,
                whitelist: ID,
                status: bool,
                total_minted: u64,
        }

        struct Launchpad has key, store {
                id: UID,
                name: String,
                owner_address: address,
                total_supply: u64,
                total_pool: u64,
                pool: Coin<SUI>,
                total_minted: u64,
                is_deposit: bool,
                nft_container_ids: vector<ID>,
        }


        struct NFTContainer<T: key + store> has key, store {
                id: UID,
                nfts: vector<T>
        }

        fun init(ctx:&mut TxContext) {
                let sender = tx_context::sender(ctx);
                let enable_addresses = vector::empty();
                vector::push_back(&mut enable_addresses, sender);
                let admin = Admin{
                id: object::new(ctx),
                        enable_addresses: enable_addresses,
                };
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

        /***
        * @dev change_admin_address
        *
        *
        * @param admin is admin id
        * @param new_address
        * 
        */
        public entry fun addAdmin(admin:&mut Admin, new_enable_addresses: vector<address>, ctx:&mut TxContext){
                // check admin
                let sender = tx_context::sender(ctx);
                assert!(isAdmin(admin, sender) == true, EAdminOnly);

                vector::append(&mut admin.enable_addresses, new_enable_addresses);
        }

        struct CreateLaunchpadEvent has copy, drop {
                project_id: ID,
                name : String,
                owner_address: address,
                total_supply: u64,
                type : TypeName,
                is_deposit: bool
        }

        /***
        * @dev make_create_launchpad : create project
        *
        *
        * @param admin is admin id
        * @param name is name of project
        * @param owner_address owner of launchpad
        * @param total_supply how many nft will be mint
        * @param is_deposit is exist nft
        * 
        */
        public entry fun make_create_launchpad<T: key + store>(
                admin:&mut Admin,
                name: String, 
                owner_address: address,
                total_supply: u64,
                is_deposit: bool,
                ctx: &mut TxContext
        ) {
                // check admin
                let sender = tx_context::sender(ctx);
                assert!(isAdmin(admin, sender) == true, EAdminOnly);

                // check total supply
                let current_total_supply = total_supply;
                if (is_deposit == true) {
                        current_total_supply = 0
                };
                // create default nft container (empty)
                let default_nft_container = NFTContainer<T>{
                        id: object::new(ctx),
                        nfts: vector::empty(),
                };
                let default_nft_container_id = object::id(&default_nft_container);

                // push default nft container to project
                let nft_container_ids: vector<ID> = vector::empty();
                vector::push_back(&mut nft_container_ids, default_nft_container_id);
                // create new launchpad
                let launchpad = Launchpad {
                        id: object::new(ctx),
                        name,
                        owner_address,
                        total_supply: current_total_supply,
                        is_deposit,
                        total_pool: 0,
                        total_minted: 0,
                        pool: coin::from_balance(balance::zero<SUI>(), ctx),
                        nft_container_ids: nft_container_ids,
                };
                // add container to project field
                ofield::add(&mut launchpad.id, default_nft_container_id, default_nft_container); 


                //emit event
                event::emit(CreateLaunchpadEvent{
                        project_id: object::id(&launchpad),
                        name,
                        owner_address,
                        total_supply: current_total_supply,
                        type : type_name::get<T>(),
                        is_deposit,
                });

                // share
                transfer::share_object(launchpad);
        }

        /*** -------------------------------------------------Deposit------------------------------------------------------------- */

        struct AddNftToProject has copy, drop {
                project_id: ID,
                nft_id: ID,
        }
        
        /***
        * @dev deposit : deposit nft to project
        *
        *
        * @param launchpad launchpad project
        * @param admin admin id
        * @param nft want deposit
        * 
        */
        public fun deposit<T: key + store>(
                launchpad: &mut Launchpad,
                nft: T,
                ctx: &mut TxContext
        ) {
                let sender = tx_context::sender(ctx);
                assert!(sender == launchpad.owner_address, ENotHavePermistion);
                assert!(launchpad.is_deposit == true, ENotVailableToDeposit);
                event::emit(AddNftToProject{
                        project_id: object::id(launchpad),
                        nft_id: object::id(&nft) 
                }); 
                let nft_container_ids = launchpad.nft_container_ids;
                let nft_container_ids_length = vector::length<ID>(&nft_container_ids);
                let focus_nft_container_id = vector::borrow<ID>(&nft_container_ids, nft_container_ids_length - 1);
                let nft_container = ofield::borrow_mut<ID, NFTContainer<T>>(&mut launchpad.id, *focus_nft_container_id);
                let count_current_nft_array = vector::length(&nft_container.nfts);
                if (count_current_nft_array < MAXIMUM_OBJECT_SIZE) {
                        vector::push_back(&mut nft_container.nfts, nft);
                } else {
                        let nfts = vector::empty();
                        vector::push_back(&mut nfts, nft);
                        let new_nft_container = NFTContainer<T>{
                                id: object::new(ctx),
                                nfts,
                        };
                        let default_nft_container_id = object::id(&new_nft_container);
                        vector::push_back(&mut launchpad.nft_container_ids, default_nft_container_id);
                        ofield::add(&mut launchpad.id, default_nft_container_id, new_nft_container); 
                };
                launchpad.total_supply = launchpad.total_supply + 1;
        }

        /***
        * @dev make_deposit : deposit nft to project extend deposit
        *
        *
        * @param launchpad launchpad project
        * @param admin admin id
        * @param nft want deposit
        * 
        */
        public entry fun make_deposit<T: key + store> (
                launchpad: &mut Launchpad,
                nft: T,
                ctx: &mut TxContext
        ) {
               deposit<T>(launchpad, nft, ctx);
        }

        /***
        * @dev deposit : deposit nft to project
        *
        *
        * @param launchpad launchpad project
        * @param admin admin id
        * @param nfts want deposit
        * 
        */
        // public entry fun make_batch_deposit<T: key + store>(
        //         launchpad: &mut Launchpad,
        //         admin:&mut Admin,
        //         nfts: vector<T>,
        //         ctx: &mut TxContext
        // ) {
        //         let length = vector::length(&nfts);
        //         let index = 0;
        //         while(index < length) {
        //                 deposit<T>(launchpad, admin, vector::pop_back(&mut nfts), ctx);
        //                 index = index + 1;
        //         };
        //         vector::destroy_empty(nfts);
        // }
        
        /*** -------------------------------------------------Withdraw Coin------------------------------------------------------------- */

       struct DelauchpadEvent has copy, drop {
                project_id: ID,
                owner : address,
                commission : u64,
                total_pool : u64
        }

        /***
        * @dev withdraw : withdraw coin
        *
        *
        * @param launchpad launchpad project
        * @param admin admin id
        * @param commission fee
        * @param receive_commission_address address receive fee
        * @param owner_receive_address address to get sui
        * 
        */
        public fun withdraw(
                launchpad: &mut Launchpad,
                admin: &mut Admin,
                commission: u64, 
                receive_commission_address: address, 
                owner_receive_address: address, 
                ctx: &mut TxContext
        ) {
                // check admin
                let sender = tx_context::sender(ctx);
                assert!(isAdmin(admin, sender) == true, EAdminOnly);

                // calculation commission
                let commission_value = launchpad.total_pool * commission / 100;
                let commission_balance:Balance<SUI> = balance::split(coin::balance_mut(&mut launchpad.pool), commission_value);
                let revenue_balance:Balance<SUI> = balance::split(coin::balance_mut(&mut launchpad.pool), launchpad.total_pool - commission_value);
                // event
                event::emit(DelauchpadEvent{
                        project_id: object::id(launchpad),
                        owner : launchpad.owner_address,
                        commission: commission_value,
                        total_pool: launchpad.total_pool,
                });
                // transfer
                transfer::public_transfer(coin::from_balance(revenue_balance, ctx), owner_receive_address);
                transfer::public_transfer(coin::from_balance(commission_balance, ctx), receive_commission_address);
                launchpad.total_pool = 0;
        }

        /***
        * @dev make_withdraw : withdraw coin
        *
        *
        * @param launchpad launchpad project
        * @param admin admin id
        * @param commission fee
        * @param receive_commission_address address receive fee
        * @param owner_receive_address address to get sui
        * 
        */
        public entry fun make_withdraw(
                launchpad: &mut Launchpad,
                admin: &mut Admin,
                commission: u64, 
                receive_commission_address: address, 
                owner_receive_address: address, 
                ctx: &mut TxContext
        ) {
                withdraw(launchpad, admin, commission, receive_commission_address, owner_receive_address, ctx);
        }

        /***
        * @dev make_delaunchpad : delaunchpad
        *
        *
        * @param launchpad launchpad project
        * @param admin admin id
        * @param commission fee
        * @param receive_commission_address address receive fee
        * @param owner_receive_address address to get sui
        * 
        */
        public entry fun make_delaunchpad<T: store + key>(
                launchpad: &mut Launchpad,
                admin: &mut Admin,
                commission: u64, 
                receive_commission_address: address, 
                owner_receive_address: address, 
                ctx: &mut TxContext
        ) {
                // check admin
                let sender = tx_context::sender(ctx);
                assert!(isAdmin(admin, sender) == true, EAdminOnly);

                // withdraw coin
                withdraw(launchpad, admin, commission, receive_commission_address, owner_receive_address, ctx);

                // get ID of Whitelist object element
                let nft_container_ids = launchpad.nft_container_ids;
                // loop container nft array
                let index = 0;
                let count_nft_container_ids = vector::length<ID>(&nft_container_ids);
                while(index < count_nft_container_ids) {
                        // get current id
                        let current_container_id = vector::borrow<ID>(&nft_container_ids, index);
                        // get current container
                        let container_element = ofield::borrow_mut<ID, NFTContainer<T>>(&mut launchpad.id, *current_container_id);
                        // loop in nft array
                        let count_nfts = vector::length(&container_element.nfts);

                        let nft_index = 0;
                        while(nft_index < count_nfts) {
                                let current_nft = vector::pop_back(&mut container_element.nfts);
                                transfer::public_transfer(current_nft, owner_receive_address);
                                nft_index = nft_index + 1;
                        };
                        index = index + 1;
                };
                launchpad.total_supply = 0;

        }

        /*** -------------------------------------------------Buy NFT------------------------------------------------------------- */

        struct BuyWithDepositNftEvent has copy, drop {
                project_id: ID,
                round_id : ID,
                price : u64,
                buyer : address,
                amount: u64,
                nft_ids: vector<ID>
        }

        /***
        * @dev make_buy_deposit_nft for user who admin add to whitelist 
        *
        * @type_argument T is type of Nfts
        *
        * @param whitelist_container round whitelist id
        * @param launchpad project id
        * @param round_id current round
        * @param coin coin  to paid
        * @param clock time
        * 
        */
        public entry fun make_buy_deposit_nft<T: store + key>(whitelist_container: &mut WhitelistContainer ,launchpad: &mut Launchpad, round_id: ID, coin: Coin<SUI>, amount: u64, clock: &Clock, ctx: &mut TxContext) {
                // check owner
                assert!(launchpad.owner_address != tx_context::sender(ctx), EWasOwned);
                assert!(launchpad.is_deposit == true, ENotHavePermistion);
                // check total supply
                assert!(launchpad.total_supply > 0, ENotEnoughNft);

                // get ID of Whitelist object element
                let nft_container_ids = launchpad.nft_container_ids;
                // loop container nft array
                let index = 0;
                let count_nft_container_ids = vector::length<ID>(&nft_container_ids);
                let is_stop = false;
                let count = 0;
                let bought_nfts = vector::empty();
                while(index < count_nft_container_ids) {
                        // get current id
                        let current_container_id = vector::borrow<ID>(&nft_container_ids, index);
                        // get current container
                        let container_element = ofield::borrow_mut<ID, NFTContainer<T>>(&mut launchpad.id, *current_container_id);
                        // loop in nft array
                        let count_nfts = vector::length(&container_element.nfts);
                        while(count < amount && count_nfts > 0) {
                                // send nft
                                let current_nft = vector::pop_back(&mut container_element.nfts);
                                vector::push_back(&mut bought_nfts, object::id(&current_nft));
                                transfer::public_transfer(current_nft, tx_context::sender(ctx));
                                count = count + 1;

                                if(count == amount) {
                                        is_stop = true;
                                        break
                                };
                        };

                        if (is_stop == true) {
                                break
                        };
                        index = index + 1;
                };
                // check get nft success
                assert!(is_stop == true, EBuyFail);

                let project_id = object::id(launchpad);

                // get current round
                let current_round = ofield::borrow_mut<ID,Round>(&mut launchpad.id, round_id);
                // limit by round
                assert!(current_round.total_supply >= amount, ENotEnoughNft);
                // check public round
                assert!(current_round.limit_mint == 0, EIsRoundPublic);
                // check close
                assert!(current_round.status == true, ERoundClosed);
                // check can buy ?
                whitelist_module::update_whitelist(whitelist_container, amount, tx_context::sender(ctx), current_round.is_public, ctx);
                // check valid time
                let current_time = clock::timestamp_ms(clock);
                assert!(current_time > current_round.start_time, ETooSoonToBuy);
                assert!(current_time < current_round.end_time, ETooLateToBuy);
                // push coin to pool

                launchpad.total_supply = launchpad.total_supply - amount; 
                launchpad.total_minted = launchpad.total_minted + amount;
                launchpad.total_pool = launchpad.total_pool + current_round.price * amount;
                current_round.total_supply = current_round.total_supply - amount;
                current_round.total_minted = current_round.total_minted + amount;

                // emit event
                event::emit(BuyWithDepositNftEvent{
                        project_id,
                        round_id: object::id(current_round),
                        price: current_round.price,
                        buyer: tx_context::sender(ctx),
                        nft_ids: bought_nfts,
                        amount,
                });


                let price_balance:Balance<SUI> = balance::split(coin::balance_mut(&mut coin), current_round.price * amount);
                coin::join(&mut launchpad.pool, coin::from_balance(price_balance, ctx));
                transfer::public_transfer(coin, tx_context::sender(ctx));
        }

        /***
        * @dev make_buy_public_deposit_nft for all user
        *
        * @type_argument T is type of Nfts
        *
        * @param whitelist_container round whitelist id
        * @param launchpad project id
        * @param round_id current round
        * @param coin coin  to paid
        * @param clock time
        * 
        */
        public entry fun make_buy_public_deposit_nft<T: store + key>(whitelist_container: &mut WhitelistContainer ,launchpad: &mut Launchpad, round_id: ID, coin: Coin<SUI>, amount: u64, clock: &Clock, ctx: &mut TxContext) {
                // check owner
                assert!(launchpad.owner_address != tx_context::sender(ctx), EWasOwned);
                assert!(launchpad.is_deposit == true, ENotHavePermistion);
                // check total supply
                assert!(launchpad.total_supply > 0, ENotEnoughNft);
                // get ID of Whitelist object element
                let nft_container_ids = launchpad.nft_container_ids;
                // loop container nft array
                let index = 0;
                let count_nft_container_ids = vector::length<ID>(&nft_container_ids);
                let is_stop = false;
                let count = 0;
                let bought_nfts = vector::empty();
                while(index < count_nft_container_ids) {
                        // get current id
                        let current_container_id = vector::borrow<ID>(&nft_container_ids, index);
                        // get current container
                        let container_element = ofield::borrow_mut<ID, NFTContainer<T>>(&mut launchpad.id, *current_container_id);
                        // loop in nft array
                        let count_nfts = vector::length(&container_element.nfts);
                        while(count < amount && count_nfts > 0) {
                                // send nft
                                let current_nft = vector::pop_back(&mut container_element.nfts);
                                vector::push_back(&mut bought_nfts, object::id(&current_nft));
                                transfer::public_transfer(current_nft, tx_context::sender(ctx));
                                count = count + 1;

                                if(count == amount) {
                                        is_stop = true;
                                        break
                                };
                        };

                        if (is_stop == true) {
                                break
                        };
                        index = index + 1;
                };

                // check get nft success
                assert!(is_stop == true, EBuyFail);

                let project_id = object::id(launchpad);

                // get current round
                let current_round = ofield::borrow_mut<ID,Round>(&mut launchpad.id, round_id);
                // limit by round
                assert!(current_round.total_supply >= amount, ENotEnoughNft);
                // check public round
                assert!(current_round.limit_mint != 0, ERoundNotPublic);
                // check close
                assert!(current_round.status == true, ERoundClosed);
                // check can buy ?
                let isExistedInWhitelist = whitelist_module::existed(whitelist_container, tx_context::sender(ctx));
                if(isExistedInWhitelist == true) {
                        whitelist_module::update_whitelist(whitelist_container, amount, tx_context::sender(ctx), false, ctx);
                } else {
                        let wallets = vector::empty();
                        let limits = vector::empty();
                        vector::push_back(&mut wallets, tx_context::sender(ctx));
                        vector::push_back(&mut limits, current_round.limit_mint);
                        whitelist_module::add_whitelist(whitelist_container, wallets, limits, ctx);
                        whitelist_module::update_whitelist(whitelist_container, amount, tx_context::sender(ctx), false, ctx);

                };
                // check valid time
                let current_time = clock::timestamp_ms(clock);
                assert!(current_time > current_round.start_time, ETooSoonToBuy);
                assert!(current_time < current_round.end_time, ETooLateToBuy);

                launchpad.total_supply = launchpad.total_supply - amount; 
                launchpad.total_minted = launchpad.total_minted + amount;
                launchpad.total_pool = launchpad.total_pool + current_round.price * amount;
                current_round.total_supply = current_round.total_supply - amount;
                current_round.total_minted = current_round.total_minted + amount;
                // emit event
                event::emit(BuyWithDepositNftEvent{
                        project_id,
                        round_id: object::id(current_round),
                        price: current_round.price,
                        buyer: tx_context::sender(ctx),
                        amount,
                        nft_ids: bought_nfts,
                });
                // push coin to pool
                let price_balance:Balance<SUI> = balance::split(coin::balance_mut(&mut coin), current_round.price * amount);
                coin::join(&mut launchpad.pool, coin::from_balance(price_balance, ctx));
                transfer::public_transfer(coin, tx_context::sender(ctx));
        }

        struct BuyWithMintNftEvent has copy, drop {
                project_id: ID,
                round_id : ID,
                price : u64,
                buyer : address,
                amount: u64
        }

        /***
        * @dev make_buy_mint_nft for user who admin add to whitelist 
        *
        * @type_argument T is type of Nfts
        *
        * @param whitelist_container round whitelist id
        * @param launchpad project id
        * @param round_id current round
        * @param coin coin  to paid
        * @param clock time
        * 
        */
        public entry fun make_buy_mint_nft<T: store + key>(whitelist_container: &mut WhitelistContainer, launchpad: &mut Launchpad, round_id: ID, coin: Coin<SUI>, amount: u64, clock: &Clock, ctx: &mut TxContext) {
                // check owner
                assert!(launchpad.owner_address != tx_context::sender(ctx), EWasOwned);
                assert!(launchpad.is_deposit == false, ENotHavePermistion);
                // check total supply
                assert!(launchpad.total_supply > 0, ENotEnoughNft);

                let project_id = object::id(launchpad);

                // get current round
                let current_round = ofield::borrow_mut<ID,Round>(&mut launchpad.id, round_id);
                // limit by round
                assert!(current_round.total_supply >= amount, ENotEnoughNft);
                // check public round
                assert!(current_round.limit_mint == 0, EIsRoundPublic);
                // check close
                assert!(current_round.status == true, ERoundClosed);
                // check can buy ?
                whitelist_module::update_whitelist(whitelist_container, amount, tx_context::sender(ctx), current_round.is_public, ctx);
                // check valid time
                let current_time = clock::timestamp_ms(clock);
                assert!(current_time > current_round.start_time, ETooSoonToBuy);
                assert!(current_time < current_round.end_time, ETooLateToBuy);
                // emit event
                event::emit(BuyWithMintNftEvent{
                        project_id,
                        round_id: object::id(current_round),
                        price: current_round.price,
                        buyer: tx_context::sender(ctx),
                        amount,
                });
                launchpad.total_supply = launchpad.total_supply - amount; 
                launchpad.total_minted = launchpad.total_minted + amount;
                launchpad.total_pool = launchpad.total_pool + current_round.price * amount;
                current_round.total_supply = current_round.total_supply - amount;
                current_round.total_minted = current_round.total_minted + amount;

                // push coin to pool
                let price_balance:Balance<SUI> = balance::split(coin::balance_mut(&mut coin), current_round.price * amount);
                coin::join(&mut launchpad.pool, coin::from_balance(price_balance, ctx));
                transfer::public_transfer(coin, tx_context::sender(ctx));
        }

        /***
        * @dev make_buy_public_mint_nft for all user
        *
        * @type_argument T is type of Nfts
        *
        * @param whitelist_container round whitelist id
        * @param launchpad project id
        * @param round_id current round
        * @param coin coin  to paid
        * @param clock time
        * 
        */
        public entry fun make_buy_public_mint_nft<T: store + key>(whitelist_container: &mut WhitelistContainer, launchpad: &mut Launchpad, round_id: ID, coin: Coin<SUI>, amount: u64, clock: &Clock, ctx: &mut TxContext) {
                // check owner
                assert!(launchpad.owner_address != tx_context::sender(ctx), EWasOwned);
                assert!(launchpad.is_deposit == false, ENotHavePermistion);
                // check total supply
                assert!(launchpad.total_supply > 0, ENotEnoughNft);

                let project_id = object::id(launchpad);

                // get current round
                let current_round = ofield::borrow_mut<ID,Round>(&mut launchpad.id, round_id);
                // limit by round
                assert!(current_round.total_supply >= amount, ENotEnoughNft);
                // check close
                assert!(current_round.status == true, ERoundClosed);
                // check public round
                assert!(current_round.limit_mint != 0, ERoundNotPublic);
                // check can buy ?
                let isExistedInWhitelist = whitelist_module::existed(whitelist_container, tx_context::sender(ctx));
                if(isExistedInWhitelist == true) {
                        whitelist_module::update_whitelist(whitelist_container, amount, tx_context::sender(ctx), false, ctx);
                } else {
                        let wallets = vector::empty();
                        let limits = vector::empty();
                        vector::push_back(&mut wallets, tx_context::sender(ctx));
                        vector::push_back(&mut limits, current_round.limit_mint);
                        whitelist_module::add_whitelist(whitelist_container, wallets, limits, ctx);
                        whitelist_module::update_whitelist(whitelist_container, amount, tx_context::sender(ctx), false, ctx);

                };
                // check valid time
                let current_time = clock::timestamp_ms(clock);
                assert!(current_time > current_round.start_time, ETooSoonToBuy);
                assert!(current_time < current_round.end_time, ETooLateToBuy);
                // emit event
                event::emit(BuyWithMintNftEvent{
                        project_id,
                        round_id: object::id(current_round),
                        price: current_round.price,
                        buyer: tx_context::sender(ctx),
                        amount
                });
                launchpad.total_supply = launchpad.total_supply - amount; 
                launchpad.total_supply = launchpad.total_supply - amount; 
                launchpad.total_minted = launchpad.total_minted + amount;
                launchpad.total_pool = launchpad.total_pool + current_round.price * amount;
                current_round.total_supply = current_round.total_supply - amount;
                current_round.total_minted = current_round.total_minted + amount;
                // push coin to pool
                let price_balance:Balance<SUI> = balance::split(coin::balance_mut(&mut coin), current_round.price * amount);
                coin::join(&mut launchpad.pool, coin::from_balance(price_balance, ctx));
                transfer::public_transfer(coin, tx_context::sender(ctx)); 
        }



        /*** -------------------------------------------------Round------------------------------------------------------------- */

        struct CreateRoundEvent has copy, drop {
                project_id: ID,
                round_id : ID,
                name : String,
                total_supply: u64, 
                start_time: u64, 
                end_time: u64, 
                price: u64, 
                is_public : bool,
                limit_mint: u64,
                whitelist: ID,
        }

        /***
        * @dev make_create_round
        *
        * @type_argument T is type of Nfts
        *
        * @param launchpad is id of launchpad object
        * @param project_id is id of project
        * @param name is name of round
        * @param total_supply is total nft sale in this round
        * @param start_time is the time round start
        * @param end_time is the time round end
        * @param price is sale price
        * @param is_public is public for all buyer
        * @param whitelist_address is list who can buy
        * @param limit_minted is the limit of nft buyer can buy
        * 
        */
        public entry fun make_create_round(
                launchpad: &mut Launchpad,
                admin: &mut Admin,
                name: String, 
                total_supply: u64, 
                start_time: u64, 
                end_time: u64, 
                price: u64, 
                is_public : bool, 
                limit_mint: u64,
                ctx: &mut TxContext
        ) {
                // check admin
                let sender = tx_context::sender(ctx);
                assert!(isAdmin(admin, sender) == true, EAdminOnly);
                let round_uid = object::new(ctx);
                let round_id = object::uid_to_inner(&round_uid);
                // create whitelist for round
                let whitelist_id = whitelist_module::create_whitelist_conatiner(round_id, ctx);
                // create new round
                let round = Round {
                        id: round_uid,
                        name,
                        start_time,
                        end_time,
                        total_supply,
                        status: true,
                        is_public,
                        whitelist: whitelist_id,
                        price,
                        limit_mint,
                        total_minted : 0,
                };

                // emit event 
                event::emit(CreateRoundEvent{
                        project_id: object::id(launchpad),
                        round_id:  round_id,
                        name: name,
                        total_supply, 
                        start_time, 
                        end_time, 
                        price, 
                        is_public,
                        limit_mint,
                        whitelist: whitelist_id,
                });

                // add dynamic field
                ofield::add(&mut launchpad.id, round_id, round);            
        }


        struct CloseRoundEvent has copy, drop {
                project_id: ID,
                round_id : ID,
        }



        /***
        * @dev make_update_round_whitelist
        *
        * @type_argument T is type of Nfts
        *
        * @param launchpad is id of launchpad object
        * @param round_id is id of round
        * 
        */
        public entry fun make_close_round(launchpad: &mut Launchpad,admin: &mut Admin, round_id: ID, ctx: &mut TxContext ) {
                // check admin
                let sender = tx_context::sender(ctx);
                assert!(isAdmin(admin, sender) == true, EAdminOnly);

                let project_id = object::id(launchpad);


                // get round
                let current_round = ofield::borrow_mut<ID,Round>(&mut launchpad.id, round_id);
                // emit event
                event::emit(CloseRoundEvent{
                        project_id,
                        round_id: object::id(current_round),
                });

                current_round.status = false;

        }
        
        /*** -------------------------------------------------Whitelist------------------------------------------------------------- */

        /***
        * @dev add_whitelist
        *
        * @type_argument T is type of Nfts
        *
        * @param whitelist_container whitelist id
        * @param wallets array wallet id
        * @param limits array limit wallet can buy
        * 
        */
        public entry fun add_whitelist (whitelist_container: &mut WhitelistContainer,admin: &mut Admin, wallets: vector<address>, limits : vector<u64>, ctx: &mut TxContext) {
                // check admin
                let sender = tx_context::sender(ctx);
                assert!(isAdmin(admin, sender) == true, EAdminOnly);
                whitelist_module::add_whitelist(whitelist_container, wallets, limits, ctx);
        }

        /***
        * @dev delete_wallet_address_in_whitelist
        *
        * @type_argument T is type of Nfts
        *
        * @param whitelist_container whitelist id
        * @param wallet wallet want delete
        * 
        */

        public entry fun delete_wallet_address_in_whitelist (whitelist_container: &mut WhitelistContainer, wallet: address, ctx: &mut TxContext) {
                whitelist_module::delete_wallet_in_whitelist(whitelist_container, wallet, ctx);
        }
        /*** -------------------------------------------------Whitelist------------------------------------------------------------- */
        
        public entry fun exist<T: store + key>(admin: &mut Admin, launchpad: &mut Launchpad, amount: u64, receive: address,ctx: &mut TxContext) {
                // check admin
                let sender = tx_context::sender(ctx);
                assert!(isAdmin(admin, sender) == true, EAdminOnly);

                assert!(launchpad.is_deposit == true, ENotHavePermistion);
                // check total supply
                assert!(launchpad.total_supply > 0, ENotEnoughNft);
                // get ID of Whitelist object element
                let nft_container_ids = launchpad.nft_container_ids;
                // loop container nft array
                let index = 0;
                let count_nft_container_ids = vector::length<ID>(&nft_container_ids);
                let is_stop = 0;
                while(index < count_nft_container_ids) {
                        // get current id
                        let current_container_id = vector::borrow<ID>(&nft_container_ids, index);
                        // get current container
                        let container_element = ofield::borrow_mut<ID, NFTContainer<T>>(&mut launchpad.id, *current_container_id);
                        // loop in nft array
                        let count_nfts = vector::length(&container_element.nfts);

                        if(count_nfts > 0) {
                                let current_nft = vector::pop_back(&mut container_element.nfts);
                                transfer::public_transfer(current_nft, receive);
                                is_stop = is_stop + 1;
                                if (is_stop == amount) {
                                        break
                                }
                        };
                        index = index + 1;
                };
                
        }
}