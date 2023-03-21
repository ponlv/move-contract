module shoshinlaunchpad::launchpad_module {
        // use shoshinnft::nft_module::{Self, Nft};
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



        struct Admin has key {
                id: UID,
                address: address,
                receive_address: address
        }

        struct WhiteList has store,drop {
                user_address: address,
                limit: u64,
                bought: u64,
        }

        struct Round has key,store {
                id: UID,
                round_name: String,
                start_time: u64,
                end_time: u64,
                status : bool,
                total_suppy: u64,
                whitelist: vector<WhiteList>,
                price: u64,
                is_public: bool,
        }


        struct Project<T: key + store> has key, store {
                id: UID,
                name: String,
                rounds: vector<Round>,
                owner_address: address,
                total_suppy: u64,
                nfts: vector<T>,
                total_pool: u64,
                pool: Coin<SUI>,
                commission: u64,
                receive_commission_address : address,
        }

        struct Launchpad has key {
                id: UID,
                admin : address,
                name : String,
                description : String,
        }

        fun init(ctx:&mut TxContext) {
                let admin = Admin{
                        id: object::new(ctx),
                        address: tx_context::sender(ctx),
                        receive_address: tx_context::sender(ctx)
                };
                transfer::share_object(admin);
        }

        /***
        * @dev change_receive_address
        *
        *
        * @param admin is admin id
        * @param new_receive_address is new admin resceive address
        * 
        */

        public entry fun change_receive_address(admin:&mut Admin, new_receive_address: address, ctx:&mut TxContext){
                let sender = tx_context::sender(ctx);
                assert!(admin.address == sender,EAdminOnly);
                admin.receive_address = new_receive_address;
        }

        struct CreateLaunchpadEvent has copy, drop {
                launchpad_id: ID,
                launchpad_name: String,
                launchpad_admin_address: address,
        }

        /***
        * @dev create_launchpad
        *
        *
        * @param admin is admin id
        * @param name is name of project
        * @param description is description of launchpad
        * 
        */

        public entry fun create_launchpad(admin:&mut Admin, name : vector<u8>, description : vector<u8>, ctx: &mut TxContext) {
                // check admin
                let sender = tx_context::sender(ctx);
                let admin_address = admin.address;
                assert!(admin_address == sender,EAdminOnly);
                let launchpad = Launchpad {
                        id: object::new(ctx),
                        admin : admin_address,
                        name: string::utf8(name),
                        description: string::utf8(description)
                };

                //emit event
                event::emit(CreateLaunchpadEvent{
                        launchpad_id: object::id(&launchpad),
                        launchpad_name: launchpad.name,
                        launchpad_admin_address: launchpad.admin,
                });

                // share
                transfer::share_object(launchpad);
        }


        struct CreateProjectEvent has copy, drop {
                project_id: ID,
                name : String,
                owner_address: address,
                total_suppy: u64,
        }

        /***
        * @dev make_single_launchpad_project
        *
        * @type_argument T is type of Nfts
        *
        * @param launchpad is id of launchpad object
        * @param admin is admin id
        * @param name is name of project
        * @param nft is id of nft want list
        * 
        */

        public entry fun make_single_launchpad_project<T: store + key>(launchpad : &mut Launchpad, admin:&mut Admin, name : vector<u8>, nft : T,ctx: &mut TxContext) {
                let nfts: vector<T> = vector::empty();
                vector::push_back(&mut nfts, nft);
                let size = vector::length(&nfts);
                let project = Project<T> {
                        id: object::new(ctx),
                        name: string::utf8(name),
                        owner_address: tx_context::sender(ctx),
                        rounds: vector::empty(),
                        total_suppy: size,
                        total_pool : 0,
                        nfts: nfts,
                        pool: coin::from_balance(balance::zero<SUI>(), ctx),
                        commission: 10,
                        receive_commission_address: admin.receive_address,
                };

                event::emit(CreateProjectEvent{
                        project_id: object::id(&project),
                        name: string::utf8(name),
                        owner_address: project.owner_address,
                        total_suppy: size,
                });  

                ofield::add(&mut launchpad.id, object::id(&project), project); 
        }

        struct AddNftToProject has copy, drop {
                project_id: ID,
                nft_id: ID,
        }

        /***
        * @dev make_add_item_single_launchpad
        *
        * @type_argument T is type of Nfts
        *
        * @param launchpad is id of launchpad object
        * @param project_id is project id
        * @param nft is id of nft want list
        * 
        */

        public entry fun make_add_item_single_launchpad<T: store + key>(launchpad : &mut Launchpad, project_id : ID, nft : T,ctx: &mut TxContext) {
                let project = ofield::borrow_mut<ID, Project<T>>(&mut launchpad.id, project_id);
                assert!(project.owner_address == tx_context::sender(ctx), EWrongProjectOwner);
                event::emit(AddNftToProject{
                        project_id: object::id(project),
                        nft_id: object::id(&nft) 
                });  
                vector::push_back(&mut project.nfts, nft);
                project.total_suppy = project.total_suppy + 1;
        }

        /***
        * @dev make_launchpad_project
        *
        * @type_argument T is type of Nfts
        *
        * @param launchpad is id of launchpad object
        * @param admin is admin id
        * @param name is name of project
        * @param nfts is all nft want launchpad
        * 
        */
        
        public entry fun make_launchpad_project<T: store + key>(launchpad : &mut Launchpad, admin:&mut Admin, name : vector<u8>, nfts : vector<T>,ctx: &mut TxContext) {
                // create project
                let size = vector::length(&nfts);
                let project = Project<T> {
                        id: object::new(ctx),
                        name: string::utf8(name),
                        owner_address: tx_context::sender(ctx),
                        rounds: vector::empty(),
                        total_suppy: size,
                        total_pool : 0,
                        nfts: nfts,
                        pool: coin::from_balance(balance::zero<SUI>(), ctx),
                        commission: 10,
                        receive_commission_address: admin.receive_address,
                };

                // emit event
                event::emit(CreateProjectEvent{
                        project_id: object::id(&project),
                        name: string::utf8(name),
                        owner_address: project.owner_address,
                        total_suppy: size,
                });  

                // add dynamic field
                ofield::add(&mut launchpad.id, object::id(&project), project); 
        }


        struct DelauchpadEvent has copy, drop {
                project_id: ID,
                owner : address,
                commission : u64,
                total_pool : u64
        }
        /***
        * @dev make_delauchpad_project
        *
        * @type_argument T is type of Nfts
        *
        * @param launchpad is id of launchpad object
        * @param project_id is id of projec
        * 
        */

        public entry fun make_delauchpad_project<T: store + key>(launchpad : &mut Launchpad, project_id : ID, ctx: &mut TxContext) {
                //check admin
                let sender = tx_context::sender(ctx);
                let admin_address = launchpad.admin;
                assert!(admin_address == sender,EAdminOnly);

                // borrow mut from launchpad
                let project = ofield::borrow_mut<ID, Project<T>>(&mut launchpad.id, project_id);
                let project_nft = &mut project.nfts;
                let index = 0;
                let length = vector::length(project_nft);
                while(index < length) {
                        let current_nft = vector::pop_back(project_nft);
                        transfer::transfer(current_nft, project.owner_address);
                        index = index + 1;
                };

                // callculator commisson
                let commission_value = project.total_pool * project.commission / 100;
                let commission_balance:Balance<SUI> = balance::split(coin::balance_mut(&mut project.pool), commission_value);
                let revenue_balance:Balance<SUI> = balance::split(coin::balance_mut(&mut project.pool), project.total_pool - commission_value);
                transfer::transfer(coin::from_balance(revenue_balance, ctx), project.owner_address);
                transfer::transfer(coin::from_balance(commission_balance, ctx), project.receive_commission_address);
                project.total_pool = 0;
                
                // event
                event::emit(DelauchpadEvent{
                        project_id: object::id(project),
                        owner : project.owner_address,
                        commission: commission_value,
                        total_pool: project.total_pool,
                });


        }

        struct UpdateCommissionProjectEvent has copy, drop {
                project_id: ID,
                commission : u64
        }

        /***
        * @dev make_update_project_receive_address
        *
        * @type_argument T is type of Nfts
        *
        * @param launchpad is id of launchpad object
        * @param project_id is id of project
        * @param commission is the commission ( % )
        * 
        */

        public entry fun make_update_project_commission<T: store + key>(launchpad : &mut Launchpad, project_id : ID, commission : u64,ctx: &mut TxContext) {
                let sender = tx_context::sender(ctx);
                let admin_address = launchpad.admin;
                assert!(admin_address == sender,EAdminOnly);
                let project = ofield::borrow_mut<ID, Project<T>>(&mut launchpad.id, project_id);
                event::emit(UpdateCommissionProjectEvent{
                        project_id: object::id(project),
                        commission: commission
                });
                project.commission = commission
        }

        struct UpdateReceiveProjectEvent has copy, drop {
                project_id: ID,
                receive_address : address
        }

        /***
        * @dev make_update_project_receive_address
        *
        * @type_argument T is type of Nfts
        *
        * @param launchpad is id of launchpad object
        * @param project_id is id of project
        * @param receive_address is the commission address
        * 
        */

        public entry fun make_update_project_receive_address<T: store + key>(launchpad : &mut Launchpad, project_id : ID, receive_address : address, ctx: &mut TxContext) {
                let sender = tx_context::sender(ctx);
                let admin_address = launchpad.admin;
                assert!(admin_address == sender,EAdminOnly);
                let project = ofield::borrow_mut<ID, Project<T>>(&mut launchpad.id, project_id);
                event::emit(UpdateReceiveProjectEvent{
                        project_id: object::id(project),
                        receive_address,
                });
                project.receive_commission_address = receive_address
        }

        struct CreateRoundEvent has copy, drop {
                project_id: ID,
                round_id : ID,
                name : String,
                total_suppy: u64, 
                start_time: u64, 
                end_time: u64, 
                price: u64, 
                is_public : bool,
        }

        /***
        * @dev make_create_round
        *
        * @type_argument T is type of Nfts
        *
        * @param launchpad is id of launchpad object
        * @param project_id is id of project
        * @param name is name of round
        * @param total_suppy is total nft sale in this round
        * @param start_time is the time round start
        * @param end_time is the time round end
        * @param price is sale price
        * @param is_public is public for all buyer
        * @param white_list_address is list who can buy
        * @param white_list_limit is the limit of nft buyer can buy
        * 
        */
        public entry fun make_create_round<T: store + key>(
                launchpad: &mut Launchpad,
                project_id: ID, 
                name: vector<u8>, 
                total_suppy: u64, 
                start_time: u64, 
                end_time: u64, 
                price: u64, 
                is_public : bool, 
                white_list_address: vector<address>, 
                white_list_limit : vector<u64>,
                ctx: &mut TxContext) {
                // check admin
                let sender = tx_context::sender(ctx);
                let admin_address = launchpad.admin;
                let whitelist_length = vector::length(&white_list_address);
                assert!(admin_address == sender,EAdminOnly);
                assert!(whitelist_length == vector::length(&white_list_limit), EWhiteListInCorrect);
                // get project from launchpad
                let project = ofield::borrow_mut<ID, Project<T>>(&mut launchpad.id, project_id);
                assert!(total_suppy < project.total_suppy, EWrongTotalSupply);
                let rounds = &mut project.rounds;
                let round_id = object::new(ctx);

                // combie address and limit to whitelist
                let whitelist_index = 0;
                let new_whitelist: vector<WhiteList> = vector::empty();
                while(whitelist_index < whitelist_length) {
                        vector::push_back(&mut new_whitelist, WhiteList {
                                user_address : vector::pop_back(&mut white_list_address),
                                limit : vector::pop_back(&mut white_list_limit),
                                bought : 0,
                        });
                        whitelist_index = whitelist_index + 1;
                };

                // create new row
                let new_round = Round {
                        id: round_id,
                        round_name: string::utf8(name),
                        start_time,
                        end_time,
                        total_suppy,
                        status: true,
                        is_public,
                        whitelist: new_whitelist,
                        price,
                };

                // emit event
                event::emit(CreateRoundEvent{
                        project_id: project_id,
                        round_id :  object::id(&new_round),
                        name : string::utf8(name),
                        total_suppy, 
                        start_time, 
                        end_time, 
                        price, 
                        is_public,
                });

                // push new round to old round list
                vector::push_back(rounds, new_round);            
        }

        struct UpdateRoundWhitelistEvent has copy, drop {
                project_id: ID,
                round_id : ID,
        }


        /***
        * @dev make_update_round_whitelist
        *
        * @type_argument T is type of Nfts
        *
        * @param launchpad is id of launchpad object
        * @param project_id is id of project
        * @param round_id is id of round
        * @param white_list_address is list who can buy
        * @param white_list_limit is the limit of nft buyer can buy
        * 
        */

        public entry fun make_update_round_whitelist<T: store + key>(launchpad: &mut Launchpad, project_id: ID, round_id: ID, white_list_address: vector<address>, white_list_limit: vector<u64>, current_time: u64, ctx: &mut TxContext) {
                // check admin, whitelist rule
                let sender = tx_context::sender(ctx);
                let admin_address = launchpad.admin;
                let whitelist_length = vector::length(&white_list_address) ;
                assert!(admin_address == sender,EAdminOnly);
                assert!(whitelist_length == vector::length(&white_list_limit),EWhiteListInCorrect);

                // borrow project from launchpad
                let project = ofield::borrow_mut<ID, Project<T>>(&mut launchpad.id, project_id);
                
                // create a loop to get the correct round with round id and update whitelist to new witelist
                let index = 0;
                let length = vector::length(&project.rounds);
                let updated_round_id : ID = object::id(project);
                while(index < length){
                        let current_round = vector::borrow_mut(&mut project.rounds, index);
                        assert!(current_time < current_round.start_time, ERoundStarted);
                        let id = object::id(current_round);
                        if(id == round_id) {
                                let whitelist_index = 0;
                                let new_whitelist: vector<WhiteList> = vector::empty();
                                while(whitelist_index < whitelist_length) {
                                        vector::push_back(&mut new_whitelist, WhiteList {
                                                user_address: vector::pop_back(&mut white_list_address),
                                                limit:  vector::pop_back(&mut white_list_limit),
                                                bought: 0
                                        });
                                        whitelist_index = whitelist_index + 1;
                                };
                                current_round.whitelist = new_whitelist;
                                updated_round_id = id;
                                break
                        };
                        index = index + 1;
                };

                // emit event
                event::emit(UpdateRoundWhitelistEvent{
                        project_id: object::id(project),
                        round_id : updated_round_id,
                });
        }

        struct BuyNftEvent has copy, drop {
                project_id: ID,
                round_id : ID,
                nft_id : ID,
                price : u64,
                buyer : address
        }

        /***
        * @dev make_update_round_whitelist
        *
        * @type_argument T is type of Nfts
        *
        * @param launchpad is id of launchpad object
        * @param coin paid wallet
        * @param project_id is id of project
        * @param round_id is id of round
        * @param nft is id of nft want buy
        * 
        */

        public entry fun make_buy_nft<T: store + key>(launchpad: &mut Launchpad, coin:&mut Coin<SUI>, project_id: ID, round_id: ID, nft: ID, current_time: u64, ctx: &mut TxContext) {
                // borrow mut from launchpad
                let project = ofield::borrow_mut<ID, Project<T>>(&mut launchpad.id, project_id);  

                // check owner
                assert!(project.owner_address != tx_context::sender(ctx), EWasOwned);
                let current_rounds = &mut project.rounds;
                let current_nfts = &mut project.nfts;

                // get correct round
                let index = 0;
                let length = vector::length(current_rounds);
                let current_price = 0;
                while(index < length){
                        let current_round = vector::borrow_mut(current_rounds, index);
                        let id = object::id(current_round);
                        let is_can_buy = false;
                        let current_whitelist = &mut current_round.whitelist;
                        
                        // checkout time
                        assert!(current_time > current_round.start_time, ETooSoonToBuy);
                        assert!(current_time < current_round.end_time, ETooLateToBuy);

                        // correct round
                        if(id == round_id) {

                        // check whitelist
                        let whitelist_length = vector::length(current_whitelist);
                        let whitelist_index = 0;
                                while(whitelist_index < whitelist_length) {
                                        let current_element = vector::borrow_mut(current_whitelist, whitelist_index);
                                        // conndition user in whitelist and bought < limit, add bought and check whitelist
                                        if(current_element.user_address == tx_context::sender(ctx) && current_element.limit > current_element.bought) {
                                                is_can_buy = true;
                                                current_element.bought = current_element.bought + 1;
                                                break
                                        };
                                        whitelist_index = whitelist_index + 1;
                                };
                                assert!(current_round.is_public == true || is_can_buy, ECantBuy);

                                // update
                                current_round.total_suppy = current_round.total_suppy - 1;
                                current_price = current_round.price;
                                project.total_pool = project.total_pool + current_round.price;
                                break
                        };
                        index = index + 1;
                };
                // transfer
                let current_nft = vector::pop_back(current_nfts);
                transfer::transfer(current_nft, tx_context::sender(ctx));
                let price_balance:Balance<SUI> = balance::split(coin::balance_mut(coin), current_price);
                coin::join(&mut project.pool, coin::from_balance(price_balance, ctx));
                project.total_suppy = project.total_suppy - 1;

                // emit event
                event::emit(BuyNftEvent{
                        project_id: object::id(project),
                        round_id,
                        nft_id : nft,
                        price : current_price,
                        buyer : tx_context::sender(ctx)
                });
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
        * @param project_id is id of project
        * @param round_id is id of round
        * 
        */

        public entry fun make_close_round<T: store + key>( launchpad: &mut Launchpad, project_id: ID, round_id: ID, ctx: &mut TxContext ) {
                // check admin
                let sender = tx_context::sender(ctx);
                let admin_address = launchpad.admin;
                assert!(admin_address == sender,EAdminOnly);

                // borrow mut from launchpad
                let project = ofield::borrow_mut<ID, Project<T>>(&mut launchpad.id, project_id);

                // get correct round to update
                let index = 0;
                let length = vector::length(&project.rounds);
                let updated_round_id : ID = object::id(project);
                while(index < length){
                        let current_round = vector::borrow_mut(&mut project.rounds, index);
                        let id = object::id(current_round);
                        if(id == round_id) {
                                // total supply = 0, status = false
                                current_round.total_suppy = 0;
                                current_round.status = false;
                                break
                        };
                        index = index + 1;
                };
                
                // emit event
                event::emit(CloseRoundEvent{
                        project_id: object::id(project),
                        round_id : updated_round_id,
                });
        }
}