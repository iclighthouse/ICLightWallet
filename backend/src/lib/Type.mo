import Text "mo:base/Text";
import Principal "mo:base/Principal";

module {

	public type AddressBookItem = {
		address : Text;
		encrypt : Text;
	};

	public type ControlledWalletItem = {
		address : [Nat8]; // ic  address
		walletId : Principal;
	};

	public type TokenItem = {
		canisterId : Principal; // token canister ID
		symbol : Text; // token symbol
		name : Text;
		decimals : Nat;
		standard : Text;
	};

	public type Operation = {
		#add;
		#del;
		#setDefault;
	};

	public type Message = {
		title : Text;
		content : Text;
		aliveTime : Nat64;
		status : { #always; #oncetime };
	};

	public type WalletItem = {
		address : [Nat8]; // ic  address
		walletId : Principal;
		isDefault : Bool;
	};

	public type DappCategory = {
		#Swap;
		#Orderbook;
		#NFT;
		#Stable;
	};

	public type DappInfo = {
		dappId : Nat;
		name : Text;
		category : DappCategory;
		introduce : Text;
		route : Text;
		decommend : Bool;
		order : Nat8;
		logo : Text;
	};

	public type MetaMask = {
		account : Text;
		mnemonic : [Text];
	};

};
