

#!/bin/bash

echo "[*] Initializing Hyperledger Besu Chain 138 Repository Structure..."

# Create high-level directories
mkdir -p arm-templates docker/besu/config docker/nginx/certs prometheus scripts terraform

# Create base files
touch .env README.md

# Move existing template project
if [ -d "besu-ibft138-template" ]; then
  mv besu-ibft138-template/docker-compose.yml docker/besu/docker-compose.yml
  mv besu-ibft138-template/genesis.json docker/besu/config/genesis.json
  mv besu-ibft138-template/ibft-config.yaml docker/besu/config/ibft-config.yaml
  mv besu-ibft138-template/startup.sh scripts/startup.sh
  mv besu-ibft138-template/README.md README.md
  rm -rf besu-ibft138-template
fi

# Create placeholder configs
cat > docker/nginx/nginx.conf <<EOF
server {
  listen 443 ssl;
  server_name your.domain.com;

  ssl_certificate     /etc/nginx/certs/fullchain.pem;
  ssl_certificate_key /etc/nginx/certs/privkey.pem;

  location / {
    proxy_pass http://besu:8545;
    proxy_http_version 1.1;
    proxy_set_header Host \$host;
    proxy_set_header X-Real-IP \$remote_addr;
    proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
  }
}
EOF

cat > prometheus/prometheus.yml <<EOF
global:
  scrape_interval: 15s

scrape_configs:
  - job_name: 'besu'
    static_configs:
      - targets: ['localhost:9545']
EOF

cat > .env <<EOF
REPO_NAME=besu-chain138
CHAIN_ID=138
NUM_VALIDATORS=4
NODE_PREFIX=validator
EOF

echo "[✓] Project structure initialized."

# === Additional Directory Scaffolding for Azure-Oriented Besu Project ===

echo "[*] Creating extended Azure orchestration scaffolding..."

# Infrastructure as Code templates
mkdir -p arm-templates/{networking,monitoring}
touch arm-templates/{bootnode-vm.json,networking/networking.json,monitoring/monitoring.json,dcr-rule.json}

# Docker-related scaffolding
touch docker/besu/{healthcheck.sh,besu.env,static-nodes.json}
touch docker/nginx/nginx-compose.override.yml

# Prometheus/Grafana extensions
mkdir -p prometheus/grafana
touch prometheus/{alerts.yml,rules.yml}
touch prometheus/grafana/{besu-dashboard.json}

# Terraform IaC files
touch terraform/{main.tf,variables.tf,outputs.tf,backend.tf}

# Additional scripts
touch scripts/{generate_static_nodes.sh,init_besu_network.sh,deploy_to_azure.sh,setup_ssl_certbot.sh}

# Tests
mkdir -p tests
touch tests/{test_rpc.sh,test_metrics.sh,validate_enodes.sh}

# GitHub Actions workflows
mkdir -p .github/workflows
touch .github/workflows/{build.yml,terraform.yml,azure-deploy.yml}

# Vault and secrets management
mkdir -p vault secrets
touch secrets/keyvault-policy.json
touch .env.production

# Docs
mkdir -p docs
touch docs/{architecture.md,onboarding.md,faq.md,infra-diagram.png}

# Ignore sensitive files
cat > .gitignore <<EOF
.env
.env.production
docker/nginx/certs
secrets/
vault/
*.log
*.tmp
EOF

# Optional Makefile for automation
cat > Makefile <<EOF
up:
	docker-compose -f docker/besu/docker-compose.yml up -d

down:
	docker-compose -f docker/besu/docker-compose.yml down

logs:
	docker-compose -f docker/besu/docker-compose.yml logs -f

deploy:
	bash scripts/deploy_to_azure.sh
EOF

echo "[✓] Extended Azure project structure initialized."