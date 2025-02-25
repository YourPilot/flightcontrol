require('dotenv').config();

async function main() {
    const hedgeBaalAddress = process.env.HEDGE_BAAL_ADDRESS;

    // Deploy LP Strategy
    const LPStrategy = await ethers.getContractFactory("LPStrategy");
    const lpStrategy = await LPStrategy.deploy(/* args */);
    await lpStrategy.deployed();
    console.log("LPStrategy deployed to:", lpStrategy.address);

    // Deploy Short Strategy
    const ShortStrategy = await ethers.getContractFactory("ShortStrategy");
    const shortStrategy = await ShortStrategy.deploy(/* args */);
    await shortStrategy.deployed();
    console.log("ShortStrategy deployed to:", shortStrategy.address);

    // Deploy Rebalance Strategy
    const RebalanceStrategy = await ethers.getContractFactory("RebalanceStrategy");
    const rebalanceStrategy = await RebalanceStrategy.deploy(/* args */);
    await rebalanceStrategy.deployed();
    console.log("RebalanceStrategy deployed to:", rebalanceStrategy.address);

    // Set strategies in HedgeBaal
    const hedgeBaal = await ethers.getContractAt("HedgeBaal", hedgeBaalAddress);
    await hedgeBaal.setLPStrategy(lpStrategy.address);
    await hedgeBaal.setShortStrategy(shortStrategy.address);
    await hedgeBaal.setRebalanceStrategy(rebalanceStrategy.address);
}

module.exports = main; 