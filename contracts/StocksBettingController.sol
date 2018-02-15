pragma solidity ^0.4.18;

import { StocksBetting as Betting } from "./StocksBetting.sol";
 
contract StocksBettingController {
    address owner;
    bool paused;
    Betting betting;


    struct SetupMoment {
        uint256 momentInt;
        string momentString;
    }

    mapping (address => SetupMoment) public bettingIndex;
    event BettingDeployed(address _address, address _owner, uint256 _time);

    modifier onlyOwmner {
        require(msg.sender == owner);
        _;
    }
    
    modifier isNotPaused {
        require(!paused);
        _;
    }
    
    function StocksBettingController() public payable {
        owner = msg.sender;
    }
    
    function createBetting(string momentSetup, string momentCloseValue, string momentOpen1MValue) public isNotPaused {
        betting = (new Betting).value(0.1 ether)();
        bettingIndex[betting].momentInt = now;
        bettingIndex[betting].momentString = momentSetup;

        assert(betting.setupBetting(momentSetup, momentCloseValue, momentOpen1MValue, 960, 60));
        BettingDeployed(address(betting), betting.owner(), now);
    }
    
    function setPause(bool _status) public onlyOwmner {
        paused = _status;
    }
}