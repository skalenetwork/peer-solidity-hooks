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
forge install

# Copy environment file
cp .env.example .env
# Edit .env with your private key

# Build contracts
forge build
```

## Deployment

### Testnet

```bash
# Deploy to Base Sepolia
NETWORK=testnet forge script script/DeployBase.s.sol \
  --rpc-url base_sepolia \
  --broadcast

# Deploy to SKALE Base Sepolia
NETWORK=testnet forge script script/DeploySkale.s.sol \
  --rpc-url skale_base_sepolia \
  --broadcast \
  --legacy
```

### Mainnet

```bash
# Deploy to Base
NETWORK=mainnet forge script script/DeployBase.s.sol \
  --rpc-url base_mainnet \
  --broadcast

# Deploy to SKALE Base
NETWORK=mainnet forge script script/DeploySkale.s.sol \
  --rpc-url skale_base_mainnet \
  --broadcast \
  --legacy
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
cast send <RECEIVER_ADDRESS> \
  "fundUsdc(uint256)" \
  <AMOUNT_IN_WEI> \
  --rpc-url <SKALE_RPC>
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
forge test
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
