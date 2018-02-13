var StocksBetting = artifacts.require("./StocksBetting.sol");

module.exports = function(deployer) {
  deployer.deploy(StocksBetting);
};
