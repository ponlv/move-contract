# contract

Shoshin Square contract

## Launchpad

### How to deposit NFT to a Project?

#### You need to Prepare

- Please make sure you already have a Project running in the Launchpad [#launchpad_id].
- Get Your NFT Type and NFT Object Id in SUI Explorer [#type] and [#object_id].
- We will provide [#package_id] for you.

#### Call this statement if your wallet is in terminal

```
sui client call --package <package_id> --module launchpad_module --function "make_deposit" --type-args <type> --args <launchpad_id> <object_id> --gas-budget 1000000000
```

### If your wallet is in browser

- Visit https://explorer.sui.io/object/<package_id>
- Expand the "make_deposit" function:
- Fill arguments :
  -- Type0 : <type>
  -- Arg0 : <launchpad_id>
  -- Arg1 : <object_id>
