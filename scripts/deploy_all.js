require('dotenv').config();
const fs = require('fs');

async function saveDeploymentState(step) {
    const state = {
        lastCompletedStep: step,
        timestamp: new Date().toISOString()
    };
    fs.writeFileSync('deployment-state.json', JSON.stringify(state, null, 2));
}

async function getLastDeploymentState() {
    try {
        const state = JSON.parse(fs.readFileSync('deployment-state.json'));
        return state.lastCompletedStep;
    } catch {
        return 0;
    }
}

async function main() {
    console.log("🚀 Starting deployment sequence...");
    
    const deploymentSteps = [
        { step: 1, name: "HedgeBaal", script: "./01_deploy_baal.js" },
        { step: 2, name: "Core Contracts", script: "./02_deploy_core.js" },
        { step: 3, name: "Strategy Contracts", script: "./03_deploy_strategies.js" },
        { step: 4, name: "Oracle Contracts", script: "./04_deploy_oracles.js" },
        { step: 5, name: "Rewards Contract", script: "./05_deploy_rewards.js" },
        { step: 6, name: "Contract Verification", script: "./06_verify_all.js" }
    ];

    const lastCompletedStep = await getLastDeploymentState();
    console.log(`📝 Resuming from step ${lastCompletedStep + 1}`);

    for (const { step, name, script } of deploymentSteps) {
        if (step <= lastCompletedStep) {
            console.log(`⏭️ Skipping step ${step}: ${name} (already completed)`);
            continue;
        }

        console.log(`\n🔄 Executing step ${step}: ${name}`);
        try {
            await require(script)();
            await saveDeploymentState(step);
            console.log(`✅ Step ${step}: ${name} completed successfully`);
        } catch (error) {
            console.error(`\n❌ Step ${step}: ${name} failed:`);
            console.error(error);
            console.error(`\n📌 Deployment halted at step ${step}. Fix the error and run again to resume from this point.`);
            process.exit(1);
        }
    }

    console.log("\n🎉 All deployments completed successfully!");
}

// Add timestamp to error logs
process.on('unhandledRejection', (error) => {
    console.error('Unhandled promise rejection:', error);
    process.exit(1);
});

main()
    .then(() => process.exit(0))
    .catch((error) => {
        console.error(`\n❌ Deployment failed with error:`, error);
        process.exit(1);
    }); 