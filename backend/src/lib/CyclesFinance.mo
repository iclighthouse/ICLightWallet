import Time "mo:base/Time";

module {

    public type Address = Text;
    public type Txid = Blob;
    public type AccountId = Blob;
    public type CyclesWallet = Principal;
    public type Shares = Nat;
    public type Data = Blob;
    public type Nonce = Nat;

    public type TokenType = {
        #Cycles;
        #Icp;
        #Token : Principal;
    };
    public type OperationType = {
        #AddLiquidity;
        #RemoveLiquidity;
        #Claim;
        #Swap;
    };

    public type BalanceChange = {
        #DebitRecord : Nat; ///+
        #CreditRecord : Nat; ///-
        #NoChange;
    };
    public type ShareChange = {
        #Mint : Shares;
        #Burn : Shares;
        #NoChange;
    };

    public type Time = Int;

    public type Status = {#Failed; #Pending; #Completed; #PartiallyCompletedAndCancelled; #Cancelled;};

    public type TxnRecord = {
        txid : Txid;
        msgCaller : ?Principal;
        caller : AccountId;
        operation : OperationType;
        account : AccountId;
        cyclesWallet : ?CyclesWallet;
        token0 : TokenType;
        token1 : TokenType;
        fee : { token0Fee : Int; token1Fee : Int };
        shares : ShareChange;
        time : Time.Time;
        index : Nat;
        nonce : Nonce;
        order : { token0Value : ?BalanceChange; token1Value : ?BalanceChange };
        orderMode : { #AMM; #OrderBook };
        orderType : ?{ #LMT; #FOK; #FAK; #MKT };
        filled : { token0Value : BalanceChange; token1Value : BalanceChange };
        details : [{
            counterparty : Txid;
            token0Value : BalanceChange;
            token1Value : BalanceChange;
            time : Time.Time;
        }];
        status : Status;
        data : ?Data;
    };

    public type Self = actor {
        getEvents : shared query ?Address -> async [TxnRecord];
        txnRecord : shared query Txid -> async ?TxnRecord;
    };
};
