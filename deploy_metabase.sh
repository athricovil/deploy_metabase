#!/usr/bin/env bash
set -euo pipefail

echo "=== Updating system ==="
sudo dnf update -y

echo "=== Installing Podman ==="
sudo dnf install -y podman

echo "=== Creating Metabase directories ==="
# Persistent volume for Metabase application DB (H2) or external DB configs
sudo mkdir -p /opt/metabase-data
sudo chown ec2-user:ec2-user /opt/metabase-data

echo "=== Pulling latest Metabase image ==="
podman pull docker.io/metabase/metabase:latest

echo "=== Stopping existing Metabase container if exists ==="
podman stop metabase 2>/dev/null || true
podman rm metabase 2>/dev/null || true

echo "=== Running Metabase container ==="
podman run -d \
  --name metabase \
  -p 3000:3000 \
  -v /opt/metabase-data:/metabase-data \
  -e MB_DB_FILE=/metabase-data/metabase.db \
  docker.io/metabase/metabase:latest

echo "=== Waiting for container startup ==="
sleep 5
podman logs --tail=50 metabase

echo "=== Metabase deployment complete! ==="
echo "Access Metabase at: http://<your-ec2-public-ip>:3000"
