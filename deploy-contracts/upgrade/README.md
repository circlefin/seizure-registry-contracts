# SeizureRegistry Upgrades

This directory contains tooling for upgrading the SeizureRegistry UUPS proxy.

## Directory structure

```
deploy-contracts/upgrade/
├── 001_UpgradeSeizureRegistry.s.sol  # Upgrade script: upgrades the proxy to a new implementation
├── UpgradeConstants.sol               # Env var key name constants for upgrade scripts
└── REINITIALIZER_TEMPLATE.sol         # Boilerplate for upgrades that add new storage state
```

## When to use this

`001_UpgradeSeizureRegistry.s.sol` is an example of a **storage-compatible upgrade script**. Use it when the new implementation requires no new storage state (logic-only change, different `TOKEN` address, etc.). It always passes empty calldata to `upgradeToAndCall`.

**Reinitializer upgrades** (new storage fields via `reinitializer(N)`) need their own numbered script. Copy `001_UpgradeSeizureRegistry.s.sol`, add read calls per reinitializer parameter, encode with `abi.encodeCall`, and pass the result to `upgradeToAndCall` instead of `""`. See `REINITIALIZER_TEMPLATE.sol` for the implementation contract boilerplate.

## Prerequisites

1. A new `SeizureRegistry` implementation has already been deployed to the target network.
2. Copy `.env.example` to `.env` and fill in the upgrade-specific values:

   ```bash
   cp .env.example .env
   ```

3. Source the env file:

   ```bash
   source .env
   ```

## Environment variables

### `001_UpgradeSeizureRegistry.s.sol` (storage-compatible)

| Variable | Required | Description |
|---|---|---|
| `OWNER_ADDRESS` | Yes | Transaction broadcaster. **Must be the current proxy owner.** |
| `SR_PROXY_ADDRESS` | Yes | The deployed SeizureRegistry proxy address. |
| `SR_OLD_IMPL_ADDRESS` | Yes | The implementation currently behind the proxy. Asserted before broadcast to prevent double-execution and catch wrong-proxy mistakes. |
| `SR_NEW_IMPL_ADDRESS` | Yes | The newly deployed implementation address. |

Reinitializer upgrade scripts define their own additional env vars for each typed parameter.

## Running the upgrade script

### Dry run (no transactions sent)

```bash
forge script deploy-contracts/upgrade/001_UpgradeSeizureRegistry.s.sol \
  --rpc-url $RPC_URL
```

### Live broadcast

The broadcaster is `OWNER_ADDRESS`, which must be the current proxy owner.

```bash
forge script deploy-contracts/upgrade/001_UpgradeSeizureRegistry.s.sol \
  --rpc-url $RPC_URL \
  --broadcast \
  --private-key $OWNER_PRIVATE_KEY
```

The script prints the pre-upgrade and post-upgrade state. Confirm "All validations passed!" and that the logged implementation address matches `SR_NEW_IMPL_ADDRESS`.

## Reinitializer upgrades

When the new implementation adds storage state via `reinitializer(N)`:

1. Copy `REINITIALIZER_TEMPLATE.sol` and follow the storage safety checklist below to write the new implementation contract.
2. Copy `001_UpgradeSeizureRegistry.s.sol` into a new file (e.g. `001_UpgradeSeizureRegistryVN.s.sol`). Add read calls per reinitializer parameter, encode with `abi.encodeCall`, and pass the result to `upgradeToAndCall` instead of `""`.
3. Run the said script, in addition to other scripts related to bytecode and state verification.

### Storage safety checklist

Before writing a single field:

**[ ] 1. Pick the correct N**

`reinitializer(N)` where N = (highest N used so far) + 1. See the version history table below. A wrong N either silently no-ops (already initialized) or reverts (version not yet reached).

**[ ] 2. Fresh namespace — never reuse an existing namespace**

Each new feature gets its own EIP-7201 namespace string and storage library. Namespaces already in use:

- `circle.SeizureRegistry.SecondaryMarketBurnable`
- `circle.SeizureRegistry.HashUpdatable`
- `circle.SeizureRegistry.Allowlistable`
- `circle.SeizureRegistry.Rescuable`

Compute your slot via ``keccak256(abi.encode(uint256(keccak256(bytes("<your.namespace.string>"))) - 1)) & ~bytes32(uint256(0xff))`

**[ ] 3. Constructor — always forward `tokenContract_`**

Pass the existing token address to preserve `TOKEN()`, or a new address to update it.

## Reinitializer version history

| Version | Contract | Function |
|---|---|---|
| 1 | `UpgradeablePlaceholder` | `initialize(address)` |
| 2 | `SeizureRegistry` | `initialize(address,address,address,address)` |

The next upgrade that adds state must use `reinitializer(3)`.
