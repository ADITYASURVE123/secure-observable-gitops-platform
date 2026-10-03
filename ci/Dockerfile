# Jenkins controller: pinned LTS + the CLI tools the pipeline needs.
# Deliberately NOT included: kubectl/helm/cluster credentials. Jenkins can only change Git,
# never the cluster, which is what makes the delivery GitOps (ArgoCD does the deploying).
FROM jenkins/jenkins:2.541.3-lts-jdk21

USER root

# Docker CLI + buildx only (the daemon is the separate dind container in docker-compose.yml).
COPY --from=docker:27.4.1-cli /usr/local/bin/docker /usr/local/bin/docker
COPY --from=docker:27.4.1-cli /usr/local/libexec/docker/cli-plugins /usr/local/libexec/docker/cli-plugins

ARG TRIVY_VERSION=0.58.1
ARG KUSTOMIZE_VERSION=5.5.0

# Both binaries are checksum-verified against the checksum file published with the release.
RUN set -eux; \
    arch="$(dpkg --print-architecture)"; \
    case "$arch" in amd64) trivy_arch=64bit ;; arm64) trivy_arch=ARM64 ;; *) echo "unsupported arch $arch"; exit 1 ;; esac; \
    cd /tmp; \
    t="trivy_${TRIVY_VERSION}_Linux-${trivy_arch}.tar.gz"; \
    base="https://github.com/aquasecurity/trivy/releases/download/v${TRIVY_VERSION}"; \
    curl -fsSLO "${base}/${t}"; curl -fsSLO "${base}/trivy_${TRIVY_VERSION}_checksums.txt"; \
    grep " ${t}\$" "trivy_${TRIVY_VERSION}_checksums.txt" | sha256sum -c -; \
    tar -xzf "$t" -C /usr/local/bin trivy; \
    k="kustomize_v${KUSTOMIZE_VERSION}_linux_${arch}.tar.gz"; \
    kbase="https://github.com/kubernetes-sigs/kustomize/releases/download/kustomize%2Fv${KUSTOMIZE_VERSION}"; \
    curl -fsSLO "${kbase}/${k}"; curl -fsSLO "${kbase}/checksums.txt"; \
    grep " ${k}\$" checksums.txt | sha256sum -c -; \
    tar -xzf "$k" -C /usr/local/bin kustomize; \
    rm -rf /tmp/*; \
    trivy --version; kustomize version

USER jenkins
# Persisted on the jenkins_home volume so the vulnerability DB is not re-downloaded each build.
ENV TRIVY_CACHE_DIR=/var/jenkins_home/.cache/trivy TRIVY_NO_PROGRESS=true

# Prefer the lock file (exact versions) when present; otherwise resolve from plugins.txt.
# The glob keeps the COPY valid when no lock file exists yet.
COPY --chown=jenkins:jenkins plugins.txt plugins.lock.tx[t] /usr/share/jenkins/ref/
RUN if [ -f /usr/share/jenkins/ref/plugins.lock.txt ]; then \
      jenkins-plugin-cli --plugin-file /usr/share/jenkins/ref/plugins.lock.txt; \
    else \
      jenkins-plugin-cli --plugin-file /usr/share/jenkins/ref/plugins.txt; \
    fi
