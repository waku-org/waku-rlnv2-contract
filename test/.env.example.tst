# Example environment variables for TestStableToken commands in test/README.md
# Either provide a private key (`DEPLOYER_ACCOUNT_PRIVATE_KEY`) or a mnemonic (`TWELVE_WORD_MNEMONIC`).

# Deployer account (used as --from / ETH_FROM)
DEPLOYER_ACCOUNT_ADDRESS=0xaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
# Hex private key (prefixed with 0x) OR leave empty if you prefer to use mnemonic
DEPLOYER_ACCOUNT_PRIVATE_KEY=0xaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa

# Alternatively, use a mnemonic instead of a private key
TWELVE_WORD_MNEMONIC="test test test test test test test test test test test junk"

# RPC URL for accessing testnet via HTTP.
# e.g. https://linea-sepolia.infura.io/v3/123aa110320f4aec179150fba1e1b1b1
RPC_URL=https://linea-sepolia.infura.io/v3/<key>

# Optional: override the default max supply (value is in wei; example below = 1_000_000 * 10**18)
# Uncomment and set to change the token cap used during initialize/upgrade
# MAX_SUPPLY=1000000000000000000000000

# Addresses used by various actions (leave commented if not applicable)
# Proxy contract (when calling upgrade, approve, mint, etc.)
# TOKEN_PROXY_ADDRESS=0xbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb

# Example account to add to the minter allowlist
# ACCOUNT_ADDRESS=0xcccccccccccccccccccccccccccccccccccccccc

# Private key for a minter account (used when sending mint transactions)
# MINTER_ACCOUNT_PRIVATE_KEY=0xcccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc