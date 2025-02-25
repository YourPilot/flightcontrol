require('dotenv').config();
require("@nomiclabs/hardhat-etherscan");
const { getNetworkAddresses } = require('./utils/addresses');

async function main() {
    const networkName = hre.network.name;
    const addresses = getNetworkAddresses(networkName);
    
    console.log(`Deploying to ${networkName}...`);
    console.log('Using addresses:', addresses);

    const HedgeBaal = await ethers.getContractFactory("HedgeBaal");
    const hedgeBaal = await HedgeBaal.deploy(
        owner,
        avatar,
        target,
        addresses.baalSummoner,  // Network-specific address
        stakingContract,
        yeeter,
        addresses.aeroToken      // Network-specific address
    );
    await hedgeBaal.deployed();
    
    console.log("HedgeBaal deployed to:", hedgeBaal.address);
}

module.exports = main; 