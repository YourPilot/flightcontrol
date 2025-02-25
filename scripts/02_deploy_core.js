require('dotenv').config();

async function main() {
    const hedgeBaalAddress = process.env.HEDGE_BAAL_ADDRESS;
    const baalSummonerAddress = process.env.BAAL_SUMMONER_ADDRESS;

    // Deploy HedgeSummoner
    const HedgeSummoner = await ethers.getContractFactory("HedgeSummoner");
    const hedgeSummoner = await HedgeSummoner.deploy(baalSummonerAddress);
    await hedgeSummoner.deployed();
    console.log("HedgeSummoner deployed to:", hedgeSummoner.address);

    // Deploy HedgeYeeter
    const HedgeYeeter = await ethers.getContractFactory("HedgeYeeter");
    const hedgeYeeter = await HedgeYeeter.deploy(hedgeBaalAddress);
    await hedgeYeeter.deployed();
    console.log("HedgeYeeter deployed to:", hedgeYeeter.address);

    // Deploy HedgeStaking
    const HedgeStaking = await ethers.getContractFactory("HedgeStaking");
    const hedgeStaking = await HedgeStaking.deploy(hedgeBaalAddress, lootTokenAddress);
    await hedgeStaking.deployed();
    console.log("HedgeStaking deployed to:", hedgeStaking.address);
}

module.exports = main; 