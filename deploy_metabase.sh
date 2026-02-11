#!/usr/bin/env bash
set -euo pipefail

echo "=== Updating system ==="
sudo dnf update -y

echo "=== Installing build dependencies ==="
sudo dnf install -y \
    git golang autoconf automake libtool meson ninja-build \
    libseccomp-devel gpgme-devel libcap-devel systemd-devel \
    yajl yajl-devel cni-plugins iptables-nft rpm-build \
    golang-github-cpuguy83-md2man.x86_64 pkgconf-pkg-config gcc make

WORKDIR="${HOME}/work"
mkdir -p "$WORKDIR"
cd "$WORKDIR"

echo "=== Building Podman ==="
git clone https://github.com/containers/podman.git
cd podman
git switch v5.7
make
sudo make install
cd ..

echo "=== Building Conmon ==="
git clone https://github.com/containers/conmon.git
cd conmon
make -j"$(nproc)"
sudo make install
cd ..

echo "=== Building crun (OCI runtime) ==="
git clone https://github.com/containers/crun.git
cd crun
./autogen.sh
./configure --prefix=/usr/local
make -j"$(nproc)"
sudo make install
cd ..

echo "=== Building libslirp ==="
git clone https://gitlab.freedesktop.org/slirp/libslirp.git
cd libslirp
git switch stable-4.2
meson build
ninja -C build
sudo ninja -C build install
cd ..

echo "=== Building slirp4netns ==="
git clone https://github.com/rootless-containers/slirp4netns.git
cd slirp4netns
git switch release/0.4
./autogen.sh
./configure --prefix=/usr/local
make -j"$(nproc)"
sudo make install
cd ..

echo "=== Installing containers-common ==="
mkdir -p "${WORKDIR}/Downloads"
cd "${WORKDIR}/Downloads"

curl -LO https://download.fedoraproject.org/pub/fedora/linux/updates/41/Everything/source/tree/Packages/c/containers-common-0.64.2-1.fc41.src.rpm

rpm -ivh containers-common-0.64.2-1.fc41.src.rpm
cd $HOME/rpmbuild
rpmbuild -bb SPECS/containers-common.spec
sudo dnf install -y RPMS/noarch/containers-common-*.rpm

echo "=== Podman build complete ==="
podman --version

echo "=== Setting up Metabase ==="
sudo mkdir -p /opt/metabase-data
sudo chown $USER:$USER /opt/metabase-data

echo "=== Pulling Metabase image ==="
podman pull docker.io/metabase/metabase:latest

echo "=== Running Metabase container ==="
podman run -d \
  --name metabase \
  -p 3000:3000 \
  -v /opt/metabase-data:/metabase-data \
  -e MB_DB_FILE=/metabase-data/metabase.db \
  docker.io/metabase/metabase:latest

echo "=== Metabase deployment complete! ==="
echo "Access Metabase at: http://<your-ec2-public-ip>:3000"
