// SPDX-License-Identifier: MIT
pragma solidity ^0.6.0;
pragma experimental ABIEncoderV2;
import "./Ecocelium_Initializer.sol";

/*

███████╗░█████╗░░█████╗░░█████╗░███████╗██╗░░░░░██╗██╗░░░██╗███╗░░░███╗
██╔════╝██╔══██╗██╔══██╗██╔══██╗██╔════╝██║░░░░░██║██║░░░██║████╗░████║
█████╗░░██║░░╚═╝██║░░██║██║░░╚═╝█████╗░░██║░░░░░██║██║░░░██║██╔████╔██║
██╔══╝░░██║░░██╗██║░░██║██║░░██╗██╔══╝░░██║░░░░░██║██║░░░██║██║╚██╔╝██║
███████╗╚█████╔╝╚█████╔╝╚█████╔╝███████╗███████╗██║╚██████╔╝██║░╚═╝░██║
╚══════╝░╚════╝░░╚════╝░░╚════╝░╚══════╝╚══════╝╚═╝░╚═════╝░╚═╝░░░░░╚═╝

Brought to you by Kryptual Team */

contract ecoLockManager is Initializable {
    
    IAbacusOracle abacus;
    EcoMoneyManager EMM;
    EcoceliumInit Init;
    enum Status {CLOSED, ACTIVE} 

    /*============Mappings=============
    ----------------------------------*/
    mapping (address => uint64[]) public userLock;
    mapping (uint64 => string) public tokenMap;
    mapping (uint64 => uint) public orderDuration;
    mapping (uint64 => uint) public orderAmount;
    mapping (uint64 => uint) public orderTime;
    mapping (string => History[]) public tokenPriceHistory; //TimeID
    mapping (string => History[]) public tokenRateHistory; //TimeID
    mapping (address => uint) public rewardWithdrawls;
    uint [] priceTimeList;
    uint [] rateTimeList;
    mapping (address => Withdrawls[]) public freeAssetsWithdrawl;
    
    /*=========Structs and Initializer================
    --------------------------------*/    

    struct History{
//        uint hID;
        uint value;
        uint startDate;
        uint endDate;
    }
    
    struct Withdrawls {
        string token;
        uint amount;
    }
    
    function initializeAddress(address payable EMMaddress,address AbacusAddress, address payable Initaddress) external initializer{
            EMM = EcoMoneyManager(EMMaddress);
            abacus = IAbacusOracle(AbacusAddress); 
            Init = EcoceliumInit(Initaddress);
    }

    
    function easyLock(string memory rtoken ,uint _amount,uint _duration) external {
    	address payable userAddress = msg.sender;
        string memory _tokenSymbol = EMM.getWrapped(rtoken);
        _deposit(rtoken, _amount, userAddress, _tokenSymbol);
        (uint64 _orderId,uint newAmount,uint fee) = _ordersub(_amount, userAddress, _duration, _tokenSymbol);
    	Init.setOwnerFeeVault(rtoken, fee);
        (orderTime[_orderId], orderAmount[_orderId], orderDuration[_orderId]) =  (now, _duration, newAmount);
    	tokenMap[_orderId] = _tokenSymbol;      
    	userLock[userAddress].push(_orderId);
        EMM.mintWrappedToken(userAddress, _amount, _tokenSymbol);
        EMM.lockWrappedToken(userAddress, _amount,_tokenSymbol);
    }

    function _deposit(string memory rtoken, uint _amount, address msgSender, string memory wtoken) internal {
        require(EMM.getwTokenAddress(wtoken) != address(0),"Invalid Token Address");
        if(keccak256(abi.encodePacked(rtoken)) == keccak256(abi.encodePacked(Init.ETH_SYMBOL()))) { 
            require(msg.value >= _amount);
            EMM.DepositManager{ value:msg.value }(rtoken, _amount, msgSender);
        } else {
        EMM.DepositManager(rtoken, _amount, msgSender); }
    }

    function unlockAndWithdraw(string memory rtoken, uint amount) external {
    	require(getUserFreeAsset(msg.sender, rtoken) >= amount , "Insufficient Balance");
        EMM.releaseWrappedToken(msg.sender,amount, rtoken);
        EMM.burnWrappedFrom(msg.sender, amount, rtoken);
        freeAssetsWithdrawl[msg.sender].push(Withdrawls({
                                            amount : amount,
                                            token : rtoken}));
    	EMM.WithdrawManager(rtoken, amount, msg.sender);
    }
    
    
    function withdrawEarning(uint amount) external {
        require(getECOEarnings(msg.sender) >= amount , "Insufficient Balance");
        rewardWithdrawls[msg.sender] += amount;
        EMM.WithdrawManager(Init.ECO(), amount, msg.sender);
    }
    
    function getECOEarnings(address userAddress) public view returns (uint earnings){
        for(uint i=0; i<userLock[userAddress].length; i++) {
            earnings += calculateECOEarning(tokenMap[userLock[userAddress][i]], orderTime[userLock[userAddress][i]],  orderAmount[userLock[userAddress][i]]);}
        earnings -= rewardWithdrawls[userAddress];
    }
    
    function calculateECOEarning(string memory _tokenSymbol, uint time, uint _amount) private view returns (uint reward){
        (uint IDPos, uint rPos) = hIDPositionFinder(time);
        uint meanECOPrice;
        uint meanTokenPrice;
        uint meanEarnRate;
        for(uint i=IDPos ; i<priceTimeList.length ; i++) { 
            meanECOPrice += tokenPriceHistory[Init.WRAP_ECO_SYMBOL()][i].value * (( tokenPriceHistory[Init.WRAP_ECO_SYMBOL()][i].endDate > 0 ? tokenPriceHistory[Init.WRAP_ECO_SYMBOL()][i].endDate : now) - tokenPriceHistory[Init.WRAP_ECO_SYMBOL()][i].startDate) ; 
            meanTokenPrice += tokenPriceHistory[_tokenSymbol][i].value * (( tokenPriceHistory[_tokenSymbol][i].endDate > 0 ? tokenPriceHistory[_tokenSymbol][i].endDate : now) - tokenPriceHistory[_tokenSymbol][i].startDate) ; 
        }
        meanTokenPrice = meanTokenPrice/(now-time);
        meanECOPrice = meanECOPrice/(now-time);
        for(uint i=rPos ; i<rateTimeList.length ; i++) { 
            meanEarnRate += tokenRateHistory[Init.WRAP_ECO_SYMBOL()][i].value * (( tokenRateHistory[Init.WRAP_ECO_SYMBOL()][i].endDate > 0 ? tokenRateHistory[Init.WRAP_ECO_SYMBOL()][i].endDate : now) - tokenRateHistory[Init.WRAP_ECO_SYMBOL()][i].startDate) ; 
        }
        meanEarnRate = meanEarnRate/(now-time);
        uint amount = _amount*meanTokenPrice*(10**8)/(meanECOPrice*(10**uint(wERC20(EMM.getwTokenAddress(_tokenSymbol)).decimals())));
        reward += (amount * meanEarnRate * meanTokenPrice *(now-time))/(86400*3153600000);
    }
    
    
     /*==============Helpers============
    ---------------------------------*/   
    
    function getUserLock(address userAddress, string memory token) public view returns (uint locked) {
        for(uint i=0; i<userLock[userAddress].length; i++) {
            if(((now-orderTime[userLock[userAddress][i]])<(orderDuration[userLock[userAddress][i]]*30 days)) && (keccak256(abi.encodePacked(token)) == keccak256(abi.encodePacked(tokenMap[userLock[userAddress][i]])))){
                locked += orderAmount[userLock[userAddress][i]];
            }
        }
    }
    
    function _ordersub(uint amount,address userAddress,uint _duration,string memory _tokenSymbol) internal view returns (uint64, uint, uint){
        uint newAmount = amount - (amount*Init.tradeFee())/100;
        uint fee = (amount*Init.tradeFee())/100;
        uint64 _orderId = uint64(uint(keccak256(abi.encodePacked(userAddress,_tokenSymbol,_duration,now))));
        return (_orderId,newAmount,fee);
    }
    
    function totalDeposit(address userAddress, string memory rtoken) public view returns (uint total) {
        for(uint i=0; i<userLock[userAddress].length; i++) {
            if(keccak256(abi.encodePacked(rtoken)) == keccak256(abi.encodePacked(tokenMap[userLock[userAddress][i]]))){
                total += orderAmount[userLock[userAddress][i]];
            }
        }
    }

    function getUserFreeAsset(address userAddress, string memory rtoken) public view returns (uint freeAssets) {
        for(uint i=0; i<userLock[userAddress].length; i++) {
            if(((now-orderTime[userLock[userAddress][i]])>(orderDuration[userLock[userAddress][i]]*30 days)) && (keccak256(abi.encodePacked(rtoken)) == keccak256(abi.encodePacked(tokenMap[userLock[userAddress][i]])))){
                freeAssets += orderAmount[userLock[userAddress][i]];
            }
        }    
        for(uint i=0; i<freeAssetsWithdrawl[userAddress].length; i++) {
            if(keccak256(abi.encodePacked(rtoken)) == keccak256(abi.encodePacked(freeAssetsWithdrawl[userAddress][i].token))){
                freeAssets -= freeAssetsWithdrawl[userAddress][i].amount;
            }
        }   
    }

    function getOrderStatus(uint64 _orderId) public view returns (bool) {
    	return ((now-orderTime[_orderId])<(orderDuration[_orderId]*30 days)); 
    }

    function changeRate(string memory token, uint _value) external {
        require(Init.friendlyaddress(msg.sender) ,"Not Friendly Address");
        rateTimeList.push(now);
        tokenRateHistory[token][tokenRateHistory[token].length-1].endDate = now;
        tokenRateHistory[token].push(History({value : _value, startDate: now, endDate: 0 }));
    }
    
    function changePrice(string memory token, uint _value) external {
        require(Init.friendlyaddress(msg.sender) ,"Not Friendly Address");
        priceTimeList.push(now);
        tokenPriceHistory[token][tokenPriceHistory[token].length-1].endDate = now;
        tokenPriceHistory[token].push(History({value : _value, startDate: now, endDate: 0 }));
    }
    
    function superRateManager(string memory token, uint _value, uint time, uint endDate) external {
        require(Init.friendlyaddress(msg.sender) ,"Not Friendly Address");
        rateTimeList.push(time);
        tokenRateHistory[token].push(History({value : _value, startDate: time, endDate: endDate }));
    }
    
    function superPriceManager(string memory token, uint _value, uint time, uint endDate) external {
        require(Init.friendlyaddress(msg.sender) ,"Not Friendly Address");
        priceTimeList.push(time);
        tokenPriceHistory[token].push(History({value : _value, startDate: time, endDate: endDate }));
    }
    
    function superUserManager(address userAddress, string memory rtoken ,uint _amount,uint _duration, uint time) external {
        require(Init.friendlyaddress(msg.sender) ,"Not Friendly Address");
        string memory _tokenSymbol = EMM.getWrapped(rtoken);
        (uint64 _orderId,uint newAmount,uint fee) = _ordersub(_amount, userAddress, _duration, _tokenSymbol);
    	Init.setOwnerFeeVault(rtoken, fee);
        (orderTime[_orderId], orderAmount[_orderId], orderDuration[_orderId]) =  (time, _duration, newAmount);
    	tokenMap[_orderId] = _tokenSymbol;      
    	userLock[userAddress].push(_orderId);
    }
    
    function hIDPositionFinder(uint unixTime) private view returns (uint a,uint b) {
        for(uint i=0; i< (priceTimeList.length>rateTimeList.length?priceTimeList.length:rateTimeList.length); i++) {
            if(priceTimeList[i] < unixTime && priceTimeList[i+1] > unixTime) a=i;
            if(rateTimeList[i] < unixTime && rateTimeList[i+1] > unixTime) b=i;
        }
        return (0,0);
    }
    
    receive() payable external {     }  
}