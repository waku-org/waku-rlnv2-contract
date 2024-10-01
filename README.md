# waku-rlnv2-contract [![Github Actions][gha-badge]][gha] [![Foundry][foundry-badge]][foundry] [![License: MIT][license-badge]][license]

[gha]: https://github.com/waku-org/waku-rlnv2-contract/actions
[gha-badge]: https://github.com/waku-org/waku-rlnv2-contract/actions/workflows/ci.yml/badge.svg
[foundry]: https://getfoundry.sh/
[foundry-badge]: https://img.shields.io/badge/Built%20with-Foundry-FFDB1C.svg
[license]: https://opensource.org/licenses/MIT
[license-badge]: https://img.shields.io/badge/License-MIT-blue.svg

Waku's RLNv2 contracts, which include -

- LazyIMT, which allows the root of the chain to be accessible on-chain.

## What's Inside

- [Forge](https://github.com/foundry-rs/foundry/blob/master/forge): compile, test, fuzz, format, and deploy smart
  contracts
- [Forge Std](https://github.com/foundry-rs/forge-std): collection of helpful contracts and cheatcodes for testing
- [Solhint Community](https://github.com/solhint-community/solhint-community): linter for Solidity code

## Prerequisites

- `pnpm` ([installation instructions](https://pnpm.io/installation))

## Usage

Install dependencies before first run:

```sh
pnpm install
```

This is a list of the most frequently needed commands.

### Build

Build the contracts:

```sh
$ forge build
```

### Clean

Delete the build artifacts and cache directories:

```sh
$ forge clean
```

### Compile

Compile the contracts:

```sh
$ forge build
```

### Coverage

Get a test coverage report:

```sh
$ forge coverage
```

### Deploy

#### Deploy to Anvil:

```sh
$ TOKEN_ADDRESS=0x1122334455667788990011223344556677889900 forge script script/Deploy.s.sol --broadcast --rpc-url localhost --tc Deploy
```

Replace the `TOKEN_ADDRESS` value by a token address you have deployed on anvil. A `TestToken` is available in
`test/TestToken.sol` and can be deployed with

```sh
forge script test/TestToken.sol --broadcast --rpc-url localhost --tc TestTokenFactory
```

For this script to work, you need to have a `MNEMONIC` environment variable set to a valid
[BIP39 mnemonic](https://iancoleman.io/bip39/).

#### Deploy to Sepolia:

Ensure that you use the [cast wallet](https://book.getfoundry.sh/reference/cast/cast-wallet) to store private keys that
will be used in deployments.

```sh
$ export RPC_URL=<rpc-url>
$ export ACCOUNT=<account name in foundry keystore>
$ pnpm deploy:sepolia
```

### Format

Format the contracts:

```sh
$ forge fmt
```

### Gas Usage

Get a gas report:

```sh
$ forge test --gas-report
```

### Lint

Lint the contracts:

```sh
$ pnpm lint
```

#### Fixing linting issues

For any errors in solidity files, run `forge fmt`. For errors in any other file type, run `pnpm prettier:write`.

### Test

Run the tests:

```sh
$ forge test
```

## Notes

1. Foundry uses [git submodules](https://git-scm.com/book/en/v2/Git-Tools-Submodules) to manage dependencies. For
   detailed instructions on working with dependencies, please refer to the
   [guide](https://book.getfoundry.sh/projects/dependencies.html) in the book
2. You don't have to create a `.env` file, but filling in the environment variables may be useful when debugging and
   testing against a fork.

## Owner privileges

The contract implementation aims to follow the
[specification](https://github.com/waku-org/specs/blob/81b9fd588bff39894608746774b0903b067b5cdf/standards/core/rln-contract.md)
that also describes ownership (see
[Governance and upgradability](https://github.com/waku-org/specs/blob/81b9fd588bff39894608746774b0903b067b5cdf/standards/core/rln-contract.md#governance-and-upgradability)
section).

As of commit afb858, the `Owner` privileges are assigned to the `msg.sender` of the membership registration transaction.
The `Owner` has the following privileges:

- set the token and price of one message published per epoch
  ([link](https://github.com/waku-org/waku-rlnv2-contract/blob/main/src/LinearPriceCalculator.sol#L25));
- authorize upgrades to a new implementation contract
  ([link](https://github.com/waku-org/waku-rlnv2-contract/blob/main/src/WakuRlnV2.sol#L99));
- set the price calculator contract address
  ([link](https://github.com/waku-org/waku-rlnv2-contract/blob/main/src/WakuRlnV2.sol#L267));
- set the maximum total rate limit of all memberships in the membership set
  ([link](https://github.com/waku-org/waku-rlnv2-contract/blob/main/src/WakuRlnV2.sol#L273));
- set the minimum ([link](https://github.com/waku-org/waku-rlnv2-contract/blob/main/src/WakuRlnV2.sol#L287)) and maximum
  ([link](https://github.com/waku-org/waku-rlnv2-contract/blob/main/src/WakuRlnV2.sol#L280)) rate limit of one
  membership;
- set the duration of the active period
  ([link](https://github.com/waku-org/waku-rlnv2-contract/blob/main/src/WakuRlnV2.sol#L295)) and grace period
  ([link](https://github.com/waku-org/waku-rlnv2-contract/blob/main/src/WakuRlnV2.sol#L302)) of new memberships (see the
  [state transition diagram of a membership](https://github.com/waku-org/specs/blob/81b9fd588bff39894608746774b0903b067b5cdf/standards/core/rln-contract.md#membership-lifecycle)).

The pause functionality for contract functions is not yet implemented.

## License

This project is licensed under MIT.
