# TestStableToken

The waku-rlnv2-contract [spec](https://github.com/waku-org/specs/blob/master/standards/core/rln-contract.md) defines
that DAI is to be used to pay for membership registration, with the end-goal being to deploy the contract on mainnet
using an existing stable DAI token.

Before this, we need to perform extensive testing on testnet and local environments (such as
[waku-simulator](https://github.com/waku-org/waku-simulator)). During initial testing, we discovered the need to manage
token minting in testnet environments to limit membership registrations and enable controlled testing of the contract.

TestStableToken is our custom token implementation designed specifically for testing environments, providing controlled
token distribution while mimicking DAI's behaviour.

## Requirements

- **Controlled minting**: Manage token minting through an allowlist of approved accounts, controlled by the token
  contract owner
- **ETH burning mechanism**: Burn ETH when minting tokens to create economic cost (WIP)
- **Proxy architecture**: Use a proxy contract to minimize updates required when the token address changes across other
  components (e.g., nwaku-compose repo or dogfooding instructions)

## Usage

### Deploy new TestStableToken with proxy contract

This script deploys both the proxy and the TestStableToken implementation, initializing the proxy to point to the new
implementation.

```bash
ETH_FROM=$DEPLOYER_ACCOUNT_ADDRESS forge script script/DeployTokenWithProxy.s.sol:DeployTokenWithProxy --rpc-url $RPC_URL --broadcast --private_key $DEPLOYER_ACCOUNT_PRIVATE_KEY
```

or

```bash
MNEMONIC=$TWELVE_WORD_MNEMONIC forge script script/DeployTokenWithProxy.s.sol:DeployTokenWithProxy --rpc-url $RPC_URL --broadcast
```

### Deploy only TestStableToken contract implementation

This script deploys only the TestStableToken implementation, which can then be used to update the proxy contract to
point to this new implementation.

```bash
forge script test/TestStableToken.sol:TestStableTokenFactory --tc TestStableTokenFactory --rpc-url $RPC_URL --private-key $DEPLOYER_ACCOUNT_PRIVATE_KEY --broadcast
```

### Update the proxy contract to point to the new implementation

```bash
# Upgrade the proxy to a new implementation
cast send $TOKEN_PROXY_ADDRESS "upgradeTo(address)" $NEW_IMPLEMENTATION_ADDRESS --rpc-url $RPC_URL --private-key $DEPLOYER_ACCOUNT_PRIVATE_KEY
```

### Add account to the allowlist to enable minting

```bash
cast send $TOKEN_PROXY_ADDRESS "addMinter(address)" $ACCOUNT_ADDRESS --rpc-url $RPC_URL --private-key $DEPLOYER_ACCOUNT_PRIVATE_KEY
```

### Mint tokens to the account

#### Option 1: Restricted minting (requires minter privileges)

```bash
cast send $TOKEN_PROXY_ADDRESS "mint(address,uint256)" <TO_ADDRESS> <AMOUNT> --rpc-url $RPC_URL --private-key $MINTER_ACCOUNT_PRIVATE_KEY
```

#### Option 2: Public minting by burning ETH (no privileges required)

```bash
cast send $TOKEN_PROXY_ADDRESS "mintWithETH(address,uint256)" <TO_ACCOUNT> <AMOUNT> --value <ETH_AMOUNT> --rpc-url $RPC_URL --private-key $MINTING_ACCOUNT_PRIVATE_KEY --from $MINTING_ACCOUNT_ADDRESS
```

**Note**: The `mintWithETH` function is public and can be called by anyone. It requires sending ETH with the transaction
(using `--value`), which gets burned (sent to address(0)) as an economic cost for minting tokens. This provides a
permissionless way to obtain tokens for testing without requiring minter privileges.

### Approve the token for the waku-rlnv2-contract to use

```bash
cast send $TOKEN_PROXY_ADDRESS "approve(address,uint256)" $TOKEN_SPENDER_ADDRESS <AMOUNT> --rpc-url $RPC_URL --private-key $PRIVATE_KEY
```

### Remove the account from the allowlist to prevent further minting

```bash
cast send $TOKEN_PROXY_ADDRESS "removeMinter(address)" $ACCOUNT_ADDRESS --rpc-url $RPC_URL --private-key $DEPLOYER_ACCOUNT_PRIVATE_KEY
```

### Query token information

```bash
# Check if an account is a minter
cast call $TOKEN_PROXY_ADDRESS "isMinter(address)" $ACCOUNT_ADDRESS --rpc-url $RPC_URL

# Check token balance
cast call $TOKEN_PROXY_ADDRESS "balanceOf(address)" $ACCOUNT_ADDRESS --rpc-url $RPC_URL

# Check token allowance
cast call $TOKEN_PROXY_ADDRESS "allowance(address,address)" $TOKEN_OWNER_ADDRESS $TOKEN_SPENDER_ADDRESS --rpc-url $RPC_URL
```
