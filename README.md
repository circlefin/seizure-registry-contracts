# SeizureRegistry Contracts

## Overview

**SeizureRegistry** is an on-chain audit trail and re-mint orchestration system for stablecoin asset recovery on Ethereum. It enables Circle to re-mint blocklisted tokens to allowlisted recipients on ETH, via a process known as a secondaryMarketBurn.

### Key Features

- **Secondary Market Burn & Remint**: Records cross-chain secondaryMarketBurn events (address, domain, amount) and orchestrates a corresponding token mint to an allowlisted recipient.
- **Immutable Token Binding**: The FiatToken contract address is set at construction, and can only be changed via upgrade.
- **Role-Based Access Control**: Four independent roles — `secondaryMarketBurner`, `hashUpdater`, `rescuer`, and `addressManager` — each scoped to a specific operation.
- **Remint Hash Tracking**: After a burn-and-remint, the resulting transaction hash can be recorded on-chain for auditability via a `hashUpdate`.
- **2-Step Ownership**: Uses OpenZeppelin's `Ownable2Step` to prevent accidental ownership loss during administrative transfers.
- **Upgradeable Architecture**: UUPS upgradeable proxy pattern (ERC1967) for future extensibility.

This repository contains the complete smart contract codebase for SeizureRegistry, including deployment scripts, validation scripts, and comprehensive test suites.

## Getting Started

### 1. Clone the repo and initialize submodules

```bash
git clone <your-repo-url>
cd seizure-registry-contracts
```

### 2. Install Foundry

The pinned Foundry version is in `.foundry-version`. Always install from that file — do not run `foundryup` without `--install`, as the nightly build has a checksum mismatch for solc 0.8.35 on some platforms and will produce non-reproducible builds.

```bash
curl -L https://foundry.paradigm.xyz | bash
foundryup --install $(cat .foundry-version)
```

To upgrade the toolchain in future, update `.foundry-version` and re-run `make build` to re-baseline the committed artifacts.

### 3. Install dependencies

```bash
forge install
yarn install
```

## Build & Test

```bash
make build    # Compile all contracts
make test     # Run the full Foundry test suite
```

## Gas Report

To inspect the gas used by the successful FiatToken/MasterMinter remint path:

```bash
forge test --gas-report --match-test test_gasBaseline_secondaryMarketBurnAndRemint
```

## Lint & Format

```bash
make lint     # Lint Solidity sources with Solhint
```

## Repository Structure

### `src/`
Primary source code. Contains the `SeizureRegistry` implementation (`src/SeizureRegistry.sol`), the
proxy bootstrap contract (`src/UpgradeablePlaceholder.sol`), the token interface (`src/interfaces/IMintableToken.sol`),
and all shared modules under `src/modules/` (roles, storage, immutables).

### `test/`
Unit, fuzz, and invariant tests written using Foundry's testing framework. Deploy script tests live in `test/deploy-contracts/`.

### `deploy-contracts/`
Forge scripts for deploying and administering SeizureRegistry:
- `000_DeploySeizureRegistry.s.sol` — deploys the full proxy system and initiates ownership transfer to the designated owner.
- `001_DeployedContractBytecodeValidation.s.sol` — verifies on-chain runtime bytecode matches the audited compiled artifacts.
- `AcceptOwnership.s.sol` — run by the designated owner to complete the 2-step ownership handoff.

See [`deploy-contracts/README.md`](deploy-contracts/README.md) for full usage instructions.

## Deploying

SeizureRegistry is Ethereum-only and deployed via plain `new` (no CREATE2, no factory).

See [`deploy-contracts/README.md`](deploy-contracts/README.md) for the full deployment guide including required env vars and post-deploy steps.

## Architecture

| Property | Value |
|---|---|
| Language | Solidity 0.8.35 |
| Build | Foundry / Forge (pinned — see `.foundry-version`) |
| Proxy pattern | UUPSUpgradeable + ERC1967Proxy |
| Storage | EIP-7201 namespaced storage |
| Ownership | OpenZeppelin Ownable2Step |
| Dependencies | OpenZeppelin Contracts v5.6.1 |
| Target network | Ethereum (mainnet + testnets) |

## License

Apache-2.0
