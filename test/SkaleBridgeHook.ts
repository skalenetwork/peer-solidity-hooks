import { expect } from "chai";
import { ethers } from "hardhat";
import { loadFixture } from "@nomicfoundation/hardhat-network-helpers";
import { anyValue } from "@nomicfoundation/hardhat-chai-matchers/withArgs";
import type { HardhatEthersSigner } from "@nomicfoundation/hardhat-ethers/signers";
import {
    deployMockDepositBoxERC20,
    deployMockERC20,
    deployMockMessageProxyForMainnet,
    deploySkaleBridgeHook,
} from "./utils";
import type { MockDepositBoxERC20, MockERC20, SkaleBridgeHook } from "../typechain-types";
import type { IPostIntentHookV2 } from "../typechain-types/contracts/SkaleBridgeHook";

// ─── Constants ────────────────────────────────────────────────────────────────

const SCHAIN_NAME = "test-skale-chain";
const BRIDGE_AMOUNT = ethers.parseEther("100");

// ─── Helpers ──────────────────────────────────────────────────────────────────

function buildContext(
    token: string,
    amount: bigint,
    recipient: string,
    intentHash: string = ethers.hexlify(ethers.randomBytes(32)),
): IPostIntentHookV2.HookExecutionContextStruct {
    return {
        intentHash,
        token,
        executableAmount: amount,
        intent: {
            owner: ethers.ZeroAddress,
            to: recipient,
            escrow: ethers.ZeroAddress,
            depositId: 0n,
            amount,
            timestamp: 0n,
            paymentMethod: ethers.ZeroHash,
            fiatCurrency: ethers.ZeroHash,
            conversionRate: 0n,
            payeeId: ethers.ZeroHash,
            signalHookData: "0x",
        },
    };
}

function encodeRecipient(address: string): string {
    return ethers.AbiCoder.defaultAbiCoder().encode(["address"], [address]);
}

// ─── Fixtures ─────────────────────────────────────────────────────────────────

async function deployBaseFixture() {
    const [owner, orchestrator, user, other] = await ethers.getSigners();

    const mockProxy = await deployMockMessageProxyForMainnet();
    await mockProxy.setConnectedChain(SCHAIN_NAME, true);

    const mockDepositBox = await deployMockDepositBoxERC20();
    const mockToken = await deployMockERC20("TestToken", "TT");

    return { owner, orchestrator, user, other, mockProxy, mockDepositBox, mockToken };
}

async function deployHookFixture() {
    const base = await deployBaseFixture();
    const { orchestrator, mockDepositBox, mockProxy } = base;

    const hook = await deploySkaleBridgeHook(
        orchestrator.address,
        await mockDepositBox.getAddress(),
        await mockProxy.getAddress(),
        SCHAIN_NAME,
    );

    return { ...base, hook };
}

/**
 * Hook deployed with IMA whitelist enabled:
 * setWhitelistEnabled(true) → DEPOSIT_BOX.isWhitelisted() returns true.
 * Token mapping is set so the mock's depositERC20Direct does not revert.
 * Orchestrator is funded and has approved the hook.
 */
async function deployWhitelistEnabledFixture() {
    const base = await deployHookFixture();
    const { orchestrator, mockDepositBox, mockToken, hook } = base;

    const tokenAddr = await mockToken.getAddress();
    const hookAddr = await hook.getAddress();
    const depositBoxAddr = await mockDepositBox.getAddress();

    await mockDepositBox.setWhitelistEnabled(SCHAIN_NAME, true);
    await mockDepositBox.setTokenMapping(tokenAddr, SCHAIN_NAME, ethers.Wallet.createRandom().address);

    await mockToken.mint(orchestrator.address, BRIDGE_AMOUNT * 10n);
    await mockToken.connect(orchestrator).approve(hookAddr, BRIDGE_AMOUNT * 10n);

    return { ...base, tokenAddr, hookAddr, depositBoxAddr };
}

/**
 * Hook deployed with IMA automatic deploy enabled:
 * setWhitelistEnabled(false) → DEPOSIT_BOX.isWhitelisted() returns false, so the hook requires its local whitelist.
 * Token mapping is set so the mock's depositERC20Direct succeeds once the hook allows the token through.
 * Orchestrator is funded and has approved the hook.
 */
async function deployAutoDeployFixture() {
    const base = await deployHookFixture();
    const { orchestrator, mockDepositBox, mockToken, hook } = base;

    const tokenAddr = await mockToken.getAddress();
    const hookAddr = await hook.getAddress();
    const depositBoxAddr = await mockDepositBox.getAddress();

    await mockDepositBox.setWhitelistEnabled(SCHAIN_NAME, false);
    await mockDepositBox.setTokenMapping(tokenAddr, SCHAIN_NAME, ethers.Wallet.createRandom().address);

    await mockToken.mint(orchestrator.address, BRIDGE_AMOUNT * 10n);
    await mockToken.connect(orchestrator).approve(hookAddr, BRIDGE_AMOUNT * 10n);

    return { ...base, tokenAddr, hookAddr, depositBoxAddr };
}

// ─── Tests ────────────────────────────────────────────────────────────────────

describe("Testing SkaleBridgeHook", () => {
    // ── Constructor ───────────────────────────────────────────────────────────────

    describe("Constructor", () => {
        it("reverts with InvalidAddress when orchestrator is zero address", async () => {
            const { mockDepositBox, mockProxy } = await loadFixture(deployBaseFixture);
            const factory = await ethers.getContractFactory("SkaleBridgeHook");

            await expect(
                factory.deploy(
                    ethers.ZeroAddress,
                    await mockDepositBox.getAddress(),
                    await mockProxy.getAddress(),
                    SCHAIN_NAME,
                ),
            )
                .to.be.revertedWithCustomError(factory, "InvalidAddress")
                .withArgs(ethers.ZeroAddress);
        });

        it("reverts with InvalidAddress when messageProxy is zero address", async () => {
            const { orchestrator, mockDepositBox } = await loadFixture(deployBaseFixture);
            const factory = await ethers.getContractFactory("SkaleBridgeHook");

            await expect(
                factory.deploy(
                    orchestrator.address,
                    await mockDepositBox.getAddress(),
                    ethers.ZeroAddress,
                    SCHAIN_NAME,
                ),
            ).to.be.revertedWithCustomError(factory, "InvalidAddress").withArgs(ethers.ZeroAddress);
        });

        it("reverts with InvalidAddress when depositBox is zero address", async () => {
            const { orchestrator, mockProxy } = await loadFixture(deployBaseFixture);
            const factory = await ethers.getContractFactory("SkaleBridgeHook");

            await expect(
                factory.deploy(
                    orchestrator.address,
                    ethers.ZeroAddress,
                    await mockProxy.getAddress(),
                    SCHAIN_NAME,
                ),
            ).to.be.revertedWithCustomError(factory, "InvalidAddress").withArgs(ethers.ZeroAddress);
        });

        it("reverts with InvalidSourceChain when schain is not connected to the proxy", async () => {
            const { orchestrator, mockDepositBox, mockProxy } = await loadFixture(deployBaseFixture);
            const factory = await ethers.getContractFactory("SkaleBridgeHook");

            await expect(
                factory.deploy(
                    orchestrator.address,
                    await mockDepositBox.getAddress(),
                    await mockProxy.getAddress(),
                    "not-a-connected-chain",
                ),
            ).to.be.revertedWithCustomError(factory, "InvalidSourceChain");
        });

        it("stores ORCHESTRATOR correctly", async () => {
            const { orchestrator, hook } = await loadFixture(deployHookFixture);
            expect(await hook.ORCHESTRATOR()).to.equal(orchestrator.address);
        });

        it("stores DEPOSIT_BOX correctly", async () => {
            const { mockDepositBox, hook } = await loadFixture(deployHookFixture);
            expect(await hook.DEPOSIT_BOX()).to.equal(await mockDepositBox.getAddress());
        });

        it("stores skaleChainName correctly", async () => {
            const { hook } = await loadFixture(deployHookFixture);
            expect(await hook.skaleChainName()).to.equal(SCHAIN_NAME);
        });

        it("sets the deployer as owner", async () => {
            const { owner, hook } = await loadFixture(deployHookFixture);
            expect(await hook.owner()).to.equal(owner.address);
        });
    });

    // ── addTokenToWhitelist ───────────────────────────────────────────────────────

    describe("addTokenToWhitelist", () => {
        let hook: SkaleBridgeHook;
        let owner: HardhatEthersSigner;
        let other: HardhatEthersSigner;
        let mockToken: MockERC20;
        let tokenAddr: string;

        beforeEach(async () => {
            ({ hook, owner, other, mockToken } = await loadFixture(deployHookFixture));
            tokenAddr = await mockToken.getAddress();
        });

        it("reverts with OwnableUnauthorizedAccount when called by a non-owner", async () => {
            await expect(hook.connect(other).addTokenToWhitelist(tokenAddr))
                .to.be.revertedWithCustomError(hook, "OwnableUnauthorizedAccount")
                .withArgs(other.address);
        });

        it("reverts with InvalidAddress when token is the zero address", async () => {
            await expect(hook.connect(owner).addTokenToWhitelist(ethers.ZeroAddress))
                .to.be.revertedWithCustomError(hook, "InvalidAddress")
                .withArgs(ethers.ZeroAddress);
        });

        it("emits TokenWhitelisted when a new token is added", async () => {
            await expect(hook.connect(owner).addTokenToWhitelist(tokenAddr))
                .to.emit(hook, "TokenWhitelisted")
                .withArgs(tokenAddr);
        });

        it("does not emit TokenWhitelisted when adding a duplicate token", async () => {
            await hook.connect(owner).addTokenToWhitelist(tokenAddr);
            await expect(hook.connect(owner).addTokenToWhitelist(tokenAddr)).to.not.emit(hook, "TokenWhitelisted");
        });

        it("increments getWhitelistedTokensLength after each new addition", async () => {
            const [, , , , extraToken] = await ethers.getSigners();
            expect(await hook.getWhitelistedTokensLength()).to.equal(0n);

            await hook.connect(owner).addTokenToWhitelist(tokenAddr);
            expect(await hook.getWhitelistedTokensLength()).to.equal(1n);

            await hook.connect(owner).addTokenToWhitelist(extraToken.address);
            expect(await hook.getWhitelistedTokensLength()).to.equal(2n);
        });

        it("does not increment length when adding a duplicate token", async () => {
            await hook.connect(owner).addTokenToWhitelist(tokenAddr);
            await hook.connect(owner).addTokenToWhitelist(tokenAddr);
            expect(await hook.getWhitelistedTokensLength()).to.equal(1n);
        });
    });

    // ── removeTokenFromWhitelist ──────────────────────────────────────────────────

    describe("removeTokenFromWhitelist", () => {
        let hook: SkaleBridgeHook;
        let owner: HardhatEthersSigner;
        let other: HardhatEthersSigner;
        let mockToken: MockERC20;
        let tokenAddr: string;

        beforeEach(async () => {
            ({ hook, owner, other, mockToken } = await loadFixture(deployHookFixture));
            tokenAddr = await mockToken.getAddress();
            await hook.connect(owner).addTokenToWhitelist(tokenAddr);
        });

        it("reverts with OwnableUnauthorizedAccount when called by a non-owner", async () => {
            await expect(hook.connect(other).removeTokenFromWhitelist(tokenAddr))
                .to.be.revertedWithCustomError(hook, "OwnableUnauthorizedAccount")
                .withArgs(other.address);
        });

        it("reverts with InvalidAddress when token is the zero address", async () => {
            await expect(hook.connect(owner).removeTokenFromWhitelist(ethers.ZeroAddress))
                .to.be.revertedWithCustomError(hook, "InvalidAddress")
                .withArgs(ethers.ZeroAddress);
        });

        it("emits TokenRemovedFromWhitelist when a whitelisted token is removed", async () => {
            await expect(hook.connect(owner).removeTokenFromWhitelist(tokenAddr))
                .to.emit(hook, "TokenRemovedFromWhitelist")
                .withArgs(tokenAddr);
        });

        it("does not emit TokenRemovedFromWhitelist when removing a token not in the whitelist", async () => {
            const [, , , , nonWhitelisted] = await ethers.getSigners();
            await expect(
                hook.connect(owner).removeTokenFromWhitelist(nonWhitelisted.address),
            ).to.not.emit(hook, "TokenRemovedFromWhitelist");
        });

        it("decrements getWhitelistedTokensLength after removal", async () => {
            expect(await hook.getWhitelistedTokensLength()).to.equal(1n);
            await hook.connect(owner).removeTokenFromWhitelist(tokenAddr);
            expect(await hook.getWhitelistedTokensLength()).to.equal(0n);
        });

        it("does not decrement length when removing a token not in the whitelist", async () => {
            const [, , , , nonWhitelisted] = await ethers.getSigners();
            await hook.connect(owner).removeTokenFromWhitelist(nonWhitelisted.address);
            expect(await hook.getWhitelistedTokensLength()).to.equal(1n);
        });
    });

    // ── getWhitelistedTokensLength / getWhitelistedTokenAt ────────────────────────

    describe("getWhitelistedTokensLength and getWhitelistedTokenAt", () => {
        let hook: SkaleBridgeHook;
        let owner: HardhatEthersSigner;
        let mockToken: MockERC20;
        let tokenAddr: string;

        beforeEach(async () => {
            ({ hook, owner, mockToken } = await loadFixture(deployHookFixture));
            tokenAddr = await mockToken.getAddress();
        });

        it("returns 0 when no tokens are whitelisted", async () => {
            expect(await hook.getWhitelistedTokensLength()).to.equal(0n);
        });

        it("returns correct length after additions and removals", async () => {
            const [, , , , a, b] = await ethers.getSigners();
            await hook.connect(owner).addTokenToWhitelist(tokenAddr);
            await hook.connect(owner).addTokenToWhitelist(a.address);
            await hook.connect(owner).addTokenToWhitelist(b.address);
            expect(await hook.getWhitelistedTokensLength()).to.equal(3n);

            await hook.connect(owner).removeTokenFromWhitelist(a.address);
            expect(await hook.getWhitelistedTokensLength()).to.equal(2n);
        });

        it("returns the correct token address at a given index", async () => {
            await hook.connect(owner).addTokenToWhitelist(tokenAddr);
            expect(await hook.getWhitelistedTokenAt(0n)).to.equal(tokenAddr);
        });

        it("reverts when accessing an out-of-bounds index", async () => {
            await expect(hook.getWhitelistedTokenAt(0n)).to.be.reverted;
        });
    });

    // ── execute – access control ──────────────────────────────────────────────────

    describe("execute – access control", () => {
        let hook: SkaleBridgeHook;
        let owner: HardhatEthersSigner;
        let user: HardhatEthersSigner;
        let mockToken: MockERC20;

        beforeEach(async () => {
            ({ hook, owner, user, mockToken } = await loadFixture(deployHookFixture));
        });

        it("reverts with OnlyOrchestrator when called by a random account", async () => {
            const ctx = buildContext(await mockToken.getAddress(), BRIDGE_AMOUNT, user.address);
            await expect(hook.connect(user).execute(ctx, "0x")).to.be.revertedWithCustomError(
                hook,
                "OnlyOrchestrator",
            );
        });

        it("reverts with OnlyOrchestrator when called by the owner", async () => {
            const ctx = buildContext(await mockToken.getAddress(), BRIDGE_AMOUNT, user.address);
            await expect(hook.connect(owner).execute(ctx, "0x")).to.be.revertedWithCustomError(
                hook,
                "OnlyOrchestrator",
            );
        });
    });

    // ── execute – recipient resolution ────────────────────────────────────────────

    describe("execute – recipient resolution", () => {
        let hook: SkaleBridgeHook;
        let orchestrator: HardhatEthersSigner;
        let user: HardhatEthersSigner;
        let other: HardhatEthersSigner;
        let tokenAddr: string;

        beforeEach(async () => {
            ({ hook, orchestrator, user, other, tokenAddr } = await loadFixture(deployWhitelistEnabledFixture));
        });

        it("uses intent.to as recipient when fulfillHookData is empty", async () => {
            const ctx = buildContext(tokenAddr, BRIDGE_AMOUNT, user.address);

            await expect(hook.connect(orchestrator).execute(ctx, "0x"))
                .to.emit(hook, "BridgeInitiated")
                .withArgs(ctx.intentHash, user.address, tokenAddr, anyValue, anyValue);
        });

        it("uses intent.to as recipient when fulfillHookData is shorter than 32 bytes", async () => {
            const ctx = buildContext(tokenAddr, BRIDGE_AMOUNT, user.address);
            const shortData = ethers.hexlify(ethers.randomBytes(20));

            await expect(hook.connect(orchestrator).execute(ctx, shortData))
                .to.emit(hook, "BridgeInitiated")
                .withArgs(ctx.intentHash, user.address, tokenAddr, anyValue, anyValue);
        });

        it("overrides recipient when fulfillHookData encodes a non-zero address", async () => {
            const ctx = buildContext(tokenAddr, BRIDGE_AMOUNT, user.address);

            await expect(hook.connect(orchestrator).execute(ctx, encodeRecipient(other.address)))
                .to.emit(hook, "BridgeInitiated")
                .withArgs(ctx.intentHash, other.address, tokenAddr, anyValue, anyValue);
        });

        it("keeps intent.to when fulfillHookData encodes the zero address", async () => {
            const ctx = buildContext(tokenAddr, BRIDGE_AMOUNT, user.address);

            await expect(hook.connect(orchestrator).execute(ctx, encodeRecipient(ethers.ZeroAddress)))
                .to.emit(hook, "BridgeInitiated")
                .withArgs(ctx.intentHash, user.address, tokenAddr, anyValue, anyValue);
        });
    });

    // ── execute – token gating (IMA auto-deploy mode) ────────────────────────────

    describe("execute – token gating (DEPOSIT_BOX.isWhitelisted = false, IMA auto-deploy)", () => {
        let hook: SkaleBridgeHook;
        let owner: HardhatEthersSigner;
        let orchestrator: HardhatEthersSigner;
        let user: HardhatEthersSigner;
        let tokenAddr: string;

        beforeEach(async () => {
            ({ hook, owner, orchestrator, user, tokenAddr } = await loadFixture(deployAutoDeployFixture));
        });

        it("reverts with TokenNotAllowedForSchain when token is not in hook whitelist", async () => {
            const ctx = buildContext(tokenAddr, BRIDGE_AMOUNT, user.address);

            await expect(hook.connect(orchestrator).execute(ctx, "0x"))
                .to.be.revertedWithCustomError(hook, "TokenNotAllowedForSchain")
                .withArgs(SCHAIN_NAME, tokenAddr);
        });

        it("succeeds when token is added to the hook's internal whitelist", async () => {
            await hook.connect(owner).addTokenToWhitelist(tokenAddr);
            const ctx = buildContext(tokenAddr, BRIDGE_AMOUNT, user.address);

            await expect(hook.connect(orchestrator).execute(ctx, "0x")).to.emit(hook, "BridgeInitiated");
        });
    });

    // ── execute – token gating (IMA whitelist enabled) ────────────────────────────

    describe("execute – token gating (DEPOSIT_BOX.isWhitelisted = true, IMA whitelist enabled)", () => {
        let hook: SkaleBridgeHook;
        let orchestrator: HardhatEthersSigner;
        let user: HardhatEthersSigner;
        let tokenAddr: string;

        beforeEach(async () => {
            ({ hook, orchestrator, user, tokenAddr } = await loadFixture(deployWhitelistEnabledFixture));
        });

        it("allows a mapped token without being added to the hook whitelist", async () => {
            const ctx = buildContext(tokenAddr, BRIDGE_AMOUNT, user.address);
            await expect(hook.connect(orchestrator).execute(ctx, "0x")).to.emit(hook, "BridgeInitiated");
        });

        it("still succeeds when token is also in the hook whitelist", async () => {
            const { owner } = await loadFixture(deployWhitelistEnabledFixture);
            await hook.connect(owner).addTokenToWhitelist(tokenAddr);
            const ctx = buildContext(tokenAddr, BRIDGE_AMOUNT, user.address);
            await expect(hook.connect(orchestrator).execute(ctx, "0x")).to.emit(hook, "BridgeInitiated");
        });
    });

    // ── execute – BridgeInitiated event ──────────────────────────────────────────

    describe("execute – BridgeInitiated event", () => {
        let hook: SkaleBridgeHook;
        let orchestrator: HardhatEthersSigner;
        let user: HardhatEthersSigner;
        let other: HardhatEthersSigner;
        let tokenAddr: string;

        beforeEach(async () => {
            ({ hook, orchestrator, user, other, tokenAddr } = await loadFixture(deployWhitelistEnabledFixture));
        });

        it("emits BridgeInitiated with the correct intentHash, recipient, token, amount and timestamp", async () => {
            const intentHash = ethers.hexlify(ethers.randomBytes(32));
            const ctx = buildContext(tokenAddr, BRIDGE_AMOUNT, user.address, intentHash);

            await expect(hook.connect(orchestrator).execute(ctx, "0x"))
                .to.emit(hook, "BridgeInitiated")
                .withArgs(intentHash, user.address, tokenAddr, BRIDGE_AMOUNT, anyValue);
        });

        it("emits BridgeInitiated with the overridden recipient from fulfillHookData", async () => {
            const intentHash = ethers.hexlify(ethers.randomBytes(32));
            const ctx = buildContext(tokenAddr, BRIDGE_AMOUNT, user.address, intentHash);

            await expect(hook.connect(orchestrator).execute(ctx, encodeRecipient(other.address)))
                .to.emit(hook, "BridgeInitiated")
                .withArgs(intentHash, other.address, tokenAddr, BRIDGE_AMOUNT, anyValue);
        });

        it("emits BridgeInitiated with a non-zero timestamp", async () => {
            const ctx = buildContext(tokenAddr, BRIDGE_AMOUNT, user.address);
            const tx = await hook.connect(orchestrator).execute(ctx, "0x");
            const receipt = await tx.wait();
            const block = await ethers.provider.getBlock(receipt!.blockNumber);

            await expect(tx)
                .to.emit(hook, "BridgeInitiated")
                .withArgs(anyValue, anyValue, tokenAddr, anyValue, block!.timestamp);
        });
    });

    // ── execute – token transfers ─────────────────────────────────────────────────

    describe("execute – token transfers", () => {
        let hook: SkaleBridgeHook;
        let orchestrator: HardhatEthersSigner;
        let user: HardhatEthersSigner;
        let mockToken: MockERC20;
        let mockDepositBox: MockDepositBoxERC20;
        let tokenAddr: string;
        let hookAddr: string;
        let depositBoxAddr: string;

        beforeEach(async () => {
            ({ hook, orchestrator, user, mockToken, mockDepositBox, tokenAddr, hookAddr, depositBoxAddr } =
                await loadFixture(deployWhitelistEnabledFixture));
        });

        it("moves tokens from the orchestrator to the deposit box", async () => {
            const ctx = buildContext(tokenAddr, BRIDGE_AMOUNT, user.address);
            const orchestratorBefore = await mockToken.balanceOf(orchestrator.address);
            const depositBoxBefore = await mockToken.balanceOf(depositBoxAddr);

            await hook.connect(orchestrator).execute(ctx, "0x");

            expect(await mockToken.balanceOf(orchestrator.address)).to.equal(orchestratorBefore - BRIDGE_AMOUNT);
            expect(await mockToken.balanceOf(depositBoxAddr)).to.equal(depositBoxBefore + BRIDGE_AMOUNT);
        });

        it("leaves zero token balance in the hook after execution", async () => {
            const ctx = buildContext(tokenAddr, BRIDGE_AMOUNT, user.address);
            await hook.connect(orchestrator).execute(ctx, "0x");
            expect(await mockToken.balanceOf(hookAddr)).to.equal(0n);
        });

        it("correctly transfers partial amounts in successive executions", async () => {
            const half = BRIDGE_AMOUNT / 2n;
            const ctx1 = buildContext(tokenAddr, half, user.address);
            const ctx2 = buildContext(tokenAddr, half, user.address);

            await hook.connect(orchestrator).execute(ctx1, "0x");
            await hook.connect(orchestrator).execute(ctx2, "0x");

            expect(await mockToken.balanceOf(depositBoxAddr)).to.equal(BRIDGE_AMOUNT);
            expect(await mockToken.balanceOf(orchestrator.address)).to.equal(BRIDGE_AMOUNT * 10n - BRIDGE_AMOUNT);
        });

        it("reverts when orchestrator has insufficient token balance", async () => {
            const tooMuch = (await mockToken.balanceOf(orchestrator.address)) + 1n;
            const ctx = buildContext(tokenAddr, tooMuch, user.address);

            await mockToken.connect(orchestrator).approve(hookAddr, tooMuch);
            await expect(hook.connect(orchestrator).execute(ctx, "0x")).to.be.reverted;
        });

        it("reverts when orchestrator has not approved the hook", async () => {
            // Deploy fresh token with no approval
            const freshToken = await deployMockERC20("Fresh", "FR");
            await freshToken.mint(orchestrator.address, BRIDGE_AMOUNT);
            const freshAddr = await freshToken.getAddress();
            await mockDepositBox.setTokenMapping(freshAddr, SCHAIN_NAME, ethers.Wallet.createRandom().address);

            const ctx = buildContext(freshAddr, BRIDGE_AMOUNT, user.address);
            await expect(hook.connect(orchestrator).execute(ctx, "0x")).to.be.reverted;
        });
    });
});
