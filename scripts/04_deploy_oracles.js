require('dotenv').config();

async function main() {
    // Deploy NAV Calculator
    const NAVCalculator = await ethers.getContractFactory("NAVCalculator");
    const navCalculator = await NAVCalculator.deploy(/* args */);
    await navCalculator.deployed();
    console.log("NAVCalculator deployed to:", navCalculator.address);
}

module.exports = main; 