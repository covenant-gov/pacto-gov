# Pacto Gov — Nave Pirata

Governance contracts for Pacto squads. Each squad deploys a "Nave Pirata" (pirate ship) — a hat-governed mesh of role contracts sitting on top of a Safe — via a one-shot factory call.

## Nave Pirata contracts

The system is built around **Hats-Pointer Upgradeability**: authority is a Hats Protocol hat, and upgrading a role contract is a `transferHat` call rather than a proxy migration. See the design docs for the full architecture.

**Docs**:
- [Architecture](./ai-docs/nave-pirata-hats-pointer-architecture.md) — hat tree, roles, invariants, upgrade paths, named patterns.
- [Tech spec](./ai-docs/nave-pirata-tech-spec.md) — interfaces, storage strategy, bootstrap sequence, resolved decisions, execution phases.

**Contracts (v1)**:
- `Quartermaster` — timelocked crew roster, admin of the crew hat.
- `MutinyModule` — 51%-of-snapshot captain accountability, admin of the captain hat; also supports voluntary captain resignation.
- `TreasuryAuthority` — two-body democracy (crew majority + captain approval) over the squad's Safe. Both the Safe's sole owner *and* its sole Zodiac module. Inherits `AssetRescuer`.
- `SquadAdmin` — UUPS proxy for application-level admin predicates; captain-upgradeable.
- `NavePirataFactory` — one-shot bootstrap that atomically deploys the Safe, creates the hat tree, deploys clones, wires the Safe, and registers the deployment.
- `NavePirataRegistry`, `RoleHatClonesFactory`, `RoleHatUpgrader` — infra for discovery and upgrade ceremonies.
- `AssetRescuer` (abstract) — shared primitive; permissionless sweep of accidentally-received ETH / ERC-20 / ERC-721 / ERC-1155 to a fixed destination.

---

## Boilerplate features

<dl>
  <dt>Foundry setup</dt>
  <dd>Foundry configuration with multiple custom profiles and remappings.</dd>

  <dt>Deployment scripts</dt>
  <dd>Sample scripts to deploy contracts on both mainnet and testnet.</dd>

  <dt>Sample Integration, Unit, Property-based fuzzed and symbolic tests</dt>
  <dd>Example tests showcasing mocking, assertions and configuration for mainnet forking. As well it includes everything needed in order to check code coverage.</dd>
  <dd>Unit tests are built based on the <a href="https://twitter.com/PaulRBerg/status/1682346315806539776">Branched-Tree Technique</a>, using <a href="https://github.com/alexfertel/bulloak">Bulloak</a>.

  <dt>Linter</dt>
  <dd>Simple and fast solidity linting thanks to forge fmt.</dd>
  <dd>Find missing natspec automatically.</dd>

  <dt>Github workflows CI</dt>
  <dd>Run all tests and see the coverage as you push your changes.</dd>
  <dd>Export your Solidity interfaces and contracts as packages, and publish them to NPM.</dd>
</dl>

## Setup

1. Install Foundry by following the instructions from [their repository](https://github.com/foundry-rs/foundry#installation).
2. Copy the `.env.example` file to `.env` and fill in the variables.
3. Install rust dependencies with [cargo](https://doc.rust-lang.org/cargo/getting-started/installation.html):
   1. `cargo install lintspec`
   2. `cargo install bulloak`
4. Install the dependencies by running: `pnpm install`. In case there is an error with the commands, run `foundryup` and try them again.

## Build

The default way to build the code is suboptimal but fast, you can run it via:

```bash
pnpm build
```

In order to build a more optimized code ([via IR](https://docs.soliditylang.org/en/v0.8.15/ir-breaking-changes.html#solidity-ir-based-codegen-changes)), run:

```bash
pnpm build:optimized
```

## Running tests

Unit tests should be isolated from any externalities, while Integration usually run in a fork of the blockchain. In this boilerplate you will find example of both.

In order to run both unit and integration tests, run:

```bash
pnpm test
```

In order to just run unit tests, run:

```bash
pnpm test:unit
```

In order to run unit tests and run way more fuzzing than usual (5x), run:

```bash
pnpm test:unit:deep
```

In order to just run integration tests, run:

```bash
pnpm test:integration
```

In order to check your current code coverage, run:

```bash
pnpm coverage
```

In order to create a new `.t.sol` file from a `.tree` bulloak file, run:

```bash
pnpm test:bulloak:scaffold
```

In order to fix or add missing tests to a `.t.sol` file after changing a `.tree` bulloak file, run:

```bash
pnpm test:bulloak:fix
```

<br>

## Deploy & verify

### Setup

Configure the `.env` variables and source them:

```bash
source .env
```

Import your private keys into Foundry's encrypted keystore:

```bash
cast wallet import $MAINNET_DEPLOYER_NAME --interactive
```

```bash
cast wallet import $SEPOLIA_DEPLOYER_NAME --interactive
```

### Sepolia

```bash
pnpm deploy:sepolia
```

### Mainnet

```bash
pnpm deploy:mainnet
```

The deployments are stored in ./broadcast

See the [Foundry Book for available options](https://book.getfoundry.sh/reference/forge/forge-create.html).

## Export And Publish

Export TypeScript interfaces from Solidity contracts and interfaces providing compatibility with TypeChain. Publish the exported packages to NPM.

To enable this feature, make sure you've set the `NPM_TOKEN` on your org's secrets. Then set the job's conditional to `true`:

```yaml
jobs:
  export:
    name: Generate Interfaces And Contracts
    # Remove the following line if you wish to export your Solidity contracts and interfaces and publish them to NPM
    if: true
    ...
```

Also, remember to update the `package_name` param to your package name:

```yaml
- name: Export Solidity - ${{ matrix.export_type }}
  uses: defi-wonderland/solidity-exporter-action@1dbf5371c260add4a354e7a8d3467e5d3b9580b8
  with:
    # Update package_name with your package name
    package_name: "my-cool-project"
    ...


- name: Publish to NPM - ${{ matrix.export_type }}
  # Update `my-cool-project` with your package name
  run: cd export/my-cool-project-${{ matrix.export_type }} && npm publish --access public
  ...
```

You can take a look at our [solidity-exporter-action](https://github.com/defi-wonderland/solidity-exporter-action) repository for more information and usage examples.

## Licensing
The primary license for the boilerplate is MIT, see [`LICENSE`](https://github.com/defi-wonderland/solidity-foundry-boilerplate/blob/main/LICENSE)
