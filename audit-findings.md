# Audit Findings — SkaleBridgeHook

**Repository:** `skalenetwork/peer-solidity-hooks`
**Contract in scope:** `contracts/SkaleBridgeHook.sol`

---

## F1 — Misleading test fixture and describe-block names for `isWhitelisted` semantics

**Severity:** Informational / Low
**Status:** Works as expected — naming only

**Background**

IMA's `DepositBoxERC20` exposes:

```solidity
// IMA source
function isWhitelisted(string memory schainName) public view override returns (bool) {
    return !_automaticDeploy[keccak256(abi.encodePacked(schainName))];
}
```

Semantics:
- `isWhitelisted() == true` → IMA whitelist **enabled**, automatic token deployment is **off** → only pre-registered tokens are bridgeable.
- `isWhitelisted() == false` → automatic deploy **on** → any new token gets a clone on the destination chain.

**Issue**

The test fixture names in `test/SkaleBridgeHook.ts` and the corresponding `describe` blocks use labels that are the **opposite** of the IMA convention:

| Entity | `setWhitelistEnabled` call | `isWhitelisted()` returns | IMA meaning | Label used in tests |
|---|---|---|---|---|
| `deployOpenDepositBoxFixture` | `true` | `true` | Whitelist ON / restrictive | ❌ "open mode" |
| `deployStrictDepositBoxFixture` | `false` | `false` | Auto-deploy / permissive | ❌ "strict mode" |

The `describe` labels at lines 421 and 450 repeat the same inversion:
- Line 421: `"DEPOSIT_BOX.isWhitelisted = false, strict mode"` — but `false` is the *permissive* / auto-deploy mode.
- Line 450: `"DEPOSIT_BOX.isWhitelisted = true, open mode"` — but `true` is the *restrictive* / whitelist-on mode.

**Impact**

The actual test assertions are functionally correct and the guard logic in `SkaleBridgeHook._depositToSkale` (`DEPOSIT_BOX.isWhitelisted(chainName) || _whitelistedTokens.contains(token)`) is correct. No production code is affected. The confusion is confined to test fixture names and describe-block strings, which could mislead future contributors auditing or extending the test suite.

**Recommendation**

Rename fixtures and describe blocks to align with IMA semantics:
- `deployOpenDepositBoxFixture` → `deployWhitelistEnabledFixture` (IMA whitelist on, auto-deploy off)
- `deployStrictDepositBoxFixture` → `deployAutoDeployFixture` (IMA whitelist off, auto-deploy on)
- Update the inline comments and describe-block strings accordingly.

---

## F2 — Missing zero-address check on `_depositBox` constructor parameter

**Severity:** Informational / Low
**Status:** Acknowledged — deploy-time responsibility

**Location:** `contracts/SkaleBridgeHook.sol`, constructor

The constructor validates `_orchestrator` and `_messageProxy` against `address(0)` but does not validate `_depositBox`. Passing `address(0)` silently sets `DEPOSIT_BOX` to the zero address; all subsequent `execute` calls revert at the `isWhitelisted` call rather than at construction.

**Impact**

Misconfiguration is caught on first use (Low). No funds are at risk from this alone — the contract simply becomes unusable and must be redeployed.

**Recommendation**

Add `require(_depositBox != address(0), InvalidAddress(_depositBox));` alongside the existing constructor checks. This is consistent with the pattern already in place for the other two immutables.

---

## F3 — Owner set to `msg.sender` at construction

**Severity:** Informational
**Status:** Accepted — deployer responsibility

`Ownable(msg.sender)` hard-codes the deployer as the initial owner. There is no constructor parameter to pass a separate owner address. This is a standard OpenZeppelin pattern and is an operational/deployment-time concern outside the scope of this contract.

---

## F4 — IMA API assumed available on Base

**Severity:** Informational
**Status:** Accepted

The hook imports and depends on `IDepositBoxERC20` from `@skalenetwork/ima-interfaces`. The SKALE team has confirmed IMA is deployed on Base with the same interface, making this concern moot.

---

## F5 — Unused/redundant length check `fulfillHookData.length > 31`

**Severity:** Informational / Low
**Status:** Acknowledged — pre-existing, can be tightened

**Location:** `contracts/SkaleBridgeHook.sol`, `execute()`, line 101

```solidity
if (fulfillHookData.length > 31) {
    (address overrideRecipient) = abi.decode(fulfillHookData, (address));
```

`abi.decode` for a single `address` requires exactly 32 bytes (a zero-padded slot). The guard `> 31` passes for any payload ≥ 32 bytes, including malformed payloads. `abi.decode` on a ≥ 32-byte blob that is not a properly padded address will silently decode a garbage address value. Because the decoded value is checked against `address(0)` before use, the worst-case outcome is that a malformed payload overrides the recipient with a non-zero garbage address.

This code was present in the originally provided contracts.

**Recommendation**

Change `> 31` to `== 32` to enforce the exact ABI encoding expected, or leave it as-is and document the accepted encoding. Either is defensible given the orchestrator is a trusted caller.

---

## F6 — Post-deposit ERC20 approval reset

**Severity:** Informational
**Status:** Rejected — not applicable

**Proposed (rejected):** Reset the ERC20 allowance to zero after `depositERC20Direct` returns.

IMA's `depositERC20Direct` pulls exactly `amount` tokens, leaving zero residual allowance. The next call to `forceApprove` already resets the allowance to zero before setting the new value (that is the purpose of `forceApprove`). An explicit post-call `approve(0)` would be redundant gas expenditure.

---

## F7 — `BridgeInitiated` event: `token` field not emitted

**Severity:** Low
**Status:** Acknowledged

**Location:** `contracts/interfaces/ISkaleBridgeHook.sol`, `BridgeInitiated` event

```solidity
event BridgeInitiated(
    bytes32 indexed intentHash,
    address indexed recipient,
    uint256 indexed amount,
    uint256 timestamp
);
```

The bridged token address is not included in the `BridgeInitiated` event. Off-chain indexers that track bridge activity cannot determine which token was bridged without parsing the internal call to `depositERC20Direct`.

**Recommendation**

Add `address indexed token` to the event signature and pass `ctx.token` when emitting in `execute()`.

---

## F8 — ERC-777 token compatibility

**Severity:** Informational
**Status:** Informational note — no code change required

ERC-777 defines two transfer hooks: `tokensToSend` (called on the sender) and `tokensReceived` (called on the recipient). Whether these fire on `transferFrom` depends on the specific token implementation:

- **Via ERC-777's native `send` / `operatorSend`:** hooks are **mandatory**. If the recipient contract has not registered `IERC777Recipient` in ERC-1820, the transfer must revert per the spec.
- **Via ERC-20 compatibility `transferFrom`:** hooks are **optional per implementation**. The EIP-777 spec says the contract *should* also call hooks on this path, but most real-world ERC-777 tokens do **not** revert when the recipient is unregistered — they skip the hook silently.

IMA's `depositERC20Direct` uses `transferFrom` (ERC-20 path), not `send`. The risk of an ERC-777 token reverting at the hook boundary is therefore low in practice. The residual concern is reentrancy: a token whose `tokensReceived` callback calls back into the hook or orchestrator could create an unexpected execution path. This is extremely unlikely for the tokens expected in production (USDC, USDT, etc., none of which are ERC-777).

**Recommendation**

Add a NatSpec note to `addTokenToWhitelist` warning that ERC-777 tokens with aggressive `tokensReceived` callbacks may introduce unexpected behaviour.
