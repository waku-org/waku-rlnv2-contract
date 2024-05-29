# This script is used to assert if require env vars are present for deployment
# RPC_URL: RPC URL for the network
# ACCOUNT: Accessed with `cast wallet` command
# ETH_FROM: Address to send transactions from TODO: remove this after bug in foundry is fixed

if [ -z "$RPC_URL" ]; then
  echo "RPC_URL is required"
  exit 1
fi

if [ -z "$ACCOUNT" ]; then
  echo "ACCOUNT is required"
  exit 1
fi

if [ -z "$ETH_FROM" ]; then
  echo "ETH_FROM is required"
  exit 1
fi
