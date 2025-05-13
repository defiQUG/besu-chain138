#!/bin/bash

# ========== LOAD ENVIRONMENT FROM .env IF PRESENT ==========
if [ -f .env ]; then
  echo "[*] Loading environment from .env"
  set -a
  source .env
  set +a
fi

# ========== CONFIGURATION ==========
# Ensure script runs from project root (parent of scripts dir)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
EXPECTED_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
PROJECT_ROOT="$(pwd)"
if [ "$PROJECT_ROOT" != "$EXPECTED_ROOT" ]; then
  echo "[!] Error: please run this script from $EXPECTED_ROOT"
  exit 1
fi
echo "[*] Running create_besu_orchestrator.sh in $PROJECT_ROOT"
REPO_NAME="${REPO_NAME:-besu-ibft138-template}"
CHAIN_ID="${CHAIN_ID:-138}"
REPO_DESC="Hyperledger Besu IBFT 2.0 ChainID $CHAIN_ID Scaffold"
AUTHOR=$(git config user.name)
EMAIL=$(git config user.email)

NUM_VALIDATORS="${NUM_VALIDATORS:-4}"
NODE_PREFIX="${NODE_PREFIX:-validator}"

# ========== SETUP FOLDERS ==========
mkdir -p "$PROJECT_ROOT/$REPO_NAME"/{.devcontainer,network}
cd "$PROJECT_ROOT/$REPO_NAME"

# ========== FILE: ibft-config.yaml ==========
cat > "$PROJECT_ROOT/$REPO_NAME/ibft-config.yaml" <<EOF
genesis:
  config:
    chainId: $CHAIN_ID
    ibft2:
      blockperiodseconds: 2
      epochlength: 30000
      requesttimeoutseconds: 10
  nonce: "0x0"
  gasLimit: "0x1fffffffffffff"
  difficulty: "0x1"
  coinbase: "0x0000000000000000000000000000000000000000"
  alloc: {}
  mixHash: "0x63746963616c2d626c6f636b2d68656164657273"
  extraData: ""
EOF

# ========== GENERATE IBFT KEYS AND CONFIG ==========
echo "[*] Generating IBFT keys and blockchain config using Besu operator CLI"
mkdir -p "$PROJECT_ROOT/$REPO_NAME/nodes"
besu operator generate-blockchain-config \
  --config-file="$PROJECT_ROOT/$REPO_NAME/ibft-config.yaml" \
  --to="$PROJECT_ROOT/$REPO_NAME/nodes" \
  --private-key-file-name="key" \
  --validators=$NUM_VALIDATORS

cp "$PROJECT_ROOT/$REPO_NAME/nodes/genesis.json" "$PROJECT_ROOT/$REPO_NAME/genesis.json"
echo "[*] Copied auto-generated genesis.json with extraData field"

# ========== FILE: docker-compose.yml ==========
cat > docker-compose.yml <<EOF
version: '3.4'

services:
EOF

# ========== FILE: docker-compose.override.yml ==========
cat > docker-compose.override.yml <<EOF
version: '3.4'

services:
EOF


# ========== BOOTNODE SETUP ==========
echo "[*] Setting up bootnode"
mkdir -p "$PROJECT_ROOT/$REPO_NAME/nodes/bootnode"
cp "$PROJECT_ROOT/$REPO_NAME/nodes/genesis.json" "$PROJECT_ROOT/$REPO_NAME/nodes/bootnode/genesis.json"
cp "$PROJECT_ROOT/$REPO_NAME/nodes/bootnode.key" "$PROJECT_ROOT/$REPO_NAME/nodes/bootnode/key"

# Append bootnode service to docker-compose.override.yml
cat >> docker-compose.override.yml <<EOB
  bootnode:
    image: hyperledger/besu:latest
    volumes:
      - ./nodes/bootnode:/opt/besu
    ports:
      - "30399:30303"
    command: >
      --data-path=/opt/besu/data
      --genesis-file=/opt/besu/genesis.json
      --node-private-key-file=/opt/besu/key
      --bootnode-enabled=true
      --p2p-port=30303
      --host-whitelist=*
      --network-id=$CHAIN_ID
EOB

# ========== VALIDATOR NODES ==========
for i in $(seq 1 $NUM_VALIDATORS); do
  node_dir="${NODE_PREFIX}${i}"
  port_offset=$((i - 1))
  cat >> docker-compose.override.yml <<EON
  besu-node-$i:
    image: hyperledger/besu:latest
    volumes:
      - ./nodes/$node_dir:/opt/besu
    ports:
      - "$((8545 + port_offset))":8545
      - "$((30303 + port_offset))":30303
    command: >
      --data-path=/opt/besu/data
      --genesis-file=/opt/besu/genesis.json
      --node-private-key-file=/opt/besu/key
      --rpc-http-enabled
      --rpc-http-port=8545
      --host-whitelist=*
      --rpc-http-api=ETH,NET,WEB3,IBFT
      --network-id=$CHAIN_ID
EON
done

# ========== GENERATE static-nodes.json FOR EACH VALIDATOR ==========
BOOTNODE_ENODE="enode://$(besu public-key export --node-key=$PROJECT_ROOT/$REPO_NAME/nodes/bootnode/key --as-enode --ip=bootnode --port=30303)"
echo "[*] Bootnode enode is: $BOOTNODE_ENODE"

for i in $(seq 1 $NUM_VALIDATORS); do
  node_dir="${NODE_PREFIX}${i}"
  mkdir -p "$PROJECT_ROOT/$REPO_NAME/nodes/$node_dir"
  echo "[\"$BOOTNODE_ENODE\"]" > "$PROJECT_ROOT/$REPO_NAME/nodes/$node_dir/static-nodes.json"
done

# ========== FILE: startup.sh ==========
cat > startup.sh <<'EOF'
#!/bin/bash
echo "[*] Starting all validator nodes..."
docker-compose up -d
EOF
chmod +x startup.sh

# ========== FILE: .devcontainer/devcontainer.json ==========
cat > .devcontainer/devcontainer.json <<EOF
{
  "name": "Besu IBFT138",
  "image": "mcr.microsoft.com/devcontainers/java:11",
  "features": {
    "ghcr.io/devcontainers/features/docker-in-docker:2": {}
  },
  "postCreateCommand": "bash startup.sh"
}
EOF

# ========== FILE: .gitignore ==========
cat > .gitignore <<EOF
network/data
*.log
*.tmp
.DS_Store
EOF

# ========== FILE: README.md ==========
cat > README.md <<'EOF'
# 🧱 Hyperledger Besu IBFT 2.0 Template (ChainID 138)

This template configures a private network using IBFT 2.0 on ChainID **138** (DeFi Oracle Meta Mainnet compatible).

## 📦 Includes

- `genesis.json` — IBFT genesis config
- `docker-compose.yml` — base compose file for validators
- `docker-compose.override.yml` — overrides to launch multiple Besu validator nodes and bootnode
- `ibft-config.yaml` — used to auto-generate keys
- `.devcontainer` — GitHub Codespace support
- `startup.sh` — run all nodes easily
- `.env` — configuration for chain and node settings

## 🚀 Quick Start

```bash
chmod +x startup.sh
./startup.sh
```

Then test the RPC for each validator node (ports 8545, 8546, 8547, 8548):

```bash
curl -X POST --data '{"jsonrpc":"2.0","method":"eth_chainId","params":[],"id":1}' localhost:8545
curl -X POST --data '{"jsonrpc":"2.0","method":"eth_chainId","params":[],"id":1}' localhost:8546
curl -X POST --data '{"jsonrpc":"2.0","method":"eth_chainId","params":[],"id":1}' localhost:8547
curl -X POST --data '{"jsonrpc":"2.0","method":"eth_chainId","params":[],"id":1}' localhost:8548
```

Expected output for each: `0x8a` (138 in hex)

---

## ⚙️ Environment Configuration (`.env`)

This project uses a `.env` file to configure network parameters. Example:

```env
REPO_NAME=besu-ibft138-template
CHAIN_ID=138
NUM_VALIDATORS=4
NODE_PREFIX=validator
```

You can edit `.env` to customize the repo name, chain ID, number of validators, or validator node prefix.

---

## 🌐 Bootnode Setup

A dedicated bootnode is set up to facilitate peer discovery. Its private key and genesis are placed in `nodes/bootnode/`. The bootnode is defined in `docker-compose.override.yml` and exposed on port `30399`.

Each validator node is configured to connect to the bootnode using a generated `static-nodes.json` containing the bootnode's ENODE address.

---

## 🧠 What This Script Covers

| File                  | Purpose                                                        |
|-----------------------|----------------------------------------------------------------|
| `genesis.json`        | Genesis configuration for IBFT2.0 and ChainID 138              |
| `ibft-config.yaml`    | Optional tool config to auto-gen the blockchain config         |
| `docker-compose.yml`  | Base compose file for Besu nodes                               |
| `docker-compose.override.yml` | Overrides to run multiple validator nodes and bootnode |
| `startup.sh`          | Starts all nodes with setup and volume mounts                  |
| `.devcontainer/`      | Enables Codespaces with Docker + Java support                  |
| `.gitignore`          | Prevents junk from being tracked                               |
| `.env`                | Environment variables for customizing setup                    |
| `README.md`           | Quick usage and overview instructions                          |

EOF
# ========== INIT GIT ==========

echo "[*] Initializing git repository"
git init
git add .
git commit -m "Initial commit for Hyperledger Besu IBFT 2.0 ChainID 138 Scaffold"

 # ========== CREATE GITHUB REPO ==========
if command -v gh &>/dev/null; then
  echo "[*] Creating GitHub repository..."
  gh repo create "$REPO_NAME" --public --description "$REPO_DESC" --source=. --remote=origin --push --template
else
  echo "[!] GitHub CLI (gh) not found. Please push manually:"
  echo "git remote add origin git@github.com:your-org/$REPO_NAME.git"
  echo "git push -u origin main"
fi

echo "[✓] Besu IBFT138 template created successfully in $REPO_NAME/"

---

## 🧠 What This Script Covers

| File                  | Purpose                                                        |
|-----------------------|----------------------------------------------------------------|
| `genesis.json`        | Genesis configuration for IBFT2.0 and ChainID 138              |
| `ibft-config.yaml`    | Optional tool config to auto-gen the blockchain config         |
| `docker-compose.yml`  | Base compose file for Besu nodes                               |
| `docker-compose.override.yml` | Overrides to run multiple validator nodes              |
| `startup.sh`          | Starts all nodes with setup and volume mounts                  |
| `.devcontainer/`      | Enables Codespaces with Docker + Java support                  |
| `.gitignore`          | Prevents junk from being tracked                               |
| `README.md`           | Quick usage and overview instructions                          |


# ========== FILE: .env ==========
cat > .env <<EOF
REPO_NAME=besu-ibft138-template
CHAIN_ID=138
NUM_VALIDATORS=4
NODE_PREFIX=validator
EOF