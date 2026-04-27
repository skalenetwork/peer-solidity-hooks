import { ethers } from "hardhat";
import type {
    MockDepositBoxERC20,
    MockERC20,
    MockMessageProxyForMainnet,
    SkaleBridgeHook,
} from "../typechain-types";

/**
 * Deploys MockDepositBoxERC20.
 */
export async function deployMockDepositBoxERC20(): Promise<MockDepositBoxERC20> {
    const [deployer] = await ethers.getSigners();
    const contract = await (await ethers.getContractFactory("MockDepositBoxERC20", deployer)).deploy();
    await contract.waitForDeployment();
    return contract;
}

/**
 * Deploys MockMessageProxyForMainnet.
 */
export async function deployMockMessageProxyForMainnet(): Promise<MockMessageProxyForMainnet> {
    const [deployer] = await ethers.getSigners();
    const contract = await (await ethers.getContractFactory("MockMessageProxyForMainnet", deployer)).deploy();
    await contract.waitForDeployment();
    return contract;
}

/**
 * Deploys MockERC20.
 *
 * @param name ERC20 token name.
 * @param symbol ERC20 token symbol.
 */
export async function deployMockERC20(name: string, symbol: string): Promise<MockERC20> {
    const [deployer] = await ethers.getSigners();
    const contract = await (await ethers.getContractFactory("MockERC20", deployer)).deploy(name, symbol);
    await contract.waitForDeployment();
    return contract as unknown as MockERC20;
}

/**
 * Deploys SkaleBridgeHook.
 *
 * @param orchestrator Address of the orchestrator contract.
 * @param depositBox Address of the DepositBoxERC20 contract.
 * @param messageProxy Address of the MessageProxyForMainnet contract.
 * @param skaleChainName SKALE chain name.
 */
export async function deploySkaleBridgeHook(
    orchestrator: string,
    depositBox: string,
    messageProxy: string,
    skaleChainName: string,
): Promise<SkaleBridgeHook> {
    const [deployer] = await ethers.getSigners();
    const contract = await (await ethers.getContractFactory("SkaleBridgeHook", deployer)).deploy(
        orchestrator,
        depositBox,
        messageProxy,
        skaleChainName,
    );
    await contract.waitForDeployment();
    return contract;
}
