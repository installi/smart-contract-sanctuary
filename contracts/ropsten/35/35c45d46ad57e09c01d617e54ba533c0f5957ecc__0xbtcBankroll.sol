pragma solidity 0.4.25;

contract _0xbtcnnInterface {
    function buyAndSetDivPercentage(uint _0xbtcAmount, address _referredBy, uint8 _divChoice, string providedUnhashedPass) public returns (uint);
    function balanceOf(address who) public view returns (uint);
    function transfer(address _to, uint _value)     public returns (bool);
    function transferFrom(address _from, address _toAddress, uint _amountOfTokens) public returns (bool);
    function exit() public;
    function sell(uint amountOfTokens) public;
    function withdraw(address _recipient) public;
}

contract ERC20Interface {

    function totalSupply() public constant returns (uint);
    function balanceOf(address tokenOwner) public constant returns (uint balance);
    function allowance(address tokenOwner, address spender) public constant returns (uint remaining);
    function transfer(address to, uint tokens) public returns (bool success);
    function approve(address spender, uint tokens) public returns (bool success);
    function transferFrom(address from, address to, uint tokens) public returns (bool success);
    event Transfer(address indexed from, address indexed to, uint tokens);
    event Approval(address indexed tokenOwner, address indexed spender, uint tokens);

}

contract ERC223Receiving {
    function tokenFallback(address _from, uint _amountOfTokens, bytes _data) public returns (bool);
}

contract _0xbtcBankroll is ERC223Receiving {
    using SafeMath for uint;

    /*=================================
    =              EVENTS            =
    =================================*/

    event Confirmation(address indexed sender, uint indexed transactionId);
    event Revocation(address indexed sender, uint indexed transactionId);
    event Submission(uint indexed transactionId);
    event Execution(uint indexed transactionId);
    event ExecutionFailure(uint indexed transactionId);
    event Deposit(address indexed sender, uint value);
    event OwnerAddition(address indexed owner);
    event OwnerRemoval(address indexed owner);
    event WhiteListAddition(address indexed contractAddress);
    event WhiteListRemoval(address indexed contractAddress);
    event RequirementChange(uint required);
    event DevWithdraw(uint amountTotal, uint amountPerPerson);
    event _0xBTCLogged(uint amountReceived, address sender);
    event BankrollInvest(uint amountReceived);
    event DailyTokenAdmin(address gameContract);
    event DailyTokensSent(address gameContract, uint tokens);
    event DailyTokensReceived(address gameContract, uint tokens);

    /*=================================
    =        WITHDRAWAL CONSTANTS     =
    =================================*/

    uint constant public MAX_OWNER_COUNT = 10;
    uint constant public MAX_WITHDRAW_PCT_DAILY = 15;
    uint constant public MAX_WITHDRAW_PCT_TX = 5;
    uint constant internal resetTimer = 1 days;

    /*=================================
    =          0xBTC INTERFACE          =
    =================================*/

    ERC20Interface constant internal _0xBTC = ERC20Interface(0x9eD7EA9aaE40ca11033266FB06713191656A9893);

    /*=================================
    =          0xBTCNN INTERFACE          =
    =================================*/

    address internal _0xBTCNNAddress;
    _0xbtcnnInterface public _0xBTCNN;

    /*=================================
    =             VARIABLES           =
    =================================*/

    mapping (uint => Transaction) public transactions;
    mapping (uint => mapping (address => bool)) public confirmations;
    mapping (address => bool) public isOwner;
    mapping (address => bool) public isWhitelisted;
    mapping (address => uint) public dailyTokensPerContract;
    address internal divCardAddress;
    address[] public owners;
    address[] public whiteListedContracts;
    uint public required;
    uint public transactionCount;
    uint internal dailyResetTime;
    uint internal dailyTknLimit;
    uint internal tknsDispensedToday;
    bool internal reEntered = false;

    /*=================================
    =         CUSTOM CONSTRUCTS       =
    =================================*/

    struct Transaction {
        address destination;
        uint value;
        bytes data;
        bool executed;
    }

    struct TKN {
        address sender;
        uint value;
    }

    /*=================================
    =            MODIFIERS            =
    =================================*/

    modifier onlyWallet() {
        if (msg.sender != address(this))
            revert();
        _;
    }

    modifier contractIsNotWhiteListed(address contractAddress) {
        if (isWhitelisted[contractAddress])
            revert();
        _;
    }

    modifier contractIsWhiteListed(address contractAddress) {
        if (!isWhitelisted[contractAddress])
            revert();
        _;
    }

    modifier isAnOwner() {
        address caller = msg.sender;
        if (!isOwner[caller])
            revert();
        _;
    }

    modifier ownerDoesNotExist(address owner) {
        if (isOwner[owner])
            revert();
        _;
    }

    modifier ownerExists(address owner) {
        if (!isOwner[owner])
            revert();
        _;
    }

    modifier transactionExists(uint transactionId) {
        if (transactions[transactionId].destination == 0)
            revert();
        _;
    }

    modifier confirmed(uint transactionId, address owner) {
        if (!confirmations[transactionId][owner])
            revert();
        _;
    }

    modifier notConfirmed(uint transactionId, address owner) {
        if (confirmations[transactionId][owner])
            revert();
        _;
    }

    modifier notExecuted(uint transactionId) {
        if (transactions[transactionId].executed)
            revert();
        _;
    }

    modifier notNull(address _address) {
        if (_address == 0)
            revert();
        _;
    }

    modifier validRequirement(uint ownerCount, uint _required) {
        if (   ownerCount > MAX_OWNER_COUNT
            || _required > ownerCount
            || _required == 0
            || ownerCount == 0)
            revert();
        _;
    }

    /*=================================
    =          LIST OF OWNERS         =
    =================================*/

    /*
        This list is for reference/identification purposes only, and comprises the eight core 0xbtc developers.
        For game contracts to be listed, they must be approved by a majority (i.e. currently five) of the owners.
        Contracts can be delisted in an emergency by a single owner.

    */


    /*=================================
    =         PUBLIC FUNCTIONS        =
    =================================*/

    /// @dev Contract constructor sets initial owners and required number of confirmations.
    /// @param _owners List of initial owners.
    /// @param _required Number of required confirmations.
    constructor (address[] _owners, uint _required)
        public
        validRequirement(_owners.length, _required)
    {
        for (uint i=0; i<_owners.length; i++) {
            if (isOwner[_owners[i]] || _owners[i] == 0)
                revert();
            isOwner[_owners[i]] = true;
        }
        owners = _owners;
        required = _required;

        dailyResetTime = now - (1 days);
    }

    /** Testing only.
    function exitAll()
        public
    {
        uint tokenBalance = _0xBTCNN.balanceOf(address(this));
        _0xBTCNN.sell(tokenBalance - 1e18);
        _0xBTCNN.sell(1e18);
        _0xBTCNN.withdraw(address(0x0));
    }
    **/

    function add0xbtcnnAddresses(address _0xbtc, address _divcards)
        public
        isAnOwner
    {
        _0xBTCNNAddress   = _0xbtc;
        divCardAddress = _divcards;
        _0xBTCNN = _0xbtcnnInterface(_0xBTCNNAddress);
    }

    /// @dev Fallback function accept eth.
    function()
        payable
        public
    {

    }

    uint NonICOBuyins;

    function deposit(uint value)
        public
    {
        _0xBTCNN.transferFrom(msg.sender,address(this),value);
        NonICOBuyins = NonICOBuyins.add(value);
    }

    /// @dev Function to buy tokens with contract _0xbtc balance.
    function buyTokens()
        public
        isAnOwner
    {
        uint savings = _0xBTCNN.balanceOf(address(this));
        if (savings > 0.01 ether) { //ether used as 18 decimals factor
            _0xBTC.approve(_0xBTCNN,savings);
            _0xBTCNN.buyAndSetDivPercentage(savings,address(0x0), 30, "");
            emit BankrollInvest(savings);
        }
        else {
            emit _0xBTCLogged(savings, msg.sender);
        }
    }

		function tokenFallback(address /*_from*/, uint /*_amountOfTokens*/, bytes /*_data*/) public returns (bool) {
			// Nothing, for now. Just receives tokens.
		}

    /// @dev Calculates if an amount of tokens exceeds the aggregate daily limit of 15% of contract
    ///        balance or 5% of the contract balance on its own.
    function permissibleTokenWithdrawal(uint _toWithdraw)
        public
        returns(bool)
    {
        uint currentTime     = now;
        uint tokenBalance    = _0xBTCNN.balanceOf(address(this));
        uint maxPerTx        = (tokenBalance.mul(MAX_WITHDRAW_PCT_TX)).div(100);

        require (_toWithdraw <= maxPerTx);

        if (currentTime - dailyResetTime >= resetTimer)
            {
                dailyResetTime     = currentTime;
                dailyTknLimit      = (tokenBalance.mul(MAX_WITHDRAW_PCT_DAILY)).div(100);
                tknsDispensedToday = _toWithdraw;
                return true;
            }
        else
            {
                if (tknsDispensedToday.add(_toWithdraw) <= dailyTknLimit)
                    {
                        tknsDispensedToday += _toWithdraw;
                        return true;
                    }
                else { return false; }
            }
    }

    /// @dev Allows us to set the daily Token Limit
    function setDailyTokenLimit(uint limit)
      public
      isAnOwner
    {
      dailyTknLimit = limit;
    }

    /// @dev Allows to add a new owner. Transaction has to be sent by wallet.
    /// @param owner Address of new owner.
    function addOwner(address owner)
        public
        onlyWallet
        ownerDoesNotExist(owner)
        notNull(owner)
        validRequirement(owners.length + 1, required)
    {
        isOwner[owner] = true;
        owners.push(owner);
        emit OwnerAddition(owner);
    }

    /// @dev Allows to remove an owner. Transaction has to be sent by wallet.
    /// @param owner Address of owner.
    function removeOwner(address owner)
        public
        onlyWallet
        ownerExists(owner)
        validRequirement(owners.length, required)
    {
        isOwner[owner] = false;
        for (uint i=0; i<owners.length - 1; i++)
            if (owners[i] == owner) {
                owners[i] = owners[owners.length - 1];
                break;
            }
        owners.length -= 1;
        if (required > owners.length)
            changeRequirement(owners.length);
        emit OwnerRemoval(owner);
    }

    /// @dev Allows to replace an owner with a new owner. Transaction has to be sent by wallet.
    /// @param owner Address of owner to be replaced.
    /// @param owner Address of new owner.
    function replaceOwner(address owner, address newOwner)
        public
        onlyWallet
        ownerExists(owner)
        ownerDoesNotExist(newOwner)
    {
        for (uint i=0; i<owners.length; i++)
            if (owners[i] == owner) {
                owners[i] = newOwner;
                break;
            }
        isOwner[owner] = false;
        isOwner[newOwner] = true;
        emit OwnerRemoval(owner);
        emit OwnerAddition(newOwner);
    }

    /// @dev Allows to change the number of required confirmations. Transaction has to be sent by wallet.
    /// @param _required Number of required confirmations.
    function changeRequirement(uint _required)
        public
        onlyWallet
        validRequirement(owners.length, _required)
    {
        required = _required;
        emit RequirementChange(_required);
    }

    /// @dev Allows an owner to submit and confirm a transaction.
    /// @param destination Transaction target address.
    /// @param value Transaction ether value.
    /// @param data Transaction data payload.
    /// @return Returns transaction ID.
    function submitTransaction(address destination, uint value, bytes data)
        public
        returns (uint transactionId)
    {
        transactionId = addTransaction(destination, value, data);
        confirmTransaction(transactionId);
    }

    /// @dev Allows an owner to confirm a transaction.
    /// @param transactionId Transaction ID.
    function confirmTransaction(uint transactionId)
        public
        ownerExists(msg.sender)
        transactionExists(transactionId)
        notConfirmed(transactionId, msg.sender)
    {
        confirmations[transactionId][msg.sender] = true;
        emit Confirmation(msg.sender, transactionId);
        executeTransaction(transactionId);
    }

    /// @dev Allows an owner to revoke a confirmation for a transaction.
    /// @param transactionId Transaction ID.
    function revokeConfirmation(uint transactionId)
        public
        ownerExists(msg.sender)
        confirmed(transactionId, msg.sender)
        notExecuted(transactionId)
    {
        confirmations[transactionId][msg.sender] = false;
        emit Revocation(msg.sender, transactionId);
    }

    /// @dev Allows anyone to execute a confirmed transaction.
    /// @param transactionId Transaction ID.
    function executeTransaction(uint transactionId)
        public
        notExecuted(transactionId)
    {
        if (isConfirmed(transactionId)) {
            Transaction storage txToExecute = transactions[transactionId];
            txToExecute.executed = true;
            if (txToExecute.destination.call.value(txToExecute.value)(txToExecute.data))
                emit Execution(transactionId);
            else {
                emit ExecutionFailure(transactionId);
                txToExecute.executed = false;
            }
        }
    }

    /// @dev Returns the confirmation status of a transaction.
    /// @param transactionId Transaction ID.
    /// @return Confirmation status.
    function isConfirmed(uint transactionId)
        public
        constant
        returns (bool)
    {
        uint count = 0;
        for (uint i=0; i<owners.length; i++) {
            if (confirmations[transactionId][owners[i]])
                count += 1;
            if (count == required)
                return true;
        }
    }

    /*=================================
    =        OPERATOR FUNCTIONS       =
    =================================*/

    /// @dev Adds a new transaction to the transaction mapping, if transaction does not exist yet.
    /// @param destination Transaction target address.
    /// @param value Transaction ether value.
    /// @param data Transaction data payload.
    /// @return Returns transaction ID.
    function addTransaction(address destination, uint value, bytes data)
        internal
        notNull(destination)
        returns (uint transactionId)
    {
        transactionId = transactionCount;
        transactions[transactionId] = Transaction({
            destination: destination,
            value: value,
            data: data,
            executed: false
        });
        transactionCount += 1;
        emit Submission(transactionId);
    }

    /*
     * Web3 call functions
     */
    /// @dev Returns number of confirmations of a transaction.
    /// @param transactionId Transaction ID.
    /// @return Number of confirmations.
    function getConfirmationCount(uint transactionId)
        public
        constant
        returns (uint count)
    {
        for (uint i=0; i<owners.length; i++)
            if (confirmations[transactionId][owners[i]])
                count += 1;
    }

    /// @dev Returns total number of transactions after filers are applied.
    /// @param pending Include pending transactions.
    /// @param executed Include executed transactions.
    /// @return Total number of transactions after filters are applied.
    function getTransactionCount(bool pending, bool executed)
        public
        constant
        returns (uint count)
    {
        for (uint i=0; i<transactionCount; i++)
            if (   pending && !transactions[i].executed
                || executed && transactions[i].executed)
                count += 1;
    }

    /// @dev Returns list of owners.
    /// @return List of owner addresses.
    function getOwners()
        public
        constant
        returns (address[])
    {
        return owners;
    }

    /// @dev Returns array with owner addresses, which confirmed transaction.
    /// @param transactionId Transaction ID.
    /// @return Returns array of owner addresses.
    function getConfirmations(uint transactionId)
        public
        constant
        returns (address[] _confirmations)
    {
        address[] memory confirmationsTemp = new address[](owners.length);
        uint count = 0;
        uint i;
        for (i=0; i<owners.length; i++)
            if (confirmations[transactionId][owners[i]]) {
                confirmationsTemp[count] = owners[i];
                count += 1;
            }
        _confirmations = new address[](count);
        for (i=0; i<count; i++)
            _confirmations[i] = confirmationsTemp[i];
    }

    /// @dev Returns list of transaction IDs in defined range.
    /// @param from Index start position of transaction array.
    /// @param to Index end position of transaction array.
    /// @param pending Include pending transactions.
    /// @param executed Include executed transactions.
    /// @return Returns array of transaction IDs.
    function getTransactionIds(uint from, uint to, bool pending, bool executed)
        public
        constant
        returns (uint[] _transactionIds)
    {
        uint[] memory transactionIdsTemp = new uint[](transactionCount);
        uint count = 0;
        uint i;
        for (i=0; i<transactionCount; i++)
            if (   pending && !transactions[i].executed
                || executed && transactions[i].executed)
            {
                transactionIdsTemp[count] = i;
                count += 1;
            }
        _transactionIds = new uint[](to - from);
        for (i=from; i<to; i++)
            _transactionIds[i - from] = transactionIdsTemp[i];
    }

    // Additions for Bankroll
    function whiteListContract(address contractAddress)
        public
        isAnOwner
        contractIsNotWhiteListed(contractAddress)
        notNull(contractAddress)
    {
        isWhitelisted[contractAddress] = true;
        whiteListedContracts.push(contractAddress);
        // We set the daily tokens for a particular contract in a separate call.
        dailyTokensPerContract[contractAddress] = 0;
        emit WhiteListAddition(contractAddress);
    }

    // Remove a whitelisted contract. This is an exception to the norm in that
    // it can be invoked directly by any owner, in the event that a game is found
    // to be bugged or otherwise faulty, so it can be shut down as an emergency measure.
    // Iterates through the whitelisted contracts to find contractAddress,
    //  then swaps it with the last address in the list - then decrements length
    function deWhiteListContract(address contractAddress)
        public
        isAnOwner
        contractIsWhiteListed(contractAddress)
    {
        isWhitelisted[contractAddress] = false;
        for (uint i=0; i < whiteListedContracts.length - 1; i++)
            if (whiteListedContracts[i] == contractAddress) {
                whiteListedContracts[i] = owners[whiteListedContracts.length - 1];
                break;
            }

        whiteListedContracts.length -= 1;

        emit WhiteListRemoval(contractAddress);
    }

     function contractTokenWithdraw(uint amount, address target) public
        contractIsWhiteListed(msg.sender)
    {
        require(isWhitelisted[msg.sender]);
        require(_0xBTCNN.transfer(target, amount));
    }

    // Alters the amount of tokens allocated to a game contract on a daily basis.
    function alterTokenGrant(address _contract, uint _newAmount)
        public
        isAnOwner
        contractIsWhiteListed(_contract)
    {
        dailyTokensPerContract[_contract] = _newAmount;
    }

    function queryTokenGrant(address _contract)
        public
        view
        returns (uint)
    {
        return dailyTokensPerContract[_contract];
    }

    // Function to be run by an owner (ideally on a cron job) which performs daily
    // token collection and dispersal for all whitelisted contracts.
    function dailyAccounting()
        public
        isAnOwner
    {
        for (uint i=0; i < whiteListedContracts.length; i++)
            {
                address _contract = whiteListedContracts[i];
                if ( dailyTokensPerContract[_contract] > 0 )
                    {
                        allocateTokens(_contract);
                        emit DailyTokenAdmin(_contract);
                    }
            }
    }

    // In the event that we want to manually take tokens back from a whitelisted contract,
    // we can do so.
    function retrieveTokens(address _contract, uint _amount)
        public
        isAnOwner
        contractIsWhiteListed(_contract)
    {
        require(_0xBTCNN.transferFrom(_contract, address(this), _amount));
    }

    // Dispenses daily amount of 0xBTCNN to whitelisted contract, or retrieves the excess.
    // Block withdraws greater than MAX_WITHDRAW_PCT_TX of 0xbtc token balance.
    // (May require occasional adjusting of the daily token allocation for contracts.)
    function allocateTokens(address _contract)
        public
        isAnOwner
        contractIsWhiteListed(_contract)
    {
        uint dailyAmount = dailyTokensPerContract[_contract];
        uint btcnnPresent  = _0xBTCNN.balanceOf(_contract);

        // Make sure that tokens aren&#39;t sent to a contract which is in the black.
        if (btcnnPresent <= dailyAmount)
        {
            // We need to send tokens over, make sure it&#39;s a permitted amount, and then send.
            uint toDispense  = dailyAmount.sub(btcnnPresent);

            // Make sure amount is <= tokenbalance*MAX_WITHDRAW_PCT_TX
            require(permissibleTokenWithdrawal(toDispense));

            require(_0xBTCNN.transfer(_contract, toDispense));
            emit DailyTokensSent(_contract, toDispense);
        } else
        {
            // The contract in question has made a profit: retrieve the excess tokens.
            uint toRetrieve = btcnnPresent.sub(dailyAmount);
            require(_0xBTCNN.transferFrom(_contract, address(this), toRetrieve));
            emit DailyTokensReceived(_contract, toRetrieve);

        }
        emit DailyTokenAdmin(_contract);
    }

    // Dev withdrawal of tokens - splits equally among all owners of contract
    function devTokenWithdraw(uint amount) public
        onlyWallet
    {
        require(permissibleTokenWithdrawal(amount));

        uint amountPerPerson = SafeMath.div(amount, owners.length);

        for (uint i=0; i<owners.length; i++) {
            _0xBTCNN.transfer(owners[i], amountPerPerson);
        }

        emit DevWithdraw(amount, amountPerPerson);
    }

    // Change the dividend card address. Can&#39;t see why this would ever need
    // to be invoked, but better safe than sorry.
    function changeDivCardAddress(address _newDivCardAddress)
        public
        isAnOwner
    {
        divCardAddress = _newDivCardAddress;
    }

    // Receive 0xbtc (from 0xbtc itself or any other source) and purchase tokens at the 30% dividend rate.
    // If the amount is less than 0.01 Ether, the Ether is stored by the contract until the balance
    // exceeds that limit and then purchases all it can.
    function receiveDividends(uint amount) public {

        _0xBTC.transferFrom(msg.sender,address(this),amount);

        if (!reEntered) {
            uint ActualBalance = (_0xBTC.balanceOf(address(this)).sub(NonICOBuyins));
            if (ActualBalance > 0.01 ether) {
              reEntered = true;
              _0xBTC.approve(_0xBTCNN,ActualBalance);
              _0xBTCNN.buyAndSetDivPercentage(ActualBalance,address(0x0), 30, "");
              emit BankrollInvest(ActualBalance);
              reEntered = false;
            }
        }
    }

    // Use all available balance to buy in
    function buyInWithAllBalance() public isAnOwner {
      if (!reEntered) {
        uint balance = _0xBTC.balanceOf(address(this));
        require (balance > 0.01 ether);
        _0xBTC.approve(_0xBTCNN,balance);
        _0xBTCNN.buyAndSetDivPercentage(balance,address(0x0), 30, "");
      }
    }

    /*=================================
    =            UTILITIES            =
    =================================*/

    // Convert an hexadecimal character to their value
    function fromHexChar(uint c) public pure returns (uint) {
        if (byte(c) >= byte(&#39;0&#39;) && byte(c) <= byte(&#39;9&#39;)) {
            return c - uint(byte(&#39;0&#39;));
        }
        if (byte(c) >= byte(&#39;a&#39;) && byte(c) <= byte(&#39;f&#39;)) {
            return 10 + c - uint(byte(&#39;a&#39;));
        }
        if (byte(c) >= byte(&#39;A&#39;) && byte(c) <= byte(&#39;F&#39;)) {
            return 10 + c - uint(byte(&#39;A&#39;));
        }
    }

    // Convert an hexadecimal string to raw bytes
    function fromHex(string s) public pure returns (bytes) {
        bytes memory ss = bytes(s);
        require(ss.length%2 == 0); // length must be even
        bytes memory r = new bytes(ss.length/2);
        for (uint i=0; i<ss.length/2; ++i) {
            r[i] = byte(fromHexChar(uint(ss[2*i])) * 16 +
                    fromHexChar(uint(ss[2*i+1])));
        }
        return r;
    }
}

/**
 * @title SafeMath
 * @dev Math operations with safety checks that throw on error
 */
library SafeMath {

    /**
    * @dev Multiplies two numbers, throws on overflow.
    */
    function mul(uint a, uint b) internal pure returns (uint) {
        if (a == 0) {
            return 0;
        }
        uint c = a * b;
        assert(c / a == b);
        return c;
    }

    /**
    * @dev Integer division of two numbers, truncating the quotient.
    */
    function div(uint a, uint b) internal pure returns (uint) {
        // assert(b > 0); // Solidity automatically throws when dividing by 0
        uint c = a / b;
        // assert(a == b * c + a % b); // There is no case in which this doesn&#39;t hold
        return c;
    }

    /**
    * @dev Subtracts two numbers, throws on overflow (i.e. if subtrahend is greater than minuend).
    */
    function sub(uint a, uint b) internal pure returns (uint) {
        assert(b <= a);
        return a - b;
    }

    /**
    * @dev Adds two numbers, throws on overflow.
    */
    function add(uint a, uint b) internal pure returns (uint) {
        uint c = a + b;
        assert(c >= a);
        return c;
    }
}