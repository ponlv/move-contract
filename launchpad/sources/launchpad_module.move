module shoshinlaunchpad::launchpad_module {
        use shoshinnft::nft_module::{Self, Nft};
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


        struct Admin has key {
                id: UID,
                address: address,
                receive_address: address
        }

        struct WhiteList has store,drop {
                user_address: address,
                limit: u64,
        }

        struct Round <T: key + store> has key,store {
                id: UID,
                round_name: String,
                start_time: u64,
                end_time: u64,
                status : bool,
                limit: u32,
                white_list: vector<WhiteList>,
                price: u64,
                is_public: bool,
                nfts : vector<T>,
        }


        struct Project<T: key + store> has key, store {
                id: UID,
                name: String,
                rounds: vector<Round<T>>,
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

        public entry fun create_launchpad<T: store + key>(admin:&mut Admin, name : vector<u8>, description : vector<u8>, ctx: &mut TxContext) {
                let sender = tx_context::sender(ctx);
                let admin_address = admin.address;
                assert!(admin_address == sender,EAdminOnly);
                let launchpad = Launchpad {
                        id: object::new(ctx),
                        admin : admin_address,
                        name: string::utf8(name),
                        description: string::utf8(description)
                };

                event::emit(CreateLaunchpadEvent{
                        launchpad_id: object::id(&launchpad),
                        launchpad_name: launchpad.name,
                        launchpad_admin_address: launchpad.admin,
                });
                transfer::share_object(launchpad);
        }


        struct CreateProjectEvent has copy, drop {
                project_id: ID,
                name : String,
                owner_address: address,
                total_suppy: u64,
        }

        public entry fun make_launchpad_project<T: store + key>(launchpad : &mut Launchpad, admin:&mut Admin, name : vector<u8>, nfts : vector<T>,ctx: &mut TxContext) {
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


        struct DelauchpadEvent has copy, drop {
                project_id: ID,
                owner : ID,
                commission : u64,
                total_pool : u64
        }

        public entry fun make_delauchpad_project<T: store + key>(launchpad : &mut Launchpad, owner : ID, ctx: &mut TxContext) {
                let sender = tx_context::sender(ctx);
                let admin_address = launchpad.admin;
                assert!(admin_address == sender,EAdminOnly);
                let project = ofield::borrow_mut<ID, Project<T>>(&mut launchpad.id, owner);
                let index = 0;
                let length = vector::length(&project.nfts);
                while(index < length) {
                        let current_nft = vector::remove(&mut project.nfts, index);
                        transfer::transfer(current_nft, project.owner_address);
                };

                let commission_value = project.total_pool * project.commission / 100;
                let commission_balance:Balance<SUI> = balance::split(coin::balance_mut(&mut project.pool), project.total_pool - commission_value);
                let revenue_balance:Balance<SUI> = balance::split(coin::balance_mut(&mut project.pool), commission_value);
                transfer::transfer(coin::from_balance(revenue_balance, ctx), project.owner_address);
                transfer::transfer(coin::from_balance(commission_balance, ctx), project.receive_commission_address);
                
                event::emit(DelauchpadEvent{
                        project_id: object::id(project),
                        owner : owner,
                        commission: commission_value,
                        total_pool: project.total_pool,
                });


        }

        struct UpdateCommissionProjectEvent has copy, drop {
                project_id: ID,
                commission : u64
        }

        public entry fun make_update_project_commission<T: store + key>(launchpad : &mut Launchpad, owner : ID, commission : u64,ctx: &mut TxContext) {
                let sender = tx_context::sender(ctx);
                let admin_address = launchpad.admin;
                assert!(admin_address == sender,EAdminOnly);
                let project = ofield::borrow_mut<ID, Project<T>>(&mut launchpad.id, owner);
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

        public entry fun make_update_project_receive_address<T: store + key>(launchpad : &mut Launchpad, owner : ID, receive_address : address, ctx: &mut TxContext) {
                let sender = tx_context::sender(ctx);
                let admin_address = launchpad.admin;
                assert!(admin_address == sender,EAdminOnly);
                let project = ofield::borrow_mut<ID, Project<T>>(&mut launchpad.id, owner);
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
                total_suppy: u32, 
                start_time: u64, 
                end_time: u64, 
                price: u64, 
                is_public : bool,
        }

        public entry fun make_create_round<T: store + key>(
                launchpad: &mut Launchpad,
                owner: ID, 
                name: vector<u8>, 
                total_suppy: u32, 
                start_time: u64, 
                end_time: u64, 
                price: u64, 
                is_public : bool, 
                white_list: vector<WhiteList>, 
                ctx: &mut TxContext
        ) {
                let sender = tx_context::sender(ctx);
                let admin_address = launchpad.admin;
                assert!(admin_address == sender,EAdminOnly);
                let project = ofield::borrow_mut<ID, Project<T>>(&mut launchpad.id, owner);
                let round_id = object::new(ctx);

                let index = 0;
                let nfts : vector<T> = vector::empty();
                while(index < total_suppy) {
                        let last_element : T = vector::pop_back(&mut project.nfts);
                        vector::push_back(&mut nfts, last_element);
                        index = index + 1;
                };

                let new_round = Round<T>{
                        id: round_id,
                        round_name: string::utf8(name),
                        start_time,
                        end_time,
                        limit: total_suppy,
                        status: true,
                        is_public,
                        white_list,
                        price,
                        nfts
                };                
                
                event::emit(CreateRoundEvent{
                        project_id: object::id(project),
                        round_id :  object::id(&new_round),
                        name : string::utf8(name),
                        total_suppy, 
                        start_time, 
                        end_time, 
                        price, 
                        is_public,
                });

                vector::push_back(&mut project.rounds, new_round);
        }



        // public entry fun make_update_round_whitelist<T: store + key>(
        //         launchpad: &mut Launchpad,
        //         owner: ID,
        //         round_id: ID,
        //         white_list: vector<WhiteList>, 
        //         ctx: &mut TxContext
        // ) {
        //         let sender = tx_context::sender(ctx);
        //         let admin_address = launchpad.admin;
        //         assert!(admin_address == sender,EAdminOnly);
        //         let project = ofield::borrow_mut<ID, Project<T>>(&mut launchpad.id, owner);
        //         let index : u64 = 0;
        //         let length = vector::length(&project.rounds);
        //         while(index < length){
        //                 if(object::id(vector::borrow(&project.rounds, index)) == round_id) {
        //                         break
        //                 };
        //                 index = index + 1;
        //         }
        //         let current_round = vector::borrow_mut(&mut project.rounds, index);
        //         current_round.white_list = white_list;
        // }

        struct UpdateRoundWhitelistEvent has copy, drop {
                project_id: ID,
                round_id : ID,
        }

        public entry fun make_update_round_whitelist<T: store + key>(launchpad: &mut Launchpad, owner: ID, round_id: ID, white_list: vector<WhiteList>, ctx: &mut TxContext) {
                let sender = tx_context::sender(ctx);
                let admin_address = launchpad.admin;
                assert!(admin_address == sender,EAdminOnly);
                let project = ofield::borrow_mut<ID, Project<T>>(&mut launchpad.id, owner);
                let index : u64 = 0;
                let length = vector::length(&project.rounds);
                let updated_round_id : ID = object::id(project);
                while(index < length){
                        let current_round = vector::borrow_mut(&mut project.rounds, index);
                        let id = object::id(current_round);
                        if(id == round_id) {
                                current_round.white_list = white_list;
                                updated_round_id = id;
                                break
                        };
                        index = index + 1;
                };
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

        fun is_can_buy(whitelist : &vector<WhiteList>, current_user : address, curent_total_minted : u64) : bool {
                let is_can_buy = false;
                let length = vector::length(whitelist);
                let index = 0;
                while(index < length) {
                        let current_element = vector::borrow(whitelist, index);
                        if(current_element.user_address == current_user && current_element.limit >curent_total_minted) {
                                is_can_buy = true;
                                break
                        };
                };
                is_can_buy
        }

        public entry fun make_buy_nft<T: store + key>(launchpad: &mut Launchpad, coin:&mut Coin<SUI>, owner: ID, round_id: ID, nft: ID, total_bought: u64, current_time : u64, ctx: &mut TxContext) {
                let project = ofield::borrow_mut<ID, Project<T>>(&mut launchpad.id, owner);  
                let index : u64 = 0;
                let length = vector::length(&project.rounds);
                let current_price = 0;
                while(index < length){
                        let current_round = vector::borrow_mut(&mut project.rounds, index);
                        assert!(current_round.is_public == true || is_can_buy(&current_round.white_list, tx_context::sender(ctx), total_bought), 2);
                        let id = object::id(current_round);
                        if(id == round_id) {
                                let nft_index = 0;
                                let nft_length = vector::length(&current_round.nfts);
                                while(nft_index < nft_length) {
                                        if(object::id(vector::borrow(&mut current_round.nfts, nft_index)) == nft) {
                                                let current_nft = vector::remove(&mut current_round.nfts, nft_index);
                                                transfer::transfer(current_nft, tx_context::sender(ctx));
                                                let price_balance:Balance<SUI> = balance::split(coin::balance_mut(coin), current_round.price);
                                                transfer::transfer(coin::from_balance(price_balance, ctx), tx_context::sender(ctx));
                                                current_price = current_round.price;
                                                project.total_pool = project.total_pool + current_round.price;
                                        };
                                };
                                break
                        };
                        index = index + 1;
                };

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

       public entry fun make_close_round<T: store + key>( launchpad: &mut Launchpad, owner: ID, round_id: ID, ctx: &mut TxContext ) {
                let sender = tx_context::sender(ctx);
                let admin_address = launchpad.admin;
                assert!(admin_address == sender,EAdminOnly);
                let project = ofield::borrow_mut<ID, Project<T>>(&mut launchpad.id, owner);
                let index : u64 = 0;
                let length = vector::length(&project.rounds);
                let updated_round_id : ID = object::id(project);
                let not_sold_nfts : vector<T> = vector::empty();
                while(index < length){
                        let current_round = vector::borrow_mut(&mut project.rounds, index);
                        let id = object::id(current_round);
                        if(id == round_id) {
                                let nft_index = 0;
                                let nft_length = vector::length(&current_round.nfts);
                                while(nft_index < nft_length) {
                                        let current_nft = vector::remove(&mut current_round.nfts, nft_index);
                                        vector::push_back(&mut not_sold_nfts, current_nft);
                                        current_round.status = false;
                                };
                                break
                        };
                        index = index + 1;
                };
                vector::append(&mut project.nfts, not_sold_nfts);
                
                event::emit(CloseRoundEvent{
                        project_id: object::id(project),
                        round_id : updated_round_id,
                });
        }

        

}