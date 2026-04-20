# SKALE Bridge Post-Intent Hook

A [Peer.xyz / zkp2p V3](https://docs.peer.xyz/developer/developer/api/v3/post-intent-hooks)
**post-intent hook** that bridges the deposit token from Base to a SKALE chain
through [SKALE IMA](https://github.com/skalenetwork/IMA) immediately after an
intent is fulfilled on zkp2p.

## How it works

Post-intent hooks run during `fulfillIntent` on the OrchestratorV2, after the
payment proof has been verified and all fees have been deducted. The flow:

```
  User → OrchestratorV2 (Base) ─── fulfillIntent ──▶  SkaleBridgeHook (Base)
                                                        │
                                                        │ depositERC20Direct
                                                        ▼
                                                    DepositBoxERC20 (Base)
                                                        │
                                                        │ IMA message
                                                        ▼
                                                    SKALE chain → recipient
```

At fulfill time the Orchestrator:

1. Computes `executableAmount = releaseAmount − fees`.
2. Approves the hook to pull exactly `executableAmount` of the deposit token.
3. Calls `hook.execute(ctx, fulfillHookData)`.
4. Verifies the hook pulled exactly `executableAmount` and did not send tokens
   back to the Orchestrator, then resets the allowance to `0`.

`SkaleBridgeHook` uses that allowance to pull the tokens from the Orchestrator,
approves the IMA `DepositBoxERC20`, and calls `depositERC20Direct` to deliver
them to the recipient on the configured SKALE chain. The recipient defaults to
`ctx.intent.to` and can be overridden by passing an ABI-encoded `address` in
`fulfillHookData`.

See [docs.peer.xyz — Post-intent hooks](https://docs.peer.xyz/developer/developer/api/v3/post-intent-hooks)
for the full hook lifecycle and invariants.

## Contract

### `SkaleBridgeHook.sol`

Implements [IPostIntentHookV2](contracts/interfaces/IPostIntentHookV2.sol)
and [ISkaleBridgeHook](contracts/interfaces/ISkaleBridgeHook.sol).

Constructor parameters:

| Name              | Description                                                              |
| ----------------- | ------------------------------------------------------------------------ |
| `_orchestrator`   | zkp2p OrchestratorV2 address on the source chain (Base)                  |
| `_depositBox`     | SKALE IMA `DepositBoxERC20` address on the source chain                  |
| `_messageProxy`   | SKALE IMA `MessageProxyForMainnet` address on the source chain           |
| `_skaleChainName` | Destination SKALE chain name (verified via `isConnectedChain` at deploy) |

Owner-only configuration:

- `addTokenToWhitelist(address token)` — mark a token as bridgeable by this hook.
- `removeTokenFromWhitelist(address token)` — revoke a token.

A deposit is allowed if the token is whitelisted on the `DepositBoxERC20` for
the destination SKALE chain **or** whitelisted locally on this hook.

## Project layout

```
contracts/              Solidity sources (Hardhat + Foundry)
  SkaleBridgeHook.sol
  interfaces/
script/                 Foundry deploy scripts
migrations/             Hardhat deploy scripts (TypeScript)
```

Both toolchains compile the same source tree but write artifacts to separate
folders so they never clobber each other:

| Tool    | Artifacts    | Cache          |
| ------- | ------------ | -------------- |
| Hardhat | `artifacts/` | `cache/`       |
| Foundry | `forge-out/` | `forge-cache/` |

## Setup

```bash
# Node / Hardhat toolchain
yarn install

# Foundry toolchain (installs forge-std into lib/)
forge install foundry-rs/forge-std --no-git
```

Copy `.env.example` to `.env` and fill in the deployment variables.

## Build

```bash
# Hardhat
yarn compile

# Foundry
forge build
```

## Lint

```bash
yarn lint            # solhint
forge fmt --check
```

## Deploy

Set environment variables (see `.env.example`):

| Variable           | Description                                                                     |
| ------------------ | ------------------------------------------------------------------------------- |
| `PRIVATE_KEY`      | Deployer private key                                                            |
| `ENDPOINT`         | RPC URL of the source chain (Base / Base Sepolia)                               |
| `ORCHESTRATOR`     | OrchestratorV2 address (`0x888888359E981B5225CA48fbCdCeff702FC3b888` on Base)   |
| `DEPOSIT_BOX`      | `DepositBoxERC20` address on the source chain                                   |
| `MESSAGE_PROXY`    | `MessageProxyForMainnet` address on the source chain                            |
| `SKALE_CHAIN_NAME` | Destination SKALE chain name                                                    |
| `OWNER`            | *(optional)* Address to transfer ownership (2-step) to after deploy             |

### Hardhat

```bash
yarn hardhat run migrations/deploySkaleBridgeHook.ts --network custom
```

### Foundry

```bash
forge script script/DeploySkaleBridgeHook.s.sol:DeploySkaleBridgeHook \
  --rpc-url "$ENDPOINT" \
  --private-key "$PRIVATE_KEY" \
  --broadcast \
  -vvvv
```

## Using the hook from zkp2p

Pass the deployed hook address as `postIntentHook` when signaling an intent:

```ts
await orchestrator.signalIntent({
  escrow,
  depositId,
  amount,
  to,                                    // default recipient on SKALE
  paymentMethod,
  fiatCurrency,
  conversionRate,
  referralFees: [],
  gatingServiceSignature,
  signatureExpiration,
  postIntentHook: skaleBridgeHookAddress,
  preIntentHookData: "0x",
  data: "0x",                            // signalHookData (unused by this hook)
});
```

Optionally override the destination address at fulfill time by passing an
ABI-encoded `address` as `postIntentHookData`:

```ts
await orchestrator.fulfillIntent({
  paymentProof,
  intentHash,
  verificationData: "0x",
  postIntentHookData: ethers.AbiCoder.defaultAbiCoder().encode(
    ["address"],
    [overrideRecipient],
  ),
});
```

If `postIntentHookData` is empty (or decodes to `address(0)`) the hook uses
`ctx.intent.to`.

## Reference addresses

| Contract                     | Network      | Address                                      |
| ---------------------------- | ------------ | -------------------------------------------- |
| OrchestratorV2 (zkp2p)       | Base         | `0x888888359E981B5225CA48fbCdCeff702FC3b888` |
| EscrowV2 (zkp2p)             | Base         | `0x777777779d229cdF3110e9de47943791c26300Ef` |
| IMA `MessageProxyForMainnet` | Base         | `0x2C3cae1A2143De33F7fe887ad0428d33BBBd0A62` |
| IMA `MessageProxyForMainnet` | Base Sepolia | `0xA1e244C6cE94FF2bb5f4533783FBc44D1f190045` |
| IMA `DepositBoxERC20`        | Base         | `0x7f54e52D08C911eAbB4fDF00Ad36ccf07F867F61` |
| IMA `DepositBoxERC20`        | Base Sepolia | `0x6722D0f037A461a568155EA0490753E9C8825FC9` |

Always re-verify the IMA and zkp2p addresses against their official docs
before deploying.

## License

MIT
# SKALE Bridge Post-Intent Hook for zkp2p

Post-intent hook for Peer.xyz/zkp2p that automatically bridges USDC from Base to SKALE Base when users onramp.

## Architecture

```
User → zkp2p (Base) → SkaleBridgeHook → IMA Message → SkaleReceiver (SKALE Base) → User
```

## Contracts

### SkaleBridgeHook.sol (Base)
- Post-intent hook implementing `IPostIntentHookV2`
- Receives USDC from zkp2p Orchestrator after intent fulfillment
- Sends IMA message to SKALE Base
- Locks tokens for liquidity-based bridging

### SkaleReceiver.sol (SKALE Base)
- Receives IMA messages from Base
- Releases mapped USDC to recipients
- Must be registered with SKALE's MessageProxy

## Setup

```bash
# Install dependencies

```

## Deployment

### Testnet

```bash
# Deploy to Base Sepolia


# Deploy to SKALE Base Sepolia

```

### Mainnet

```bash
# Deploy to Base


# Deploy to SKALE Base

```

### Register SKALE Receiver

After deploying `SkaleReceiver`, register it with SKALE's MessageProxy:

```bash
cast send 0xd2AAa00100000000000000000000000000000000 \
  "grantRole(bytes32,address)" \
  0x96e3fc3be15159903e053027cff8a23f39a990e0194abcd8ac1cf1b355b8b93c \
  <RECEIVER_ADDRESS> \
  --rpc-url <SKALE_RPC>
```

## Usage

### Signal Intent with Hook

```typescript
import { OrchestratorV2 } from "@peerxyz/orchestrator";

await orchestrator.signalIntent({
  escrow: escrowAddress,
  depositId: depositId,
  amount: amount,
  to: recipientAddress,
  paymentMethod: keccak256("card"),
  postIntentHook: hookAddress, // SkaleBridgeHook address
  data: abi.encode(recipientAddress) // Optional: override recipient
});
```

### Fund SKALE Receiver

The SkaleReceiver contract needs to be funded with mapped USDC to release to recipients:

```bash

```

## Addresses

### Base
| Network | USDC |
|---------|------|
| Mainnet | `0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913` |
| Sepolia | `0x03655B2e3C0C3D9a5bB79b5451ea47eFCDbd3AAF` |

### SKALE Base
| Network | Chain ID | USDC |
|---------|----------|------|
| Mainnet | 1187947933 | TBD |
| Sepolia | 324705682 | `0x2e08028E3C4c2356572E096d8EF835cD5C6030bD` |

### Contracts
| Contract | Address |
|----------|---------|
| OrchestratorV2 (Base) | `0x888888359E981B5225CA48fbCdCeff702FC3b888` |
| MessageProxy (SKALE) | `0xd2AAa00100000000000000000000000000000000` |

## Testing

```bash
```

## Important Notes

### SKALE Native Bridge

SKALE's native DepositBox is designed for **Ethereum → SKALE** bridging. For Base → SKALE, this implementation uses:

1. **IMA Messaging**: Cross-chain communication between Base and SKALE Base
2. **Liquidity Model**: Tokens locked on Base, released from pre-funded liquidity on SKALE Base

### TODO Items

1. Verify if MessageProxy exists on Base for direct IMA communication
2. Find actual DepositBox address on Base (if exists)
3. Confirm SKALE Base mainnet USDC address
4. Set up automated liquidity management for SkaleReceiver

## License

MIT
