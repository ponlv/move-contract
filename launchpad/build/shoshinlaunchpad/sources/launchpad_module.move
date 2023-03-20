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
                limited_token: u32,
                white_list: vector<WhiteList>,
                price: u64,
                is_public: u8,
                nfts : vector<T>,
        }


        struct Project<T: key + store> has key, store {
                id: UID,
                name: String,
                rounds: vector<Round<T>>,
                owner_address: address,
                total_suppy: u64,
                nfts: vector<T>,
                pool: Coin<SUI>,
                fee : u64,
                receive_fee_address : address,
        }

        struct Projects<T: key + store> has store, key {
                id: UID,
                projects : vector<Project<T>>
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

        public entry fun create_launchpad<T: store + key>(admin:&mut Admin, name : vector<u8>, description : vector<u8>, fee: u64, ctx: &mut TxContext) {
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

        public entry fun make_create_project<T: store + key>(launchpad : &mut Launchpad, admin:&mut Admin, name : vector<u8>, nfts : vector<T>,ctx: &mut TxContext) {
                let size = vector::length(&nfts);
                let project = Project<T> {
                        id: object::new(ctx),
                        name: string::utf8(name),
                        owner_address: tx_context::sender(ctx),
                        rounds: vector::empty(),
                        total_suppy: size,
                        nfts: nfts,
                        pool: coin::from_balance(balance::zero<SUI>(), ctx),
                        fee: 10,
                        receive_fee_address: admin.receive_address,
                };

                event::emit(CreateProjectEvent{
                        project_id: object::id(&project),
                        name: string::utf8(name),
                        owner_address: project.owner_address,
                        total_suppy: size,
                });  

                ofield::add(&mut launchpad.id, project.owner_address, project); 
        }



}