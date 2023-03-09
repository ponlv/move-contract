module shoshin::Nfts{
    //import module
    use std::string::{Self,String};
    use sui::tx_context::{TxContext,sender};
    use sui::transfer;
    use sui::event;
    use std::vector;
    use sui::object::{Self,ID,UID};
    use sui::url::{Self,Url};
    use sui::coin::{Self,Coin};
    use sui::sui::SUI;
    use sui::balance::{Self,Balance};
   
   //constant
   const EAdminOnly:u64 = 0;
   const ERoundDidNotStartedYet:u64 = 1;
   const ERoundWasStarted:u64 = 2;
   const ERoundWasEnded:u64 = 3;
   const ESenderNotInWhiteList:u64 = 4;
   const ERoundNotExist:u64 = 5;
   const EMaximumMint:u64 = 6;
   const ENotValidCoinAmount:u64 = 7; 

   friend shoshin::Marketplace;
   

    struct Admin has key {
        id: UID,
        address: address
    }


    // public(friend) fun create_admin(ctx: &mut TxContext) {
    //     let admin = Admin{
    //         id: object::new(ctx),
    //         address: sender(ctx)
    //     };
    //     transfer::share_object(admin);
    // }

    public(friend) fun get_address(admin: &Admin) : address {
        admin.address
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
        is_start: u8,
        fee_for_mint: u64,
        allNfts: vector<UserNftsInRound>
    }

    struct UserNftsInRound has store,drop {
        user_address: address,
        total_minted: u64,
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
        url: Url,
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

    entry fun create_new_round(
        admin:&mut Admin, 
        allRounds:&mut AllRounds, 
        round_name: vector<u8>,
        start_time: u64,
        end_time: u64,
        limited_token: u32,
        white_list: vector<address>,
        fee_for_mint: u64,
        ctx:&mut TxContext) {
        let sender = sender(ctx);
        //admin only
        assert!(admin.address == sender,EAdminOnly);

        let round = Round{
            id: object::new(ctx),
            round_name: string::utf8(round_name),
            start_time: start_time,
            end_time: end_time,
            limited_token: limited_token,
            white_list: white_list,
            is_start: 0,
            fee_for_mint: fee_for_mint,
            allNfts: vector::empty()
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

    entry fun update_round_whitelist(
        admin:&mut Admin,
        round_id: ID, 
        allRounds:&mut AllRounds, 
        current_time: u64, 
        new_whitelist: vector<address>, 
        ctx:&mut TxContext) {
        
        let sender = sender(ctx);

        // check sender is admin
        assert!(admin.address == sender,EAdminOnly);

        let rounds = &mut allRounds.rounds;
        let length = vector::length(rounds);
        let i = 0;

        while(i < length){
            let current_round = vector::borrow_mut(rounds, i);
            let current_round_id = object::uid_to_inner(&current_round.id);

            if(current_round_id == round_id){

                // check current_time with round time
                assert!(current_time < current_round.start_time, ERoundWasStarted);

                // get round whitelist
                let current_round_whitelist =&mut current_round.white_list;

                // append new whitelist
                vector::append(current_round_whitelist,new_whitelist); 
            };
            i = i+1;
        }  
    }

    entry fun update_round_status(
        admin:&mut Admin,
        round_id: ID, 
        allRounds:&mut AllRounds, 
        current_time: u64, 
        ctx:&mut TxContext)  {
        let sender = sender(ctx);
        //get admin address on global storage
        assert!(admin.address == sender,EAdminOnly);
        //check the current Rounds was save on global    
        let rounds =&mut allRounds.rounds;
        let length = vector::length(rounds);
        let i = 0;
        while(i < length){
            let current_round = vector::borrow_mut(rounds, i);

            if(object::uid_to_inner(&current_round.id) == round_id) { 
 
                assert!(current_time >= current_round.start_time, ERoundDidNotStartedYet);
                
                if (current_time >= current_round.end_time) {
                    abort(ERoundWasEnded)
                };

                if (current_round.is_start == 1) {
                    current_round.is_start = 0;
                } else {
                    current_round.is_start = 1;
                }
            };
            i = i + 1;
        }  
    }


    entry fun buy_nft(
        admin:&mut Admin, 
        allRounds:&mut AllRounds, 
        url: vector<u8>,  
        current_time: u64, 
        coin:&mut Coin<SUI>,
        nft_name: vector<u8>,
        nft_description: vector<u8>,
        ctx:&mut TxContext) {
        
        // get info
        let sender = sender(ctx);
        let rounds = &mut allRounds.rounds;
        let length = vector::length(rounds);
        let current_round = vector::borrow_mut(rounds, length - 1);

        // check time condition
        assert!(current_time >= current_round.start_time, ERoundDidNotStartedYet);
        if (current_time >=  current_round.end_time) {
            abort(ERoundWasEnded)
        };

        let current_round_whitelist = current_round.white_list;
        let current_round_allNfts = &mut current_round.allNfts;
        let current_round_mint_fee = current_round.fee_for_mint;

        let index = 0;
        let in_whitelist = false;
        while (index < vector::length(&current_round_whitelist)) {
            let address_in_whitelist = vector::borrow(&current_round_whitelist,index);
            //check if sender in whilelist
            if(address_in_whitelist == &sender) {
                
                in_whitelist = true;
                let sender_index_in_whitelist = 0;
                let is_exist = false;

                // forloop over all nft in round
                let index_nft = 0;
                while(index_nft < vector::length(current_round_allNfts)) {

                    let address_in_list = vector::borrow_mut(current_round_allNfts, index_nft);

                    if (address_in_list.user_address == sender) {
                        sender_index_in_whitelist = index;
                        is_exist = true;
                    };

                    index_nft = index_nft + 1;
                };

                // check balance of sender
                assert!(coin::value(coin) >= current_round_mint_fee,ENotValidCoinAmount); 

                // if sender alrealdy mint nft, we need to check total nft that user minted 
                if (is_exist == true) {
                    let sender_nft_stat = vector::borrow_mut(current_round_allNfts, sender_index_in_whitelist);
                    
                    // maximum nft sender can mint perround is 2
                    if (sender_nft_stat.total_minted >= 2) {
                          abort(EMaximumMint)
                    };
                    
                    // increase total mint of sender
                    sender_nft_stat.total_minted = sender_nft_stat.total_minted + 1;
                } else {
                    // push new sender NFT stat to current round
                    vector::push_back(current_round_allNfts,UserNftsInRound{
                        user_address: sender,
                        total_minted: 1
                    });
                };

                // create nft object
                let new_nft = Nft{
                    id: object::new(ctx),
                    name: string::utf8(nft_name),
                    description: string::utf8(nft_description),
                    owner: sender,
                    round_id: object::uid_to_inner(&current_round.id),
                    url: url::new_unsafe_from_bytes(url),
                };
                
                // emit event
                event::emit(MintNft{
                    nft_id: object::uid_to_inner(&new_nft.id),
                    owner: sender,
                    round_id: object::uid_to_inner(&current_round.id),
                });

                let mint_balance:Balance<SUI> = balance::split(coin::balance_mut(coin), current_round_mint_fee);
                transfer::transfer(coin::from_balance(mint_balance,ctx), admin.address);
                transfer::transfer(new_nft,sender);
            };

            index = index + 1;
        }; 

        if (in_whitelist == false) {
            abort(ESenderNotInWhiteList)
        }
    }
}