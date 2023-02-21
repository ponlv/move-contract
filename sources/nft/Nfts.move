module shoshin::Nfts{
    //import module
    use std::string::{Self,String};
    use sui::tx_context::{TxContext,sender};
    use sui::transfer;
    use sui::event;
    use std::vector;
    use sui::object::{Self,ID,UID};
    use sui::url::{Self,Url};
   
   //constant
   const EAdminOnly:u64 = 0;
   const ERoundDidNotStartedYet:u64 = 1;
   const ERoundWasStarted:u64 = 2;
   const ERoundWasEnded:u64 = 3;
   const ESenderNotInWhiteList:u64 = 4;
   const ERoundNotExist:u64 = 5;
   

    struct Admin has key {
        id: UID,
        address: address
    }

    /*--------ROUND-----------*/
    struct AllRounds has key {
        id: UID,
        rounds: vector<Round>,
        description: String
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
        round_id: ID,
        url: Url
    }

    struct NftData has copy,drop {
        name: String,
        description: String,
        round_id: ID,
    }

    struct MintNft has copy,drop {
        nft_id: ID,
        owner: address,
        round_id: ID,
    }




    fun init(ctx:&mut TxContext) {
        //set address of deployer to admin
        let admin = Admin{
            id: object::new(ctx),
            address: sender(ctx)
        };
        let rounds = AllRounds{
            id: object::new(ctx),
            rounds: vector::empty(),
            description: string::utf8(b"This object use to save all the rounds")
        };
        // Admin,Round objects will be saved on global storage
        // after the smart contract deployment we will get the ID to access it
        transfer::share_object(admin);
        transfer::share_object(rounds);
    }

    entry fun create_new_round(ctx:&mut TxContext, admin:&mut Admin, allRounds:&mut AllRounds, data: RoundData) {
        
        let sender = sender(ctx);
        //admin only
        assert!(admin.address == sender,EAdminOnly);

       
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
        let current_rounds = &mut allRounds.rounds;
        vector::push_back(current_rounds, round);
    }

    entry fun update_round_whitelist(ctx:&mut TxContext, admin:&mut Admin,round_id: ID, allRounds:&mut AllRounds, current_time: u64, new_whitelist: vector<address>) {
        let sender = sender(ctx);
       
        assert!(admin.address == sender,EAdminOnly);
        //check the current Rounds was save on global    
        let rounds = &mut allRounds.rounds;
        let length = vector::length(rounds);

        let i = 0;
        while(i < length){
             let current_round = vector::borrow_mut(rounds, i);
             let current_round_id = object::uid_to_inner(&current_round.id);
             if(current_round_id == round_id){
                assert!(current_time < current_round.start_time, ERoundWasStarted);
                let current_round_whitelist =&mut current_round.white_list;
                vector::append(current_round_whitelist,new_whitelist);
                
             };
            i = i+1;
        }  
    }

  

    entry fun update_round_status(ctx:&mut TxContext, admin:&mut Admin,round_id: ID, allRounds:&mut AllRounds, current_time: u64)  {
        let sender = sender(ctx);
        //get admin address on global storage
        assert!(admin.address == sender,EAdminOnly);
        //check the current Rounds was save on global    
        let rounds =&mut allRounds.rounds;
        let length = vector::length(rounds);

        let i = 0;
        while(i < length){
             let current_round = vector::borrow_mut(rounds, i);
             if(object::uid_to_inner(&current_round.id) == round_id){
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


    entry fun buy_nft_by_round(ctx:&mut TxContext, nftData: NftData, round_id: ID, allRounds:&mut AllRounds, url:vector<u8>) {
        let sender = sender(ctx);

        let rounds =&mut allRounds.rounds;
        let length = vector::length(rounds);

        //check if user is in the whitelist of the round
        let i = 0;
        while(i < length){
            let current_round = vector::borrow_mut(rounds,i);  
            //check if round is exists on global storage
            if(object::uid_to_inner(&current_round.id) == round_id){
            let current_round_whitelist =&mut current_round.white_list;
            let index = 0;
            while(index < vector::length(current_round_whitelist)) {
                let address_in_list = vector::borrow(current_round_whitelist,index);
                if(address_in_list == &sender){
                    let new_nft = Nft{
                    id: object::new(ctx),
                    name: nftData.name,
                    description: nftData.description,
                    owner: sender,
                    round_id: nftData.round_id,
                    url: url::new_unsafe_from_bytes(url)
                    };

                    event::emit(MintNft{
                        nft_id: object::uid_to_inner(&new_nft.id),
                        owner: sender,
                        round_id: nftData.round_id,
                    });

                    //tranfer new nft to the sender address
                    transfer::transfer(new_nft,sender);

                }else{
                    if(index == vector::length(current_round_whitelist)-1){
                        //abort that sender was not in round's white_list
                        abort(ESenderNotInWhiteList)
                    }
                };
                index=index+1;
            };
        }else{
            if(i == length-1){
                //abort that round is not exists in global storage 
                abort(ERoundNotExist)
            }
        };
        i=i+1;
        }    
    }



}