import Array "mo:base/Array";
import Debug "mo:base/Debug";
import HashMap "mo:base/HashMap";
import Iter "mo:base/Iter";
import Nat8 "mo:base/Nat8";
import Option "mo:base/Option";
import Principal "mo:base/Principal";
import Cycles "mo:base/ExperimentalCycles";
import List "mo:base/List";
import Text "mo:base/Text";
import Trie "mo:base/Trie";
import Blob "mo:base/Blob";
import Buffer "mo:base/Buffer";
import Bool "mo:base/Bool";
import Nat32 "mo:base/Nat32";
import Hex "./lib/Hex";
import Type "./lib/Type";
import Tools "./lib/Tools";
import CF "./lib/CyclesFinance";

shared (msg) actor class ICLighthouse() {

	private stable var owner_ : Principal = msg.caller;

	private var walletCanisterId = "eife2-cqaaa-aaaai-qatkq-cai";
	private let cf : CF.Self = actor ("6nmrm-laaaa-aaaak-aacfq-cai");

	private stable let createWalletFee : Nat64 = 260000;

	type AddressBookItem = Type.AddressBookItem;
	type ControlledWalletItem = Type.ControlledWalletItem;
	type TokenItem = Type.TokenItem;
	type Operation = Type.Operation;
	type Message = Type.Message;
	type WalletItem = Type.WalletItem;
	type TxnRecord = CF.TxnRecord;
	type DappInfo = Type.DappInfo;
	type DappCategory = Type.DappCategory;
	type MetaMask = Type.MetaMask;

	type CyclesWallet = actor {
		wallet_create_wallet : shared (request : CreateCanisterArgs) -> async WalletResultCreate;
		wallet_balance : query () -> async ({ amount : Nat64 });
	};
	type CreateCanisterArgs = {
		cycles : Nat64;
		settings : CanisterSettings;
	};
	type WalletResultCreate = {
		#Ok : { canister_id : Principal };
		#Err : Text;
	};
	type CanisterSettings = {
		controller : ?Principal;
		controllers : ?[Principal];
		compute_allocation : ?Nat;
		memory_allocation : ?Nat;
		freezing_threshold : ?Nat;
	};
	type CreateCyclesWalletArgs = {
		createCanisterArgs : CreateCanisterArgs;
		nonce : Nat;
		txid : Blob;
	};
	private var addressBooksMap = HashMap.HashMap<Principal, [AddressBookItem]>(1, Principal.equal, Principal.hash);
	private var controlledWalletsMap = HashMap.HashMap<Principal, [ControlledWalletItem]>(1, Principal.equal, Principal.hash);
	private var tokensMap = HashMap.HashMap<Principal, [TokenItem]>(1, Principal.equal, Principal.hash);
	private stable var metaMaskTrie : Trie.Trie<Blob, MetaMask> = Trie.empty();

	private stable var defaultWallet : Trie.Trie<Principal, ControlledWalletItem> = Trie.empty();
	private stable var favorites : Trie.Trie<Principal, [Principal]> = Trie.empty();
	private stable var favoritesCount : Trie.Trie<Principal, Nat32> = Trie.empty();
	private stable var isCreateWallet : Trie.Trie<Principal, [Nat]> = Trie.empty();
	private stable var accountName : Trie.Trie<Principal, Text> = Trie.empty();
	private stable var addressBooks_ : [(Principal, [AddressBookItem])] = [];
	private stable var controlledWallets_ : [(Principal, [ControlledWalletItem])] = [];
	private stable var tokensMap_ : [(Principal, [TokenItem])] = [];
	private stable var dappsList = List.nil<DappInfo>();

	private var message = HashMap.HashMap<Text, Message>(1, Text.equal, Text.hash);
	private func keyp(t : Principal) : Trie.Key<Principal> {
		return { key = t; hash = Principal.hash(t) };
	};
	private func keyb(t : Blob) : Trie.Key<Blob> {
		return { key = t; hash = Blob.hash(t) };
	};

	let messageInfo : Message = {
		title = "ICLighthouse";
		content = "hello every one";
		aliveTime = 0;
		status = #always;
	};
	message.put("message", messageInfo);

	// add token
	private func _addTokenItem(canisterId : Principal, symbol : Text, name : Text, decimals : Nat, standard : Text, caller : Principal) {
		let tokens = tokensMap.get(caller);
		let token : TokenItem = {
			canisterId = canisterId;
			symbol = symbol;
			name = name;
			decimals = decimals;
			standard = standard;
		};
		var buf = Buffer.Buffer<TokenItem>(12);
		switch (tokens) {
			case (?tokens_) {
				let _tokens = Array.filter<TokenItem>(
					tokens_,
					func(t : TokenItem) : Bool {
						if (canisterId == t.canisterId) {
							return false;
						};
						buf.add(t);
						return true;
					},
				);
				buf.add(token);
				tokensMap.put(caller, Buffer.toArray(buf));
			};
			case (_) {
				tokensMap.put(caller, [token]);
			};
		};
	};

	private func _removeTokenItem(canisterId : Principal, caller : Principal) {
		let tokens = tokensMap.get(caller);
		switch (tokens) {
			case (?tokens_) {
				let t = Array.filter<TokenItem>(
					tokens_,
					func(t : TokenItem) : Bool {
						if (canisterId == t.canisterId) {
							return false;
						};
						return true;
					},
				);
				tokensMap.put(caller, t);
			};
			case (_) {};
		};
	};

	// add addressbook
	private func _addAddressBook(address : Text, encrypt : Text, caller : Principal) {
		let addressBooks = addressBooksMap.get(caller);
		let addressBook : AddressBookItem = {
			address = address;
			encrypt = encrypt;
		};
		var buf = Buffer.Buffer<AddressBookItem>(12);
		switch (addressBooks) {
			case (?addressBooks_) {
				let _books = Array.filter<AddressBookItem>(
					addressBooks_,
					func(b : AddressBookItem) : Bool {
						if (address == b.address) {
							return false;
						};
						buf.add(b);
						return true;
					},
				);
				buf.add(addressBook);
				addressBooksMap.put(caller, Buffer.toArray(buf));
			};
			case (_) {
				addressBooksMap.put(caller, [addressBook]);
			};
		};
	};

	// remove addressbook
	private func _removeAddressBook(address : Text, caller : Principal) {
		let addressBooks = addressBooksMap.get(caller);
		switch (addressBooks) {
			case (?addressBooks_) {
				let _books = Array.filter<AddressBookItem>(
					addressBooks_,
					func(b : AddressBookItem) : Bool {
						if (address == b.address) {
							return false;
						};
						return true;
					},
				);
				addressBooksMap.put(caller, _books);
			};
			case (_) {};
		};
	};

	private func _addControllWallet(walletId : Principal, caller : Principal) {
		let dWallet = Trie.get(defaultWallet, keyp(caller), Principal.equal);
		switch (dWallet) {
			case (?wallet_) {
				if (wallet_.walletId == walletId) { return };
			};
			case (_) {};
		};
		let controlledWallets = controlledWalletsMap.get(caller);
		let controlledWallet : ControlledWalletItem = {
			walletId = walletId;
			address = Tools.principalToAccount(caller, null);
		};
		var buf = Buffer.Buffer<ControlledWalletItem>(12);
		switch (controlledWallets) {
			case (?controlledWallets_) {
				var _wallets = Array.filter<ControlledWalletItem>(
					controlledWallets_,
					func(w : ControlledWalletItem) : Bool {
						if (w.walletId == walletId) {
							return false;
						};
						buf.add(w);
						return true;
					},
				);
				buf.add(controlledWallet);
				controlledWalletsMap.put(caller, Buffer.toArray(buf));
			};
			case (_) {
				controlledWalletsMap.put(caller, [controlledWallet]);
			};
		};
	};

	private func _removeControllWallet(walletId : Principal, caller : Principal) {
		let controlledWallets = controlledWalletsMap.get(caller);
		switch (controlledWallets) {
			case (?controlledWallets_) {
				if (controlledWallets_.size() == 0) {
					_removeDefaultWallet(caller);
					return;
				};
				let wallet = Array.filter<ControlledWalletItem>(
					controlledWallets_,
					func(c : ControlledWalletItem) : Bool {
						if (walletId == c.walletId) {
							return false;
						};
						return true;
					},
				);
				controlledWalletsMap.put(caller, wallet);
			};
			case (_) {
				_removeDefaultWallet(caller);
			};
		};
	};

	private func _removeDefaultWallet(caller : Principal) {
		let dWallet = Trie.get(defaultWallet, keyp(caller), Principal.equal);
		switch (dWallet) {
			case (?_wallet) {
				defaultWallet := Trie.remove(defaultWallet, keyp(caller), Principal.equal).0;
			};
			case (_) {};
		};
	};

	private func _setDefaultWallet(walletId : Principal, caller : Principal) {
		let controlledWallet : ControlledWalletItem = {
			walletId = walletId;
			address = Tools.principalToAccount(caller, null);
		};
		let oldDefault = Trie.get(defaultWallet, keyp(caller), Principal.equal);
		_removeControllWallet(walletId, caller);
		defaultWallet := Trie.put(defaultWallet, keyp(caller), Principal.equal, controlledWallet).0;
		switch (oldDefault) {
			case (?wallet_) {
				_addControllWallet(wallet_.walletId, caller);
			};
			case (_) {};
		};
	};

	private func _createCyclesWallet() : CyclesWallet {
		actor (walletCanisterId) : actor {
			wallet_create_wallet : shared (request : CreateCanisterArgs) -> async WalletResultCreate;
			wallet_balance : query () -> async ({ amount : Nat64 });
		};
	};

	private func _checkTxRecord(txnRecord : ?TxnRecord, caller : Principal) : Bool {
		switch (txnRecord) {
			case (?txnRecord_) {
				/// check wallet
				switch (txnRecord_.cyclesWallet) {
					case (?cyclesWallet) {
						if (cyclesWallet != Principal.fromText(walletCanisterId)) {
							return false;
						};
					};
					case (_) { return false };
				};
				/// check caller
				let account = Tools.principalToAccountBlob(caller, null);
				if (not (Blob.equal(account, txnRecord_.caller))) {
					return false;
				};
				/// check amount
				switch (txnRecord_.filled.token0Value) {
					case ((#CreditRecord(amount))) {
						if (amount <= 160000000000 or amount >= 1100000000000) {
							return false;
						};
					};
					case (_) { return false };
				};
				return true;
			};
			case (_) { return false };
		};
	};

	private func plusFavoritesCount(pair : Principal) {
		let count = Trie.get(favoritesCount, keyp(pair), Principal.equal);
		switch (count) {
			case (?num) {
				favoritesCount := Trie.put<Principal, Nat32>(favoritesCount, keyp(pair), Principal.equal, num + 1).0;
			};
			case (_) {
				favoritesCount := Trie.put<Principal, Nat32>(favoritesCount, keyp(pair), Principal.equal, 1).0;
			};
		};
	};

	private func subFavoritesCount(pair : Principal) {
		let count = Trie.get(favoritesCount, keyp(pair), Principal.equal);
		switch (count) {
			case (?num) {
				favoritesCount := Trie.put<Principal, Nat32>(favoritesCount, keyp(pair), Principal.equal, num - 1).0;
				if ((num - 1) == 0) {
					favoritesCount := Trie.remove(favoritesCount, keyp(pair), Principal.equal).0;
				};
			};
			case (_) {};
		};
	};

	// controller wallet
	public query (msg) func getWallets() : async [WalletItem] {
		let dWallet = Trie.get(defaultWallet, keyp(msg.caller), Principal.equal);
		var buf = Buffer.Buffer<WalletItem>(12);
		switch (dWallet) {
			case (?wallet) {
				buf.add({
					address = wallet.address;
					walletId = wallet.walletId;
					isDefault = true;
				});
			};
			case (_) {};
		};
		let controlledWallets = controlledWalletsMap.get(msg.caller);
		switch (controlledWallets) {
			case (?_wallets) {
				for (wallet in _wallets.vals()) {
					buf.add({
						address = wallet.address;
						walletId = wallet.walletId;
						isDefault = false;
					});
				};
				return Buffer.toArray(buf);
			};
			case (_) { return Buffer.toArray(buf) };
		};
	};

	// manage wallet
	public shared (msg) func manageWallet(walletId : Principal, op : Operation) : async Bool {
		switch (op) {
			case (#add) {
				_addControllWallet(walletId, msg.caller);
				return true;
			};
			case (#del) {
				_removeControllWallet(walletId, msg.caller);
				return true;
			};
			case (#setDefault) {
				_setDefaultWallet(walletId, msg.caller);
				return true;
			};
		};
	};

	public func addMetaMask(account : Blob, mnemonic : Text) {
		let metaMask = Trie.get(metaMaskTrie, keyb(account), Blob.equal);
		var mnemonicsBuffer = Buffer.Buffer<Text>(4);
		switch (metaMask) {
			case (?m) {
				var mnemonics = m.mnemonic;
				mnemonics := Array.filter(
					mnemonics,
					func(m : Text) : Bool {
						if (m == mnemonic) { return false };
						mnemonicsBuffer.add(m);
						return true;
					},
				);
				mnemonicsBuffer.add(mnemonic);
				var val : MetaMask = {
					account = Hex.encode(Blob.toArray(account));
					mnemonic = Buffer.toArray(mnemonicsBuffer);
				};
				metaMaskTrie := Trie.put(metaMaskTrie, keyb(account), Blob.equal, val).0;
			};
			case (_) {
				var val : MetaMask = {
					account = Hex.encode(Blob.toArray(account));
					mnemonic = [mnemonic];
				};
				metaMaskTrie := Trie.put(metaMaskTrie, keyb(account), Blob.equal, val).0;
			};
		};
	};

	// token
	public query (msg) func getTokens() : async [TokenItem] {
		let tokens = tokensMap.get(msg.caller);
		let token : [TokenItem] = Option.get<[TokenItem]>(tokens, []);
		return token;
	};

	public shared (msg) func manageToken(canisterId : Principal, symbol : Text, name : Text, decimals : Nat, standard : Text, op : Operation) : async Bool {
		switch (op) {
			case (#add) {
				_addTokenItem(canisterId, symbol, name, decimals, standard, msg.caller);
				return true;
			};
			case (#del) {
				_removeTokenItem(canisterId, msg.caller);
				return true;
			};
			case (#setDefault) {
				false;
			};
		};
	};

	public query func getMetaMask(account : Blob) : async ?MetaMask {
		return Trie.get(metaMaskTrie, keyb(account), Blob.equal);
	};

	// addressbook list
	public query (msg) func getAddressBookItems() : async [AddressBookItem] {
		let addressBooks = addressBooksMap.get(msg.caller);
		return Option.get<[AddressBookItem]>(addressBooks, []);
	};

	// manage addressbook
	public shared (msg) func manageAddressBook(address : Text, encrypt : Text, op : Operation) : async Bool {
		switch (op) {
			case (#add) {
				_addAddressBook(address, encrypt, msg.caller);
				return true;
			};
			case (#del) {
				_removeAddressBook(address, msg.caller);
				return true;
			};
			case (#setDefault) {
				false;
			};
		};
	};

	public query func walletCreatedOf(user : Principal) : async Bool {
		let walletNonce = Trie.get(isCreateWallet, keyp(user), Principal.equal);
		switch (walletNonce) {
			case (?_walletNonce) { return true };
			case (_) { return false };
		};
	};

	public shared (msg) func createCyclesWallet(createWalletRequest : CreateCyclesWalletArgs) : async WalletResultCreate {
		var nonce = Trie.get(isCreateWallet, keyp(msg.caller), Principal.equal);
		var buf = Buffer.Buffer<Nat>(12);
		switch (nonce) {
			case (?nonce_) {
				for (r in nonce_.vals()) {
					if (r == createWalletRequest.nonce) {
						return #Err("wallet has been created");
					};
					buf.add(r);
				};
			};
			case (_) {};
		};
		let txnRecord = await cf.txnRecord(createWalletRequest.txid);
		if (not (_checkTxRecord(txnRecord, msg.caller))) {
			return #Err("wallet check failed");
		};
		let cycleWallet = _createCyclesWallet();
		var createCanisterArgs : CreateCanisterArgs = {
			cycles = (createWalletRequest.createCanisterArgs.cycles - createWalletFee);
			settings = createWalletRequest.createCanisterArgs.settings;
		};
		let walletId = await cycleWallet.wallet_create_wallet(createCanisterArgs);
		buf.add(createWalletRequest.nonce);
		isCreateWallet := Trie.put(isCreateWallet, keyp(msg.caller), Principal.equal, Buffer.toArray(buf)).0;
		return walletId;
	};

	public query (msg) func getCyclesWallet() : async Principal {
		return Principal.fromText(walletCanisterId);
	};

	public shared (msg) func updateWalletId(walletId : Principal) {
		assert (msg.caller == owner_);
		walletCanisterId := Principal.toText(walletId);
	};

	public shared func wallet_receive() {
		let amount : Nat = Cycles.available();
		let _accepted = Cycles.accept<system>(amount);
	};

	public query func cyclesBalance() : async Nat {
		let _amount : Nat = Cycles.balance();
	};

	public query func getDappsList(decommend : Bool) : async [DappInfo] {
		if (decommend) {
			var dappInfoBuffer = Buffer.Buffer<DappInfo>(10);
			List.iterate<DappInfo>(
				dappsList,
				func(dapp : DappInfo) {
					if (dapp.decommend) {
						dappInfoBuffer.add(dapp);
					};
				},
			);
			return Buffer.toArray(dappInfoBuffer);
		};
		return List.toArray<DappInfo>(dappsList);
	};

	public shared (msg) func deleteDappInfo(dappId : Nat) {
		assert (msg.caller == owner_);
		dappsList := List.filter<DappInfo>(
			dappsList,
			func(dapp : DappInfo) : Bool {
				if (dapp.dappId == dappId) {
					return false;
				};
				return true;
			},
		);
	};

	public shared (msg) func addDappInfo(name : Text, category : DappCategory, introduce : Text, route : Text, decommend : Bool, logo : Text, order : ?Nat8) : async Nat {
		assert (msg.caller == owner_);
		// reverse the list to get max index
		var lastDapp = List.last<DappInfo>(List.reverse(dappsList));
		var index : Nat = switch lastDapp {
			case (?dapp) { dapp.dappId + 1 };
			case (_) { 1 };
		};
		var o = Option.get<Nat8>(order, 0);
		let dappInfo : DappInfo = {
			dappId = index;
			name = name;
			category = category;
			introduce = introduce;
			route = route;
			decommend = decommend;
			order = o;
			logo = logo;
		};
		dappsList := List.push(dappInfo, dappsList);
		return index;
	};

	// message tip
	public query func getMessage() : async Message {
		return Option.get<Message>(message.get("message"), messageInfo);
	};

	public shared (msg) func updateMessage(m : Message) : async Bool {
		assert (msg.caller == owner_);
		message.put("message", m);
		return true;
	};

	public query (msg) func getWalletCount() : async Nat {
		assert (msg.caller == owner_);
		controlledWalletsMap.size();
	};

	public query func getFavorites(account : Principal) : async [Principal] {
		let favoriteList = Trie.get(favorites, keyp(account), Principal.equal);
		switch (favoriteList) {
			case (?pairs) { pairs };
			case (_) { [] };
		};
	};

	public shared (msg) func addFavorites(pair : Principal) : async () {
		let favoriteList = Trie.get(favorites, keyp(msg.caller), Principal.equal);
		switch (favoriteList) {
			case (?pairs) {
				var buf = Buffer.Buffer<Principal>(Array.size(pairs));
				if (Array.size(pairs) == 0) {
					favorites := Trie.put(favorites, keyp(msg.caller), Principal.equal, [pair]).0;
					Debug.print(debug_show (Array.size(pairs)));
					return;
				};
				label a for (item in pairs.vals()) {
					if (item == pair) {
						continue a;
					};
					buf.add(item);
				};
				buf.add(pair);
				favorites := Trie.put(favorites, keyp(msg.caller), Principal.equal, Buffer.toArray(buf)).0;
			};
			case (_) {
				favorites := Trie.put(favorites, keyp(msg.caller), Principal.equal, [pair]).0;
			};
		};
		plusFavoritesCount(pair);
	};

	public shared (msg) func removeFavorites(pair : Principal) : async Bool {
		let favoriteList = Trie.get(favorites, keyp(msg.caller), Principal.equal);
		switch (favoriteList) {
			case (?pairs) {
				var buf = Buffer.Buffer<Principal>(Array.size(pairs));
				label a for (item in pairs.vals()) {
					if (item == pair) {
						continue a;
					};
					buf.add(item);
				};
				let pairsArr = Buffer.toArray(buf);
				if (Array.size(pairsArr) == 0) {
					favorites := Trie.remove(favorites, keyp(msg.caller), Principal.equal).0;
				} else {
					favorites := Trie.put(favorites, keyp(msg.caller), Principal.equal, pairsArr).0;
				};
				subFavoritesCount(pair);
				return true;
			};
			case (_) { false };
		};
	};

	public shared (msg) func updateFavoritesListOrder(pairsList : [Principal]) : async () {
		let favoriteList = Trie.get(favorites, keyp(msg.caller), Principal.equal);
		switch (favoriteList) {
			case (?_pairs) {
				favorites := Trie.put(favorites, keyp(msg.caller), Principal.equal, pairsList).0;
			};
			case (_) {};
		};
	};

	public query (msg) func getAllFavoritesCount() : async [(Principal, Nat32)] {
		assert (msg.caller == owner_);
		let iter = Trie.iter(favoritesCount);
		let result = Buffer.Buffer<(Principal, Nat32)>(10);
		for ((k, v) in iter) {
			result.add(k, v);
		};
		return Buffer.toArray(result);
	};

	public shared (msg) func updateAccountlName(name : Text) : async () {
		accountName := Trie.put(accountName, keyp(msg.caller), Principal.equal, name).0;
	};

	public query func getAccountName(account : Principal) : async (Principal, ?Text) {
		let name = Trie.get(accountName, keyp(account), Principal.equal);
		return (account, name);
	};

	// update method
	system func preupgrade() {
		addressBooks_ := Iter.toArray(addressBooksMap.entries());
		controlledWallets_ := Iter.toArray(controlledWalletsMap.entries());
		tokensMap_ := Iter.toArray(tokensMap.entries());
	};

	system func postupgrade() {
		addressBooksMap := HashMap.fromIter<Principal, [AddressBookItem]>(
			addressBooks_.vals(),
			1,
			Principal.equal,
			Principal.hash,
		);
		addressBooks_ := [];

		controlledWalletsMap := HashMap.fromIter<Principal, [ControlledWalletItem]>(
			controlledWallets_.vals(),
			1,
			Principal.equal,
			Principal.hash,
		);
		controlledWallets_ := [];

		tokensMap := HashMap.fromIter<Principal, [TokenItem]>(
			tokensMap_.vals(),
			1,
			Principal.equal,
			Principal.hash,
		);
		tokensMap_ := [];
	};

};
