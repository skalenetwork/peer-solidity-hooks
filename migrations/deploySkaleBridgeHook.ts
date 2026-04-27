
import { verify } from "@skalenetwork/upgrade-tools";
import chalk from "chalk";
import {ethers} from "hardhat";

async function main() {

    if (!process.env["ORCHESTRATOR"]) {
        console.error(chalk.red(`ORCHESTRATOR environment variable is not set.`));
        process.exit(1);
    }

    if (!process.env["MESSAGE_PROXY"]) {
        console.error(chalk.red(`MESSAGE_PROXY environment variable is not set.`));
        process.exit(1);
    }

    if (!process.env["DEPOSIT_BOX"]) {
        console.error(chalk.red(`DEPOSIT_BOX environment variable is not set.`));
        process.exit(1);
    }

    if (!process.env["SKALE_CHAIN_NAME"]) {
        console.error(chalk.red(`SKALE_CHAIN_NAME environment variable is not set.`));
        process.exit(1);
    }

    const SkaleBridgeHook = await ethers.getContractFactory("SkaleBridgeHook");
    const skaleBridgeHookContract = await SkaleBridgeHook.deploy(
        process.env["ORCHESTRATOR"],
        process.env["DEPOSIT_BOX"],
        process.env["MESSAGE_PROXY"],
        process.env["SKALE_CHAIN_NAME"],
    );

    await skaleBridgeHookContract.waitForDeployment();

    console.log(chalk.green(`SkaleBridgeHook deployed to: ${await skaleBridgeHookContract.getAddress()}`));

    if (!process.env["OWNER"]) {
        console.log(chalk.gray(`OWNER environment variable is not set. Using deployer address as the owner`));
    }
    else {
        const tx = await skaleBridgeHookContract.transferOwnership(process.env["OWNER"]);
        await tx.wait();
        console.log(chalk.yellow(`Ownership transfer requested to: ${process.env["OWNER"]} - Requires confirmation by the new owner`));
    }

    const constructorArguments = ethers.AbiCoder.defaultAbiCoder().encode(
        ["address", "address", "address", "string"],
        [process.env["ORCHESTRATOR"], process.env["DEPOSIT_BOX"], process.env["MESSAGE_PROXY"], process.env["SKALE_CHAIN_NAME"]]
    );
    await verify("SkaleBridgeHook", await skaleBridgeHookContract.getAddress(), constructorArguments);

    console.log(chalk.green(`SkaleBridgeHook verified successfully`));

    console.log(chalk.green("Done!"));
}

if (require.main === module) {
    main().catch((error) => {
        console.error(error);
        process.exitCode = 1;
    });
}
