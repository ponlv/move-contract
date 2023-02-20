module shoshin::Nfts{
    //import module
    use std::string::{Self,String};
    use sui::tx_context::{TxContext,sender};
    use sui::transfer;
    use sui::event;
    use std::vector;
    use sui::object::{Self,ID,UID};
   
   //constant
   const EAdminOnly:u64 = 0;
   const ERoundDidNotStartedYet:u64 = 1;
   const ERoundWasStarted:u64 = 2;
   const ERoundWasEnded:u64 = 3;
   

    
    struct Admin has key{
        address: address,
    }

    /*--------ROUND-----------*/
    struct AllRounds has key{
        admin_address: address,
        rounds: vector<Round>
    }

    struct Round has key,store {
        id: UID,
        round_name: String,
        start_time: u64,
        end_time: u64,
        limited_token: u32,
        white_list: vector<address>,
        is_start: u8
    }

    struct RoundData has store,drop,copy {
        round_name: String,
        start_time: u64,
        end_time: u64,
        limited_token: u32,
        white_list: vector<address>
    }

    struct CreateRoundEvent has copy,drop {
        round_id: ID,
        admin_address: address,
        round_name: String
    }


    /*---------------NFT---------------*/
    struct Nft has key {
        id: UID,
        name: String,
        description: String,
        owner: address,
        round_id: ID
    }

    struct NftData has copy,drop {
        name: String,
        description: String,
        round_id: ID,
    }

    struct MintNft has copy,drop{
        nft_id: ID,
        owner: address,
        round_id: ID,
    }




    fun init(ctx:&mut TxContext){
        //set address of deployer to admin
        let admin = Admin{
            address: sender(ctx)
        };
        let rounds = AllRounds{
            admin_address: sender(ctx),
            rounds: vector::empty()
        };
        // Admin object to save it on blockchain
       transfer::share_object(admin);
       transfer::share_object(rounds);
    }


    //Read the address of admin was saved on global storage
    public fun get_admin_address(addr: address): address acquires Admin {
        borrow_global<Admin>(addr).address
    }

    entry fun create_new_round(ctx:&mut TxContext, data:&mut RoundData)  acquires Admin,AllRounds {
        
        let sender = sender(ctx);
        //get admin address on global storage.
        let admin_address = get_admin_address(sender);
        assert!(admin_address == sender,EAdminOnly);

       
        let round = Round{
            id: object::new(ctx),
            round_name: data.round_name,
            start_time: data.start_time,
            end_time: data.end_time,
            limited_token: data.limited_token,
            white_list: data.white_list,
            is_start: 0
        };

        //emit event
        event::emit(CreateRoundEvent{
            round_id: object::uid_to_inner(&round.id),
            admin_address: sender,
            round_name: round.round_name
        });
       
     //add new round into the round_vector on global storage
        let current_all_rounds = borrow_global_mut<AllRounds>(sender);
        let current_rounds =&mut current_all_rounds.rounds;
        vector::push_back(current_rounds, round);
    }

    entry fun update_round_whitelist(ctx:&mut TxContext, round_id: &UID,current_time: u64, new_whitelist: vector<address>) acquires AllRounds,Admin {
        let sender = sender(ctx);
        //get admin address on global storage.
        let admin_address = get_admin_address(sender);
        assert!(admin_address == sender,EAdminOnly);
        //check the current Rounds was save on global    
        let rounds = &mut borrow_global_mut<AllRounds>(sender).rounds;
        let length = vector::length(rounds);

        let i = 0;
        while(i < length){
             let current_round = vector::borrow_mut(rounds, i);
             if(&current_round.id == round_id){
                assert!(current_time < current_round.start_time, ERoundWasStarted);
                let current_round_whitelist =&mut current_round.white_list;
                vector::append(current_round_whitelist,new_whitelist);
                
             };
            i = i+1;
        }  
    }

  

    entry fun update_round_status(ctx:&mut TxContext, current_time: u64,round_id: &UID) acquires AllRounds,Admin {
        let sender = sender(ctx);
        //get admin address on global storage.
        let admin_address = get_admin_address(sender);
        assert!(admin_address == sender,EAdminOnly);
        //check the current Rounds was save on global    
        let rounds =&mut borrow_global_mut<AllRounds>(sender).rounds;
        let length = vector::length(rounds);

        let i = 0;
        while(i < length){
             let current_round = vector::borrow_mut(rounds, i);
             if(&current_round.id == round_id){
                assert!(current_time >= current_round.start_time, ERoundDidNotStartedYet);
                assert!(current_time < current_round.end_time, ERoundWasEnded);
                if (current_round.is_start == 1) {
                    current_round.is_start = 0;
                }else{
                    current_round.is_start = 1;
                }
             };
            i = i+1;
        }  
    }


    entry fun buy_nft(ctx:&mut TxContext, nftData: &NftData) {
        let sender = sender(ctx);

        //check if user is in the whitelist of the round, for now this checking will be proccessed on the web side
        
        let new_nft = Nft{
            id: object::new(ctx),
            name: nftData.name,
            description: nftData.description,
            owner: sender,
            round_id: nftData.round_id,
        };

        event::emit(MintNft{
            nft_id: object::uid_to_inner(&new_nft.id),
            owner: sender,
            round_id: nftData.round_id,
        });

        //tranfer new nft to the sender address
        transfer::transfer(new_nft,sender);
    }



}