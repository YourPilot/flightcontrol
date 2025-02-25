require('dotenv').config();

async function verifyContract(address, constructorArguments) {
    console.log('Verifying contract at', address);
    try {
        await hre.run("verify:verify", {
            address: address,
            constructorArguments: constructorArguments,
        });
        console.log('Contract verified!');
    } catch (error) {
        console.log('Verification failed:', error);
    }
}

async function main() {
    // Verify HedgeBaal
    await verifyContract(process.env.HEDGE_BAAL_ADDRESS, [/* args */]);
    
    // Verify HedgeSummoner
    await verifyContract(process.env.HEDGE_SUMMONER_ADDRESS, [process.env.BAAL_SUMMONER_ADDRESS]);
    
    // Verify HedgeYeeter
    await verifyContract(process.env.HEDGE_YEETER_ADDRESS, [process.env.HEDGE_BAAL_ADDRESS]);
    
    // Verify HedgeStaking
    await verifyContract(process.env.HEDGE_STAKING_ADDRESS, [process.env.HEDGE_BAAL_ADDRESS]);
    
    // Verify Strategies
    await verifyContract(process.env.LP_STRATEGY_ADDRESS, [/* args */]);
    await verifyContract(process.env.SHORT_STRATEGY_ADDRESS, [/* args */]);
    await verifyContract(process.env.REBALANCE_STRATEGY_ADDRESS, [/* args */]);
    
    // Verify Oracle
    await verifyContract(process.env.NAV_CALCULATOR_ADDRESS, [/* args */]);
    
    // Verify Rewards
    await verifyContract(process.env.REWARDS_CONTROLLER_ADDRESS, [
        process.env.FLIGHT_TOKEN_ADDRESS,
        process.env.HEDGE_BAAL_ADDRESS
    ]);
}

module.exports = main; 