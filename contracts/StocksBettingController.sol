pragma solidity ^0.4.18;

import { StocksBetting as Betting } from "./StocksBetting.sol";
 
contract StocksBettingController {
    address owner;
    bool paused;
    Betting betting;

    mapping (address => uint256) bettingIndex;
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
    
    function createBetting() public isNotPaused {
        betting = (new Betting).value(0.1 ether)();
        bettingIndex[betting] = now;
        // neet to setup duration
        assert(betting.setupBetting("2018-02-07", "2018-02-08 15:01:00", 960, 60));
        BettingDeployed(address(betting), betting.owner(), now);
    }
    
    function setPause(bool _status) public onlyOwmner {
        paused = _status;
    }
}