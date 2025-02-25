function getNetworkAddresses(networkName) {
    switch(networkName) {
        case 'sepolia':
            return {
                baalSummoner: process.env.SEPOLIA_BAAL_SUMMONER_ADDRESS,
                aeroToken: process.env.SEPOLIA_AERO_TOKEN_ADDRESS,
                usdcToken: process.env.SEPOLIA_USDC_TOKEN_ADDRESS
            };
        case 'base':
            return {
                baalSummoner: process.env.BASE_BAAL_SUMMONER_ADDRESS,
                aeroToken: process.env.BASE_AERO_TOKEN_ADDRESS,
                usdcToken: process.env.BASE_USDC_TOKEN_ADDRESS
            };
        case 'base-goerli':
            return {
                baalSummoner: process.env.BASE_GOERLI_BAAL_SUMMONER_ADDRESS,
                aeroToken: process.env.BASE_GOERLI_AERO_TOKEN_ADDRESS,
                usdcToken: process.env.BASE_GOERLI_USDC_TOKEN_ADDRESS
            };
        default:
            throw new Error(`Unsupported network: ${networkName}`);
    }
}

module.exports = { getNetworkAddresses }; 