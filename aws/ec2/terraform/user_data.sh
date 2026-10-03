#!/bin/bash
# First-boot provisioning (runs once as root). Log: /var/log/gitops-bootstrap.log
# Installs: Docker, kind, kubectl, helm, kubeseal, make, git. Versions are pinned except Docker (apt repo).
set -euxo pipefail
exec > >(tee -a /var/log/gitops-bootstrap.log) 2>&1

export DEBIAN_FRONTEND=noninteractive
KIND_VERSION=v0.33.0
KUBECTL_VERSION=v1.35.8
HELM_VERSION=v3.17.3
KUBESEAL_VERSION=0.27.2

apt-get update -y
apt-get install -y ca-certificates curl gnupg git make jq unzip python3 python3-yaml

# Kind runs several nodes that each need many inotify watches.
cat > /etc/sysctl.d/99-kind.conf <<SYSCTL
fs.inotify.max_user_watches = 524288
fs.inotify.max_user_instances = 512
SYSCTL
sysctl --system

# Docker Engine from Docker's official apt repository
install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
chmod a+r /etc/apt/keyrings/docker.asc
echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu $(. /etc/os-release && echo "$VERSION_CODENAME") stable" > /etc/apt/sources.list.d/docker.list
apt-get update -y
apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
systemctl enable --now docker
usermod -aG docker ubuntu

curl -fsSLo /usr/local/bin/kind "https://kind.sigs.k8s.io/dl/${KIND_VERSION}/kind-linux-amd64"
curl -fsSLo /usr/local/bin/kubectl "https://dl.k8s.io/release/${KUBECTL_VERSION}/bin/linux/amd64/kubectl"
chmod +x /usr/local/bin/kind /usr/local/bin/kubectl

curl -fsSL https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | DESIRED_VERSION="${HELM_VERSION}" bash

curl -fsSL "https://github.com/bitnami-labs/sealed-secrets/releases/download/v${KUBESEAL_VERSION}/kubeseal-${KUBESEAL_VERSION}-linux-amd64.tar.gz" \
  | tar -xz -C /usr/local/bin kubeseal

touch /var/lib/gitops-bootstrap-done
echo "bootstrap complete"
