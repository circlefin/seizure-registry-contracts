# SeizureRegistry Deployment

This directory contains the deploy scripts for the **SeizureRegistry** UUPS proxy system.

SeizureRegistry is Ethereum-only and uses plain `new` throughout — no CREATE2, no factory contract, no pre-compiled artifacts.

## Directory Structure

```
deploy-contracts/
├── 000_DeploySeizureRegistry.s.sol   # Deploys and initializes the full proxy system
├── 001_DeployedContractBytecodeValidation.s.sol  # Verifies on-chain bytecode matches audited source
├── 002_DeployedContractStateValidation.s.sol     # Verifies on-chain state matches expected config
├── AcceptOwnership.s.sol                    # Completes 2-step ownership transfer (designated owner)
├── compiled-contract-artifacts/             # Pinned bytecode snapshots used by the validation script
│   ├── SeizureRegistry.json
│   ├── UpgradeablePlaceholder.json
│   └── ERC1967Proxy.json
└── shared/
│   ├── BaseDeployScript.sol                 # Abstract base: _readAddress env var helper
│   └── Constants.sol                        # Env var key name constants
└── upgrade/
    ├── 001_UpgradeSeizureRegistry.s.sol     # Upgrades the proxy to a new implementation
    ├── UpgradeConstants.sol                 # Env var key name constants for upgrades
    └── REINITIALIZER_TEMPLATE.sol           # Boilerplate for state-adding upgrades
    └── .env.example                         # Boilerplate example env for an upgrade
```

See [`upgrade/README.md`](upgrade/README.md) for upgrade instructions and the reinitializer safety checklist.

## Prerequisites

1. Copy `.env.example` to `.env` and fill in all values:
   ```bash
   cp .env.example .env
   ```

2. Source the env file:
   ```bash
   source .env
   ```

3. Ensure the deployer account has sufficient ETH on the target network.


## Deployment Sequence

The script performs five steps in a single broadcast:

1. Deploy `UpgradeablePlaceholder` — no-op UUPS implementation; gives the proxy a valid upgradeable impl from birth and establishes deployer as owner atomically.
2. Deploy `SeizureRegistry` implementation — sets the `TOKEN` immutable and disables direct initialization.
3. Deploy `ERC1967Proxy` pointed at the placeholder — deployer becomes proxy owner at construction.
4. `upgradeToAndCall` — swaps impl to `SeizureRegistry` and initializes all four roles atomically.
5. `transferOwnership` — begins 2-step handoff to the designated owner.

## Running the Deploy Script

### Dry run (no transactions sent)

```bash
forge script deploy-contracts/000_DeploySeizureRegistry.s.sol \
  --rpc-url $RPC_URL
```

### Live broadcast

```bash
forge script deploy-contracts/000_DeploySeizureRegistry.s.sol \
  --rpc-url $RPC_URL \
  --broadcast \
  --private-key $PRIVATE_KEY
```

`$PRIVATE_KEY` must correspond to `$DEPLOYER_ADDRESS`.

The script prints the deployed addresses on completion:

```
SeizureRegistry implementation:  0x...
UpgradeablePlaceholder:          0x...
SeizureRegistry proxy:           0x...
Pending owner (must call acceptOwnership()): 0x...
```

Broadcast artifacts (transaction data, receipts) are saved to `broadcast/`.

## Post-Deploy: Accept Ownership

The deploy script initiates a 2-step ownership transfer. The designated owner must run `AcceptOwnership.s.sol` to complete it.

### Required env vars

| Var | Purpose |
|---|---|
| `SR_PROXY_ADDRESS` | Deployed SeizureRegistry proxy address |
| `SR_OWNER_ADDRESS` | Designated owner accepting ownership (must equal `pendingOwner` set at deploy time) |

### Dry run

```bash
forge script deploy-contracts/AcceptOwnership.s.sol \
  --rpc-url $RPC_URL
```

### Live broadcast

```bash
forge script deploy-contracts/AcceptOwnership.s.sol \
  --rpc-url $RPC_URL \
  --broadcast \
  --private-key $PRIVATE_KEY
```

`$PRIVATE_KEY` must correspond to `$SR_OWNER_ADDRESS`.

The script logs ownership state before and after:

```
Owner before:   0x<deployer>
Pending owner:  0x<designated-owner>
Owner after:    0x<designated-owner>
```

Until `acceptOwnership()` is called, `DEPLOYER_ADDRESS` remains the active owner.

## Bytecode Validation

After deployment, run `001_DeployedContractBytecodeValidation.s.sol` to prove the deployed contracts
match the audited source. The script reads live runtime bytecode from the chain and compares it against
the pinned artifacts in `compiled-contract-artifacts/`. It checks:

1. The `TOKEN` immutable on the `SeizureRegistry` implementation matches the expected constructor arg.
2. Runtime bytecode of the `SeizureRegistry` implementation matches the audited artifact.
3. Runtime bytecode of `UpgradeablePlaceholder` matches the audited artifact.
4. Runtime bytecode of the `ERC1967Proxy` matches the audited artifact.
5. The proxy's EIP-1967 implementation slot points to the `SeizureRegistry` implementation.

### Required env vars

In addition to the deploy env vars, set the three deployed addresses:

```bash
export SR_IMPL_ADDRESS=0x...          # SeizureRegistry implementation address
export SR_UPGRADEABLE_PLACEHOLDER_IMPL_ADDRESS=0x...   # UpgradeablePlaceholder address
export SR_PROXY_ADDRESS=0x...         # ERC1967Proxy address
# TOKEN_CONTRACT_ADDRESS is already set from deployment
```

### Run against a live network or fork

```bash
forge script deploy-contracts/001_DeployedContractBytecodeValidation.s.sol \
  --rpc-url $RPC_URL
```

On success every check prints `[OK]` and the script exits cleanly. On any mismatch it prints
`[ERROR]` details and reverts with a descriptive message, producing a non-zero exit code suitable
for CI.

### Updating the pinned artifacts

The files in `compiled-contract-artifacts/` are committed snapshots of the compiler output at the
audited source commit. Only update them after a re-audit. To regenerate:

```bash
bash scripts/compile_artifacts.sh
```

## State Validation

After deployment (and optionally after ownership transfer), run `002_DeployedContractStateValidation.s.sol`
to assert every on-chain state value matches the expected configuration. The script checks:

1. `owner()` and `pendingOwner()` — conditioned on `SR_OWNERSHIP_TRANSFER_COMPLETED`.
2. `TOKEN()` immutable — readable through the proxy via delegatecall.
3. All four role addresses: `secondaryMarketBurner()`, `hashUpdater()`, `rescuer()`, `addressManager()`.
4. The proxy's EIP-1967 implementation slot points to the `SeizureRegistry` implementation.

Any mismatch reverts with a descriptive message and a non-zero exit code, suitable for CI.

### Required env vars

All deploy env vars carry over. Set the two post-deploy addresses and the ownership flag:

| Var | Purpose |
|---|---|
| `SR_IMPL_ADDRESS` | SeizureRegistry implementation address |
| `SR_PROXY_ADDRESS` | Deployed SeizureRegistry proxy address |
| `SR_OWNERSHIP_TRANSFER_COMPLETED` | `false` (default): asserts `owner == DEPLOYER_ADDRESS`, `pendingOwner == SR_OWNER_ADDRESS`. Set to `true` after running `AcceptOwnership` to assert `owner == SR_OWNER_ADDRESS`, `pendingOwner == 0x0` |

### Run against a live network or fork

```bash
forge script deploy-contracts/002_DeployedContractStateValidation.s.sol \
  --rpc-url $RPC_URL
```

On success every check prints `[OK]` and the script exits cleanly.
