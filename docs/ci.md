# CI with Jenkins (Phase 2)

Jenkins runs in Docker, is configured entirely by JCasC (`ci/jenkins.yaml`), and uses a separate
docker-in-docker daemon so it never touches the host's Docker socket.

```
git push --> Jenkins (poll/webhook) --> test --> build --> Trivy gate --> push image --> commit new tag to Git
                                                                                         (k8s/overlays/staging, "[skip ci]")
```

## One-time setup

1. **Create the GitHub repo** `ADITYASURVE123/secure-observable-gitops-platform` and push this project to `main`.
   If you use a different repo name, change `GIT_REPO_URL` in `ci/.env`.
2. **Create two tokens** (never commit them):
   - Registry token (GHCR): GitHub > Settings > Developer settings > Tokens (classic) > scope `write:packages`.
     Docker Hub instead: Account settings > Security > New access token (Read & Write), and set
     `REGISTRY=docker.io`, `REGISTRY_NAMESPACE=adityasurve`, `REGISTRY_USER=adityasurve` in `ci/.env`.
   - Git token: fine-grained PAT limited to this repo, permission **Contents: Read and write**.
3. `make jenkins-up` creates `ci/.env` and stops asking for the two tokens. Paste them into `ci/.env`, run again.
4. (Recommended) `make jenkins-lock`, then commit `ci/plugins.lock.txt`. This pins every plugin and dependency.
   Jenkins and tool versions (LTS image, Trivy, kustomize, Docker CLI) are already pinned in `ci/Dockerfile`.

## Run it

Open http://localhost:8081, log in as `admin` (password in `ci/.env`), open job **orders-platform**, click **Build Now**.
After that, any push to `main` is picked up within ~3 minutes (SCM polling).

For instant builds, expose Jenkins (for example with `smee.io` or `ngrok`) and add a GitHub webhook to
`<url>/github-webhook/` (content type `application/json`, event: push).

## After the first successful build

- GHCR packages are private by default. Make `orders-api` and `orders-frontend` **public**
  (GitHub > Packages > Package settings) so the Kind cluster can pull them without an imagePullSecret.
- Check that a commit like `chore(release): deploy b1-ab12cd34 to staging [skip ci]` appeared on `main`.
  It changed only `k8s/overlays/staging/kustomization.yaml`.

## Design notes

- **No loops.** The release commit contains `[skip ci]`; the `scmSkip` step in the Checkout stage aborts
  and deletes any build triggered by it. `disableConcurrentBuilds()` prevents racing pushes.
- **No direct deploys.** The Jenkins image has no kubectl/helm and no kubeconfig. It can only write Git.
- **Security gate.** Trivy fails the build on fixable HIGH/CRITICAL findings. JSON reports, CycloneDX
  SBOMs, the unit-test log and image digests are archived on every build (the build page's "Build Artifacts").
- **Secrets.** Registry and Git tokens live only in `ci/.env` (git-ignored) and reach Jenkins as environment
  variables that JCasC turns into credentials. They are used through `withCredentials` and never echoed.
- **Trade-off.** Builds run on the controller (2 executors) to keep the demo small. Production would use
  ephemeral agents and `numExecutors: 0`.

## Troubleshooting

| Symptom | Likely cause / fix |
|---|---|
| `make jenkins-up`: "REGISTRY_TOKEN is empty" | Fill the tokens in `ci/.env` |
| Plugin install fails during image build | Run `make jenkins-lock` again or delete `ci/plugins.lock.txt` to re-resolve |
| Trivy stage fails | Open `reports/trivy-*.json`; bump the dependency/base image, or add a justified entry to `.trivyignore` |
| Push stage: `denied` | Token lacks `write:packages`, or `REGISTRY_NAMESPACE` is not lowercase |
| Update Manifests: `403` | Git token needs Contents read+write on this repo; branch protection must allow the push |
