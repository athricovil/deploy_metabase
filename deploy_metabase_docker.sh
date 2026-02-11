#!/usr/bin/env bash
set -euo pipefail

# --- Configurable variables ---
MB_HTTP_PORT="${MB_HTTP_PORT:-3000}"         # Host port for Metabase UI
MB_CONTAINER_NAME="${MB_CONTAINER_NAME:-metabase}"
MB_DATA_DIR="${MB_DATA_DIR:-/opt/metabase-data}"   # Persistent storage path on host
MB_DOCKER_IMAGE="${MB_DOCKER_IMAGE:-metabase/metabase:latest}"  # Metabase OSS image
USE_SYSTEMD="${USE_SYSTEMD:-true}"           # Set to "false" to skip systemd service creation

echo "=== [1/8] Update system packages (recommended on AL2023) ==="
sudo dnf update -y  # Keep AL2023 repos current; see AL2023 guidance on managing updates
# (You can pin --releasever if you manage repo versions explicitly.)  # see AWS docs
# https://docs.aws.amazon.com/linux/al2023/ug/managing-repos-os-updates.html

echo "=== [2/8] Install Docker Engine from AL2023 repos ==="
# AL2023 provides docker via dnf
sudo dnf install -y docker
# References:
# - LinuxShout: 'sudo dnf install docker' on AL2023  [1](https://linux.how2shout.com/how-to-install-docker-on-amazon-linux-2023/)
# - LinuxVox: 'sudo dnf install docker -y' on AL2023  [2](https://linuxvox.com/blog/install-docker-on-amazon-linux-2023/)

echo "=== [3/8] Enable and start Docker service ==="
sudo systemctl enable --now docker
sudo systemctl --no-pager --full status docker || true

echo "=== [4/8] Add ec2-user to 'docker' group (no sudo for docker) ==="
if id -nG ec2-user | grep -qw docker; then
  echo "ec2-user already in docker group."
else
  sudo usermod -aG docker ec2-user
  echo "Added ec2-user to docker group. You must log out/in for this to take effect."
fi

echo "=== [5/8] Prepare persistent data directory ==="
sudo mkdir -p "${MB_DATA_DIR}"
sudo chown ec2-user:ec2-user "${MB_DATA_DIR}"
sudo chmod 700 "${MB_DATA_DIR}"

echo "=== [6/8] Pull official Metabase image ==="
sudo docker pull "${MB_DOCKER_IMAGE}"   # Official image and run usage documented by Metabase  [3](https://www.metabase.com/docs/latest/installation-and-operation/running-metabase-on-docker)

echo "=== [7/8] Remove any existing container with the same name ==="
sudo docker rm -f "${MB_CONTAINER_NAME}" 2>/dev/null || true

echo "=== [8/8] Run Metabase container (detached) ==="
# Persist the app DB on host. For production, prefer external Postgres (env vars below).
sudo docker run -d --name "${MB_CONTAINER_NAME}" \
  -p "${MB_HTTP_PORT}:3000" \
  -v "${MB_DATA_DIR}:/metabase-data" \
  -e MB_DB_FILE=/metabase-data/metabase.db \
  --restart unless-stopped \
  "${MB_DOCKER_IMAGE}"

echo "Container started. Tailing the last 50 logs:"
sudo docker logs --tail=50 "${MB_CONTAINER_NAME}" || true

# --- Optional: create a systemd unit that depends on docker.service and restarts the container on boot ---
if [[ "${USE_SYSTEMD}" == "true" ]]; then
  echo "=== Creating systemd unit for ${MB_CONTAINER_NAME} ==="
  SERVICE_PATH="/etc/systemd/system/${MB_CONTAINER_NAME}.service"
  sudo bash -c "cat > '${SERVICE_PATH}'" <<EOF
[Unit]
Description=Metabase container
Requires=docker.service
After=docker.service

[Service]
Restart=always
ExecStart=/usr/bin/docker start -a ${MB_CONTAINER_NAME}
ExecStop=/usr/bin/docker stop -t 10 ${MB_CONTAINER_NAME}

[Install]
WantedBy=multi-user.target
EOF
  sudo systemctl daemon-reload
  sudo systemctl enable --now "${MB_CONTAINER_NAME}.service"
fi

echo "=== Metabase deployment complete! ==="
IP=$(curl -s http://169.254.169.254/latest/meta-data/public-ipv4 || echo "<your-ec2-public-ip>")
echo "Open: http://${IP}:${MB_HTTP_PORT}"

cat <<'NOTE'

Notes:
- Initial admin setup will start at the above URL.
- Data is persisted under /metabase-data inside the container and ${MB_DATA_DIR} on the host.
- Official Metabase Docker usage (ports, image) is documented here:
  https://www.metabase.com/docs/latest/installation-and-operation/running-metabase-on-docker  (docs)  [citation above]
- For production, use an external Postgres/MySQL/etc. instead of embedded H2 (see below).

Production DB (recommended):
  Add these environment variables to the 'docker run' above, and remove MB_DB_FILE:
    -e MB_DB_TYPE=postgres \
    -e MB_DB_DBNAME=metabase_appdb \
    -e MB_DB_PORT=5432 \
    -e MB_DB_USER=metabase_user \
    -e MB_DB_PASS=strongpassword \
    -e MB_DB_HOST=<postgres-hostname or IP>

Upgrade:
  sudo docker pull metabase/metabase:latest
  sudo docker stop ${MB_CONTAINER_NAME} && sudo docker rm ${MB_CONTAINER_NAME}
  (re-run the same docker run ... line)

Logs:
  sudo docker logs -f ${MB_CONTAINER_NAME}

Stop/Start:
  sudo systemctl stop ${MB_CONTAINER_NAME}   # if systemd service created
  sudo systemctl start ${MB_CONTAINER_NAME}

Firewall:
  Ensure inbound TCP ${MB_HTTP_PORT} is allowed in the EC2 Security Group.
NOTE
