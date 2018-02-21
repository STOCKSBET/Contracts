pragma solidity ^0.4.18;

import "../installed_contracts/oraclize/contracts/usingOraclize.sol";
import "../installed_contracts/zeppelin-solidity/contracts/math/SafeMath.sol";
import "../installed_contracts/stringutils/strings.sol";

contract StocksBetting is usingOraclize {
    using strings for *;
    using SafeMath for uint256; //using safemath

    address public owner; //owner address

    bytes32 stockId; // variable to differentiate different callbacks
    bytes32 queryId; // temp variable to store oraclize IDs

    uint stocksCount = 3; // variable to check if all prices are received
    uint public queryProp = 0; // ethers to prop the oraclize queries
    
    string public constant version = "0.0.2";
    
    struct ActionStatusStruct {
        bool  isOpen; // boolean: check if betting is open
        bool  isStart; //boolean: check if betting has started
        bool  isEnd; //boolean: check if betting has ended
        bool  isVoided; //boolean: check if betting has been voided
        uint  duration; // duration of the betting
        uint durationLockBetReceiving;
        uint durationBettingResult;
        uint  momentStart; // timestamp of when the betting starts
        string momentCloseValue;
        string momentOpen1MValue;
        string momentSetup;
    }
    
    struct StocksStruct {
        int oddsAAPL; // AAPL odds value
        int oddsMSFT; // MSFT odds value
        int oddsGOOG; // GOOG odds value
        bytes32 AAPL;
        bytes32 MSFT;
        bytes32 GOOG;
    }

    struct BetInfo {
        bytes32 stock; // stock on which amount is bet on
        uint amount; // amount bet by Bettor
        bool isCancelled;
    }

    struct StockInfo {
        uint totalPool; // total stock pool
        uint priceStart; // locking price
        uint priceEnd; // ending price
        uint betsCount; // number of bets
        uint canceledBetsCount; // number of canceled bets
        bool isWinner;
    }

    struct BettorInfo {
        uint betsCount; // number of bets
        uint canceledBetsCount; // number of canceled bets
        bool isRewarded; // boolean: check for double spending
        BetInfo[] bets; // array of bets
    }

    mapping (bytes32 => bytes32) oraclizeIndex; // mapping oraclize IDs with stocks
    mapping (bytes32 => StockInfo) public stocksIndex; // mapping stocks with pool information
    //mapping (bytes32 => string) public stocksDailyURL;
    //mapping (bytes32 => string) public stocksIntraDayURL;
    mapping (address => BettorInfo) public bettorsIndex; // mapping voter address with Bettor information

    uint public totalReward; // total reward to be awarded
    uint public totalPool;

    // data access structures
    StocksStruct public stocks;
    ActionStatusStruct public actionStatus;

    // tracking events
    event newOraclizeQuery(string description);
    event newPriceTicker(uint price);
    event Deposit(address from, uint256 val);
    event Withdraw(address to, uint256 val);

    // constructor
    function StocksBetting() payable public {
        oraclize_setProof(proofType_TLSNotary | proofStorage_IPFS);
        owner = msg.sender;
        queryProp = msg.value;
        stocks.AAPL = bytes32("AAPL");
        stocks.MSFT = bytes32("MSFT");
        stocks.GOOG = bytes32("GOOG");
        oraclize_setCustomGasPrice(4000000000 wei);
    }

    // modifiers for restricting access to methods
    modifier onlyOwner {
        require(owner == msg.sender);
        _;
    }

    modifier afterBettingOpen {
        require(actionStatus.isOpen);
        _;
    }
    
    modifier beforeBetReceiving {
        require(!actionStatus.isOpen);
        _;
    }

    modifier afterBetting {
        require(actionStatus.isEnd);
        _;
    }

    modifier beforeBettingStart {
        require(!actionStatus.isStart);
        _;
    }

    //oraclize callback method
    function __callback(bytes32 myid, string result, bytes proof) {
        if (msg.sender != oraclize_cbAddress()) throw;
        stockId = oraclizeIndex[myid];
        if (stockId == bytes32("CheckService")) {
            actionStatus.isStart = true;
        } else {
            if (actionStatus.isStart) {
                stocksIndex[stockId].priceEnd = stringToUintNormalize(result);
                stocksCount = stocksCount.sub(1);
                if (stocksCount == 0) {
                    reward();
                }
            } else {
                stocksIndex[stockId].priceStart = stringToUintNormalize(result);
            }
        }
    }

    // cancel bet
    function cancelAllBet(bytes32 stock) external afterBettingOpen beforeBettingStart payable {
        uint i;
        if (bettorsIndex[msg.sender].betsCount > 0) {
            for (i = 0; i < bettorsIndex[msg.sender].betsCount; i++) {
                if (!bettorsIndex[msg.sender].bets[i].isCancelled) {
                    bettorsIndex[msg.sender].canceledBetsCount = bettorsIndex[msg.sender].canceledBetsCount.add(1);
                    bettorsIndex[msg.sender].bets[i].isCancelled = true;
                    stocksIndex[stock].totalPool = (stocksIndex[stock].totalPool).sub(bettorsIndex[msg.sender].bets[i].amount);
                    stocksIndex[stock].betsCount = stocksIndex[stock].betsCount.sub(1);
                    Withdraw(msg.sender, bettorsIndex[msg.sender].bets[i].amount);
                }
            }
        }
    }

    // place a bet
    function sendBet(bytes32 stock) external afterBettingOpen beforeBettingStart payable {
        require(msg.value >= 0.1 ether && msg.value <= 1.0 ether);
        BetInfo memory currentBet;
        currentBet.amount = msg.value;
        currentBet.stock = stock;
        bettorsIndex[msg.sender].bets.push(currentBet);
        bettorsIndex[msg.sender].betsCount = bettorsIndex[msg.sender].betsCount.add(1);
        stocksIndex[stock].totalPool = (stocksIndex[stock].totalPool).add(msg.value);
        stocksIndex[stock].betsCount = stocksIndex[stock].betsCount.add(1);
        Deposit(msg.sender, msg.value);
    }

/*
    function setupStocksURLs(string momentCloseValue, string momentOpen1MValue) internal {
        stocksDailyURL[stocks.MSFT] = getURLDaily("MSFT", momentCloseValue);
        stocksDailyURL[stocks.AAPL] = getURLDaily("AAPL", momentCloseValue);
        stocksDailyURL[stocks.GOOG] = getURLDaily("GOOG", momentCloseValue);

        stocksIntraDayURL[stocks.MSFT] = getURLIntraDay("MSFT", momentOpen1MValue);
        stocksIntraDayURL[stocks.AAPL] = getURLIntraDay("AAPL", momentOpen1MValue);
        stocksIntraDayURL[stocks.GOOG] = getURLIntraDay("GOOG", momentOpen1MValue);
    }
*/

    function getURLDaily(string code, string moment) internal returns(string) {

        string memory characterStringPart1 = "json(https://www.alphavantage.co/query?function=TIME_SERIES_DAILY_ADJUSTED&symbol=";
        string memory characterStringPart2 = "&apikey=FGWRJGD9IACD8SHZ).'Time Series (Daily)'.'";
        string memory characterStringPart3 = "'.'4. close'";

        var s = characterStringPart1.toSlice().concat(code.toSlice()).toSlice().concat(characterStringPart2.toSlice());
        return s.toSlice().concat(moment.toSlice()).toSlice().concat(characterStringPart3.toSlice());
    }

    function getURLIntraDay(string code, string moment) internal returns(string) {

        string memory characterStringPart1 = "json(https://www.alphavantage.co/query?function=TIME_SERIES_INTRADAY&interval=1min&symbol=";
        string memory characterStringPart2 = "&apikey=FGWRJGD9IACD8SHZ).'Time Series (1min)'.'";
        string memory characterStringPart3 = "'.'4. close'";

        var s = characterStringPart1.toSlice().concat(code.toSlice()).toSlice().concat(characterStringPart2.toSlice());
        return s.toSlice().concat(moment.toSlice()).toSlice().concat(characterStringPart3.toSlice());
    }

    function setupBetting(string momentSetup, string momentCloseValue, string momentOpen1MValue, uint durationLockBetReceiving, uint durationBettingResult) public onlyOwner beforeBetReceiving payable returns(bool) {
        if (oraclize_getPrice("URL") > this.balance / 10) {
            newOraclizeQuery("Oraclize query was NOT sent, please add some ETH to cover for the query fee");
            return false;
        } else {
            actionStatus.momentStart = block.timestamp;
            actionStatus.momentSetup = momentSetup;
            actionStatus.momentCloseValue = momentCloseValue;
            actionStatus.momentOpen1MValue = momentOpen1MValue;
            actionStatus.durationLockBetReceiving = durationLockBetReceiving;
            actionStatus.durationBettingResult = durationBettingResult;
            actionStatus.isOpen = true;

            newOraclizeQuery("Oraclize query was sent, standing by for the answer..");
            ///////////////////////////////////
            // Get close market price
            queryId = oraclize_query("URL", getURLDaily("MSFT", momentCloseValue));
            oraclizeIndex[queryId] = stocks.MSFT;

            queryId = oraclize_query("URL", getURLDaily("AAPL", momentCloseValue));
            oraclizeIndex[queryId] = stocks.AAPL;

            queryId = oraclize_query("URL", getURLDaily("GOOG", momentCloseValue));
            oraclizeIndex[queryId] = stocks.GOOG;

            ///////////////////////////////////
            // Check service availability and Lock Bet Receiving
            uint delay = durationLockBetReceiving * 60;
            queryId = oraclize_query(delay, "URL", getURLDaily("GOOG", momentCloseValue), 300000);
            oraclizeIndex[queryId] = bytes32("CheckService");

            ///////////////////////////////////
            // Get 1 min open market price
            delay = delay.add(durationBettingResult * 60);
            queryId = oraclize_query(delay, "URL", getURLIntraDay("MSFT", momentOpen1MValue), 300000);
            oraclizeIndex[queryId] = stocks.MSFT;

            queryId = oraclize_query(delay, "URL", getURLIntraDay("AAPL", momentOpen1MValue), 300000);
            oraclizeIndex[queryId] = stocks.AAPL;

            queryId = oraclize_query(delay, "URL", getURLIntraDay("GOOG", momentOpen1MValue), 300000);
            oraclizeIndex[queryId] = stocks.GOOG;

            actionStatus.duration = delay;
            return true;
        }
    }


    // method to calculate reward (called internally by callback)
    function reward() internal {
        /*
        calculating the difference in price with a precision of 5 digits
        not using safemath since signed integers are handled
        */
        stocks.oddsAAPL = int(stocksIndex[stocks.AAPL].priceEnd - stocksIndex[stocks.AAPL].priceStart) * 10000 / int(stocksIndex[stocks.AAPL].priceStart);
        stocks.oddsMSFT = int(stocksIndex[stocks.MSFT].priceEnd - stocksIndex[stocks.MSFT].priceStart) * 10000 / int(stocksIndex[stocks.MSFT].priceStart);
        stocks.oddsGOOG = int(stocksIndex[stocks.GOOG].priceEnd - stocksIndex[stocks.GOOG].priceStart) * 10000 / int(stocksIndex[stocks.GOOG].priceStart);

        // throws when no bets are placed. since oraclize will eat some ethers from the queryProp and queryProp will be > balance
        totalReward = this.balance.sub(queryProp); 

        // fee 5%
        uint fee = totalReward.mul(5).div(100);
        totalReward = totalReward.sub(fee);
        fee = fee.add(queryProp);
        require(this.balance > fee);
        owner.transfer(fee);

        if (stocks.oddsAAPL > stocks.oddsMSFT) {
            if (stocks.oddsAAPL > stocks.oddsGOOG) {
                stocksIndex[stocks.AAPL].isWinner = true;
                totalPool = stocksIndex[stocks.AAPL].totalPool;
            } else if (stocks.oddsGOOG > stocks.oddsAAPL) {
                stocksIndex[stocks.GOOG].isWinner = true;
                totalPool = stocksIndex[stocks.GOOG].totalPool;
            } else {
                stocksIndex[stocks.AAPL].isWinner = true;
                stocksIndex[stocks.GOOG].isWinner = true;
                totalPool = stocksIndex[stocks.AAPL].totalPool.add(stocksIndex[stocks.GOOG].totalPool);
            }
        } else if (stocks.oddsMSFT > stocks.oddsAAPL) {
            if (stocks.oddsMSFT > stocks.oddsGOOG) {
                stocksIndex[stocks.MSFT].isWinner = true;
                totalPool = stocksIndex[stocks.MSFT].totalPool;
            } else if (stocks.oddsGOOG > stocks.oddsMSFT) {
                stocksIndex[stocks.GOOG].isWinner = true;
                totalPool = stocksIndex[stocks.GOOG].totalPool;
            } else {
                stocksIndex[stocks.MSFT].isWinner = true;
                stocksIndex[stocks.GOOG].isWinner = true;
                totalPool = stocksIndex[stocks.MSFT].totalPool.add(stocksIndex[stocks.GOOG].totalPool);
            }
        } else {
            if (stocks.oddsGOOG > stocks.oddsMSFT) {
                stocksIndex[stocks.GOOG].isWinner = true;
                totalPool = stocksIndex[stocks.GOOG].totalPool;
            } else if (stocks.oddsGOOG < stocks.oddsMSFT) {
                stocksIndex[stocks.MSFT].isWinner = true;
                stocksIndex[stocks.AAPL].isWinner = true;
                totalPool = stocksIndex[stocks.MSFT].totalPool.add(stocksIndex[stocks.AAPL].totalPool);
            } else {
                stocksIndex[stocks.GOOG].isWinner = true;
                stocksIndex[stocks.MSFT].isWinner = true;
                stocksIndex[stocks.AAPL].isWinner = true;
                totalPool = stocksIndex[stocks.MSFT].totalPool.add(stocksIndex[stocks.AAPL].totalPool).add(stocksIndex[stocks.GOOG].totalPool);
            }
        }
        actionStatus.isEnd = true;
    }

    // method to calculate an invidual's reward
    function rewardCalculate(address candidate) internal afterBetting constant returns(uint winnerReward) {
        uint i;
        BettorInfo storage bettor = bettorsIndex[candidate];
        if (!actionStatus.isVoided) {
            for (i = 0; i < bettor.betsCount; i++) {
                if (!bettor.bets[i].isCancelled) {
                    if (stocksIndex[bettor.bets[i].stock].isWinner) {
                        winnerReward += (((totalReward.mul(10000)).div(totalPool)).mul(bettor.bets[i].amount)).div(10000);
                    }
                }
            }
        } else {
            for (i = 0; i < bettor.betsCount; i++) {
                if (!bettor.bets[i].isCancelled) {
                    winnerReward += bettor.bets[i].amount;
                }
            }
        }
    }

    // method to just check the reward amount
    function rewardCheck() public afterBetting constant returns (uint) {
        require(!bettorsIndex[msg.sender].isRewarded);
        return rewardCalculate(msg.sender);
    }

    // method to claim the reward amount
    function rewardClaim() afterBetting public {
        require(!bettorsIndex[msg.sender].isRewarded);
        uint transferAmount = rewardCalculate(msg.sender);
        require(this.balance > transferAmount);
        bettorsIndex[msg.sender].isRewarded = true;
        msg.sender.transfer(transferAmount);
        Withdraw(msg.sender, transferAmount);
    }

    // utility function to convert string to integer with precision consideration
    function stringToUintNormalize(string s) public constant returns (uint result) {
        uint p = 2;
        bool precision = false;
        bytes memory b = bytes(s);
        uint i;
        result = 0;
        for (i = 0; i < b.length; i++) {
            if (precision == true) {p = p - 1;}
            if (uint(b[i]) == 46) {precision = true;}
            uint c = uint(b[i]);
            if (c >= 48 && c <= 57) {result = result * 10 + (c - 48);}
            if (precision==true && p == 0) {return result;}
        }
        while (p != 0) {
            result = result * 10;
            p = p - 1;
        }
    }

    // exposing the stock pool details
    function getStockInfo(bytes32 index) public constant returns (uint, uint, uint, uint, uint) {
        return (stocksIndex[index].totalPool, stocksIndex[index].priceStart, stocksIndex[index].priceEnd, stocksIndex[index].betsCount, stocksIndex[index].canceledBetsCount);
    }

    // exposing the total reward amount
    function getTotalPool() public constant returns (uint) {
        return (stocksIndex[stocks.AAPL].totalPool.add(stocksIndex[stocks.MSFT].totalPool).add(stocksIndex[stocks.GOOG].totalPool));
    }

    function getBettorInfo() public constant returns (uint, bytes32[], uint[], bool[]) {
        BettorInfo storage bettorInfoTemp = bettorsIndex[msg.sender];

        bytes32[] memory bettorStocks = new bytes32[](bettorInfoTemp.bets.length);
        uint[] memory bettorAmounts = new uint[](bettorInfoTemp.bets.length);
        bool[] memory isCancelled = new bool[](bettorInfoTemp.bets.length);

        for (uint i = 0; i < bettorInfoTemp.bets.length; i++) {
            BetInfo storage bet = bettorInfoTemp.bets[i];
            bettorStocks[i] = bet.stock;
            bettorAmounts[i] = bet.amount;
            isCancelled[i] = bet.isCancelled;
        }

        return (bettorInfoTemp.betsCount, bettorStocks, bettorAmounts, isCancelled);
    }

    // in case of any errors in betting, enable full refund for the Bettors to claim
    function refundKill() public onlyOwner {
        require(now > actionStatus.momentStart + actionStatus.duration);
        require((actionStatus.isOpen && !actionStatus.isStart) || (actionStatus.isStart && !actionStatus.isEnd));
        actionStatus.isVoided = true;
        actionStatus.isEnd = true;
    }

    // method to claim unclaimed winnings after 30 day notice period
    function recovery() public onlyOwner {
        require(now > actionStatus.momentStart+actionStatus.duration + 30 days);
        require(actionStatus.isVoided || actionStatus.isEnd);
        selfdestruct(owner);
    }
}