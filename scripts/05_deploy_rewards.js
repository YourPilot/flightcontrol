require('dotenv').config();

async function main() {
    const hedgeBaalAddress = process.env.HEDGE_BAAL_ADDRESS;
    const flightTokenAddress = process.env.FLIGHT_TOKEN_ADDRESS;

    // Deploy Rewards Controller
    const RewardsController = await ethers.getContractFactory("RewardsController");
    const rewardsController = await RewardsController.deploy(
        flightTokenAddress,
        hedgeBaalAddress
    );
    await rewardsController.deployed();
    console.log("RewardsController deployed to:", rewardsController.address);
}

module.exports = main; 