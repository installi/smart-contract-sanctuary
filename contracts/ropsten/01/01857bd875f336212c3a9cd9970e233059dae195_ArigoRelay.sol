pragma solidity ^0.4.13;

contract ArigoRelay {
	using SafeMath for uint256;

	/// @dev Holds application state.
	struct Application {
		/// @dev Account allowed to add or remove workers.
		address owner;
		/// @dev Lock to prevent reentrancy.
		bool mutex;
		/// @dev Details for each coin supported by the application.
		mapping (address=>Coin) coins;
		/// @dev Accounts allowed to interact with this contract on the
		/// application&#39;s behalf.
		mapping (address=>bool) workers;
	}

	/// @dev Holds coin-specific state.
	struct Coin {
		/// @dev Withdraw IDs processed.
		mapping(bytes32=>bool) withdrawIds;
		/// @dev Total amount of this coin withdrawn.
		uint256 totalWithdrawn;
		/// @dev Total amount of this coin collected from all users.
		uint256 totalCollected;
		/// @dev Total amount of this coin collected from each user.
		mapping(address=>uint256) totalCollectedFrom;
	}

	/// @dev Raised whenever an application is registered.
	/// @param app The unique ID assigned to the app.
	event Register(uint64 app);
	/// @dev Raised whenever a new worker is added via hire().
	event Hire(uint64 indexed app, address worker);
	/// @dev Raised whenever a worker is removed via fire().
	event Fire(uint64 indexed app, address worker);
	/// @dev Called for each deposit collected in collect().
	event Collect(
		uint64 indexed app,
		address indexed coin,
		address from,
		address vault,
		uint256 amount);
	/// @dev Called for each withdrawal successfully disbursed in withdraw().
	event Withdraw(
		uint64 indexed app,
		address indexed coin,
		bytes32 id,
		address vault,
		address to,
		uint256 amount);

	/// @dev Application-specific states.
	mapping(uint64=>Application) apps;
	/// @dev Number of applications registered. Also the next ID for register().
	uint64 public applicationCount;
	/// @dev Version of this contract.
	string public version = &#39;1.0&#39;;

	modifier onlyOwner(uint64 app) {
		require(apps[app].owner == msg.sender);
		_;
	}

	/// @dev Registers an application.
	/// Off-chain callers can retrieve the generated application ID by watching
	/// for a &#39;Register&#39; event generated by the transaction.
	/// @param owner The account that is allowed to add or remove workers.
	/// @param workers Accounts that are allowed to interact with this contract
	/// on the application&#39;s behalf.
	/// @return The unique ID of the newly registered application.
	function register(address owner, address[] workers)
			external returns (uint64) {

		uint64 appId = uint64(applicationCount);
		applicationCount += 1;
		Application storage _app = apps[appId];
		assert(_app.owner == 0x0);
		_app.owner = owner;
		for (uint256 i = 0; i < workers.length; i++)
			_app.workers[workers[i]] = true;
		emit Register(appId);
		return appId;
	}

	/// @dev Transfer ownership of an application.
	/// The owner is the account allowed to add or remove workers.
	/// @param newOwner New owner.
	function abdicate(uint64 app, address newOwner) external onlyOwner(app) {
		Application storage _app = apps[app];
		_app.owner = newOwner;
	}

	/// @dev Add workers.
	/// @param workers workers to add.
	function hire(uint64 app, address[] workers) external onlyOwner(app) {
		Application storage _app = apps[app];
		for (uint256 i = 0; i < workers.length; i++) {
			_app.workers[workers[i]] = true;
			emit Hire(app, workers[i]);
		}
	}

	/// @dev Remove workers.
	/// @param workers workers to remove.
	function fire(uint64 app, address[] workers) external onlyOwner(app) {
		Application storage _app = apps[app];
		for (uint256 i = 0; i < workers.length; i++) {
			_app.workers[workers[i]] = false;
			emit Fire(app, workers[i]);
		}
	}

	/// @dev Return the total number of a coin collected for an application.
	function getTotalCollected(uint64 app, address coin)
			external view returns (uint256) {

		Application storage _app = apps[app];
		return _app.coins[coin].totalCollected;
	}

	/// @dev Return the total number of a coin collected from a user for an
	/// application.
	function getTotalCollectedFrom(uint64 app, address coin, address from)
			external view returns (uint256) {

		Application storage _app = apps[app];
		return _app.coins[coin].totalCollectedFrom[from];
	}

	/// @dev Return the total number of a coin withdrawn for an
	/// application.
	function getTotalWithdrawn(uint64 app, address coin)
			external view returns (uint256) {

		Application storage _app = apps[app];
		return _app.coins[coin].totalWithdrawn;
	}

	/// @dev Transfers the entire (approved) balance from multiple deposit
	/// addresses (wallets) to the vault.
	/// Prior to this call, the wallet should have given this contract enough
	/// of an allowance to withdraw the entire balance.
	/// @param coins Token contract addresses. If length is 1, the same
	/// token contract is used for all transfers.
	/// @param wallets Source wallets.
	/// @param vault Destination vault.
	function collect(
			uint64 app,
			address[] coins,
			address[] wallets,
			address vault)
			external {

		require(coins.length == 1 || coins.length == wallets.length);
		Application storage _app = apps[app];
		// Caller must be a worker.
		require(_app.workers[msg.sender]);
		// No reentrancy.
		require(!_app.mutex);
		_app.mutex = true;
		for (uint256 i = 0; i < wallets.length; i++) {
			address wallet = wallets[i];
			address coin = coins.length == 1 ? coins[0] : coins[i];
			uint256 amount = _transferAvailable(coin, wallet, vault);
			if (amount > 0) {
				Coin storage _coin = _app.coins[coin];
				// Update counters.
				_coin.totalCollected = _coin.totalCollected.add(amount);
				_coin.totalCollectedFrom[wallet] = _coin.totalCollectedFrom[wallet].add(amount);
			}
			emit Collect(app, coin, wallet, vault, amount);
		}
		_app.mutex = false;
	}

	/// @dev Transfers the entire available balance of &#39;from&#39;.
	/// The available balance is min(allowance, balance).
	/// This function will use _llTransferFrom to make the transfer, so it
	/// will not propagate a revert inside the token contract, instead it will
	/// return 0.
	/// @param coin The address of the token contract.
	/// @param from Account to spend from.
	/// @param to Recipient of tokens.
	/// @return The number of tokens transfered.
	function _transferAvailable(address coin, address from, address to)
			private returns (uint256 amount) {

			ERC20 _token = ERC20(coin);
			uint256 allowance = _token.allowance(from, address(this));
			uint256 balance = _token.balanceOf(from);
			amount = Math.min256(allowance, balance);
			if (amount > 0) {
				if (!_llTransferFrom(coin, from, to, amount))
					amount = 0;
			}
	}

	/// @dev Low-level transferFrom that gracefully handles failure.
	/// Calls transferFrom at the contract address specified by &#39;token&#39;.
	/// @param coin The address of the token contract.
	/// @param from Account to spend from.
	/// @param to Recipient of tokens.
	/// @param amount Amount of tokens to transfer.
	/// @return true if the transferFrom call returns true and does not revert.
	/// Otherwise, returns false.
	function _llTransferFrom(
			address coin, address from, address to, uint256 amount)
			private returns (bool success) {

		bytes4 sig = 0x23b872dd;
		assembly {
			let m := mload(0x40)
			mstore(m, sig)
			mstore(add(m, 0x4), from)
			mstore(add(m, 0x24), to)
			mstore(add(m, 0x44), amount)
			let succeeded := call(gas, coin, 0, m, 0x64, m, 0x20)
			if iszero(succeeded) {mstore(m, 0)}
			success := mload(m)
		}
	}

	/// @dev Transfers tokens out of the vault.
	/// Prior to this call, the vault should have given this contract enough
	/// of an allowance to withdraw these amounts.
	/// @param vault Source wallet.
	/// @param coins Token contract addresses. If length is 1, the same token
	/// contract is used for all transfers.
	/// @param ids Withdrawal ids. Used to prevent duplicates.
	/// @param dsts Recipients.
	/// @param amounts Number of tokens to transfer to each respect recipient.
	function withdraw(
			uint64 app,
			address vault,
			address[] coins,
			bytes32[] ids,
			address[] dsts,
			uint256[] amounts)
			external {

		require(dsts.length == amounts.length && dsts.length == ids.length);
		require(coins.length == 1 || coins.length == dsts.length);
		Application storage _app = apps[app];
		// Caller must be a worker.
		require(_app.workers[msg.sender]);
		// No reentrancy.
		require(!_app.mutex);
		_app.mutex = true;
		// Unfornately, the stack is maxed out so this code is a little illegible.
		for (uint256 i = 0; i < dsts.length; i++) {
			address coin = coins.length == 1 ? coins[0] : coins[i];
			// Only make the withdrawal once per id.
			if (!_app.coins[coin].withdrawIds[ids[i]]) {
				_app.coins[coin].withdrawIds[ids[i]] = true;
				// Perform the transfer.
				if (_llTransferFrom(coin, vault, dsts[i], amounts[i])) {
					// Update counters.
					_app.coins[coin].totalWithdrawn =
						_app.coins[coin].totalWithdrawn.add(amounts[i]);
					emit Withdraw(app, coin, ids[i], vault, dsts[i], amounts[i]);
				}
			}
		}
		_app.mutex = false;
	}
}

contract ERC20Basic {
  function totalSupply() public view returns (uint256);
  function balanceOf(address who) public view returns (uint256);
  function transfer(address to, uint256 value) public returns (bool);
  event Transfer(address indexed from, address indexed to, uint256 value);
}

contract ERC20 is ERC20Basic {
  function allowance(address owner, address spender)
    public view returns (uint256);

  function transferFrom(address from, address to, uint256 value)
    public returns (bool);

  function approve(address spender, uint256 value) public returns (bool);
  event Approval(
    address indexed owner,
    address indexed spender,
    uint256 value
  );
}

library Math {
  function max64(uint64 a, uint64 b) internal pure returns (uint64) {
    return a >= b ? a : b;
  }

  function min64(uint64 a, uint64 b) internal pure returns (uint64) {
    return a < b ? a : b;
  }

  function max256(uint256 a, uint256 b) internal pure returns (uint256) {
    return a >= b ? a : b;
  }

  function min256(uint256 a, uint256 b) internal pure returns (uint256) {
    return a < b ? a : b;
  }
}

library SafeMath {

  /**
  * @dev Multiplies two numbers, throws on overflow.
  */
  function mul(uint256 a, uint256 b) internal pure returns (uint256 c) {
    // Gas optimization: this is cheaper than asserting &#39;a&#39; not being zero, but the
    // benefit is lost if &#39;b&#39; is also tested.
    // See: https://github.com/OpenZeppelin/openzeppelin-solidity/pull/522
    if (a == 0) {
      return 0;
    }

    c = a * b;
    assert(c / a == b);
    return c;
  }

  /**
  * @dev Integer division of two numbers, truncating the quotient.
  */
  function div(uint256 a, uint256 b) internal pure returns (uint256) {
    // assert(b > 0); // Solidity automatically throws when dividing by 0
    // uint256 c = a / b;
    // assert(a == b * c + a % b); // There is no case in which this doesn&#39;t hold
    return a / b;
  }

  /**
  * @dev Subtracts two numbers, throws on overflow (i.e. if subtrahend is greater than minuend).
  */
  function sub(uint256 a, uint256 b) internal pure returns (uint256) {
    assert(b <= a);
    return a - b;
  }

  /**
  * @dev Adds two numbers, throws on overflow.
  */
  function add(uint256 a, uint256 b) internal pure returns (uint256 c) {
    c = a + b;
    assert(c >= a);
    return c;
  }
}