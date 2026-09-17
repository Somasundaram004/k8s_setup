# Kubernetes and UniKube setup

This repository provides repeatable Bash scripts for an Ubuntu kubeadm cluster. It installs containerd, Kubernetes, a Calico network, and UniKube, then upgrades nodes with drain/uncordon protection.

It also includes a principal platform agent with Kubernetes, CI/CD, and reliability specialists. The agent produces auditable plans and stores bounded run memory locally; it does not silently modify infrastructure or rewrite its own code.

The current platform architecture and control/data flows are documented in [docs/architecture.md](docs/architecture.md). Every feature update must update this README and that architecture diagram.

The repository also includes a macOS operator path. macOS is not used as a production kubeadm node; it connects to Ubuntu nodes over SSH.

Every setup script supports `--dry-run`. It prints the components and operations that would be affected without requiring root, opening SSH, installing packages, draining nodes, or changing Kubernetes:

```bash
./scripts/bootstrap.sh --dry-run control-plane
./scripts/upgrade.sh control-plane --dry-run
./scripts/install-unikube.sh --dry-run
./scripts/health-check.sh --dry-run
./scripts/download-templates.sh --dry-run
./scripts/install-platform-kit.sh --dry-run
./scripts/build-image.sh --dry-run ghcr.io/OWNER/REPOSITORY:dev
./scripts/macos/setup-all.sh --dry-run
./scripts/deploy-nginx.sh --dry-run
```

## Zero-downtime requirement

Zero downtime is a topology property, not just a script feature. Use three control-plane nodes behind a TCP load balancer and at least two worker nodes. Applications must have multiple replicas, a PodDisruptionBudget, and readiness probes. A single server or a single worker cannot be upgraded without a service interruption; the scripts reject that case unless `ALLOW_DOWNTIME=true`.

## Prerequisites

For a production cluster, use Ubuntu 22.04 or 24.04 nodes with DNS, a load balancer for `CONTROL_PLANE_ENDPOINT`, SSH key access, and open Kubernetes network ports. Use three control planes and at least two workers for no-downtime maintenance.

For the macOS operator, install Homebrew, Bash, OpenSSH, Docker Desktop, and Helm:

```bash
brew install bash openssh helm
brew install --cask docker
docker version
helm version
ssh -V
```

Docker Desktop is used to build and test application images locally. Kubernetes itself runs on the Ubuntu servers through kubeadm; Docker Desktop is not the production cluster runtime.

## Agent runner

Run the principal agent locally without third-party Python dependencies:

```bash
./scripts/run-agent.sh "Review the Kubernetes upgrade and monitoring risks"
```

The output contains the principal plan plus specialist reports from Kubernetes, CI/CD, and reliability agents. Set `AI_API_KEY` for an OpenAI-compatible backend; without it, the runner remains offline and returns conservative review guidance. Optional `AI_BASE_URL` and `AI_MODEL` support compatible providers.

GitHub Actions runs the same agent weekly and on manual dispatch using [agent-runner.yml](.github/workflows/agent-runner.yml). Add `AI_API_KEY` as a repository secret and optional `AI_BASE_URL`/`AI_MODEL` repository variables. Reports are uploaded as workflow artifacts. The workflow has `contents: read` permission and does not deploy or mutate the cluster.

## Complete installation

The following sequence installs all components: local templates, Kubernetes/containerd, Calico, UniKube, Helm, Argo CD, Prometheus, Grafana, Alertmanager, Metrics Server, kube-state-metrics, and node-exporter.

### Mac-driven setup

1. Create the configuration and set the server inventory:

   ```bash
   cp .env.example cluster.env
   chmod +x scripts/*.sh scripts/macos/*.sh
   ```

   Edit `cluster.env` and set `REMOTE_USER`, `CONTROL_PLANE_HOSTS`, `WORKER_HOSTS`, `CONTROL_PLANE_ENDPOINT`, and pinned versions.
2. Preview the complete operation:

   ```bash
   ./scripts/macos/setup-all.sh --dry-run
   ```

3. Bring up the complete cluster:

   ```bash
   ./scripts/macos/setup-all.sh
   ```

   The runner automatically downloads the local CNI template, stages every repository template, installs node prerequisites, bootstraps and joins all nodes, installs Helm, deploys the platform kit, and runs health checks.

### Manual Ubuntu setup

1. Use Ubuntu 22.04 or 24.04 on every node. Provide a stable DNS name or load-balancer address for `CONTROL_PLANE_ENDPOINT`.
2. Copy `.env.example` to `cluster.env`, pin the Kubernetes and UniKube versions, and set the endpoint and CNI version.
3. Download the pinned CNI manifest into the repository and review it before use:

   ```bash
   sudo ./scripts/download-templates.sh
   ```

   Bootstrap reads only the local `templates/calico.yaml`; it does not fetch a live manifest.
4. On each node, make the scripts executable once: `chmod +x scripts/*.sh`.
5. On the first control plane, run:

   ```bash
   sudo ./scripts/bootstrap.sh control-plane
   ```

6. Copy the worker join command from `/root/worker-join-command.txt` to each worker and run:

   ```bash
   sudo JOIN_COMMAND='paste-the-command-here' ./scripts/bootstrap.sh worker
   ```

   Generate a separate control-plane join command with `kubeadm token create --print-join-command`, adding `--control-plane --certificate-key <key>` from `/root/control-plane-certificate-key.txt`.
7. Install UniKube on the node where its CLI is needed:

   ```bash
   sudo ./scripts/install-unikube.sh
   ```

   The script installs the official `unikube` Python package from PyPI. Pin `UNIKUBE_VERSION` in production.
8. Verify the cluster:

   ```bash
   sudo ./scripts/health-check.sh
   ```

## Docker image setup

Docker image build is part of the CI/CD flow. Copy the sample Dockerfile and site into an application repository, or use them directly from this repository:

```bash
mkdir -p ./image-build/site
cp templates/ci/Dockerfile ./image-build/Dockerfile
cp templates/ci/site/index.html ./image-build/site/index.html
./scripts/build-image.sh example/k8s-app:dev ./image-build
docker run --rm --name k8s-app -p 8080:80 example/k8s-app:dev
```

Open `http://localhost:8080` to verify the image. Stop it with `Ctrl+C` or use `docker stop k8s-app` from another terminal. To publish an image, authenticate to the registry and run:

```bash
docker login ghcr.io
docker tag example/k8s-app:dev ghcr.io/OWNER/REPOSITORY:dev
docker push ghcr.io/OWNER/REPOSITORY:dev
```

The GitHub Actions template builds and publishes the image automatically on pushes to `main`; replace `OWNER/REPOSITORY` and the sample test command before committing it to an application repository.

## Platform kit

Install the local Helm values for Argo CD and the monitoring stack after the cluster is healthy:

```bash
./scripts/install-platform-kit.sh
```

This installs Argo CD, Prometheus, Alertmanager, Grafana, Metrics Server, kube-state-metrics, and node-exporter. Prometheus/Grafana provide historical application and infrastructure monitoring; Metrics Server provides current resource metrics for `kubectl top`, HPA, and VPA. It is safe to rerun for chart upgrades after reviewing and pinning `ARGOCD_CHART_VERSION`, `MONITORING_CHART_VERSION`, and `METRICS_SERVER_CHART_VERSION` in `cluster.env`. Argo CD and Grafana use `ClusterIP` services by default; expose them through your approved ingress or use port-forwarding during initial setup.

The CI half is intentionally application-specific. Copy [templates/ci/github-actions-ci.yml](templates/ci/github-actions-ci.yml) into an application repository, replace the test command and image name, then configure Argo CD to deploy the image tag or GitOps manifest produced by that pipeline.

For a working sample image, copy [templates/ci/Dockerfile](templates/ci/Dockerfile) and its `site/` directory into the application repository. Replace the sample site with the application, then build locally:

```bash
./scripts/build-image.sh ghcr.io/OWNER/REPOSITORY:dev
docker run --rm -p 8080:80 ghcr.io/OWNER/REPOSITORY:dev
```

The GitHub Actions workflow builds and publishes the same Dockerfile on pushes to `main`. Replace the sample Dockerfile for non-static applications while keeping the health check and non-root runtime requirements appropriate for that application.

## macOS operator

Install Homebrew on the Mac, copy `.env.example` to `cluster.env`, and set `REMOTE_USER` to the SSH user for the Ubuntu nodes. Then install UniKube locally:

```bash
UNIKUBE_VERSION=latest ./scripts/macos/install-unikube.sh
```

Use the remote wrapper from the Mac. It copies the configuration and scripts to the target node, then runs the Linux implementation with `sudo`:

```bash
REMOTE_USER=ubuntu ./scripts/macos/remote.sh bootstrap control-plane 10.0.0.10
JOIN_COMMAND='paste-the-command-here' REMOTE_USER=ubuntu ./scripts/macos/remote.sh bootstrap worker 10.0.0.20
REMOTE_USER=ubuntu ./scripts/macos/remote.sh health control-plane 10.0.0.10
REMOTE_USER=ubuntu ./scripts/macos/remote.sh platform cluster 10.0.0.10
```

Preview a remote operation without connecting to the server:

```bash
REMOTE_USER=ubuntu ./scripts/macos/remote.sh --dry-run upgrade worker 10.0.0.20
REMOTE_USER=ubuntu ./scripts/macos/remote.sh --dry-run platform cluster 10.0.0.10
```

For worker upgrades, provide a local admin kubeconfig temporarily so the wrapper can drain and uncordon the worker:

```bash
ADMIN_KUBECONFIG="$HOME/.kube/config" REMOTE_USER=ubuntu ./scripts/macos/remote.sh upgrade worker 10.0.0.20
```

Run upgrades one node at a time, control planes first. The wrapper requires standard `ssh` and `scp`; configure SSH keys rather than passwords for repeatable operation.

For a complete Mac-driven deployment, set `CONTROL_PLANE_HOSTS`, `WORKER_HOSTS`, and `REMOTE_USER` in `cluster.env`, then run:

```bash
./scripts/macos/setup-all.sh --dry-run
./scripts/macos/setup-all.sh
```

The runner stages all local templates, bootstraps the first control plane, automatically creates and uses kubeadm join commands for the remaining control planes and workers, installs Helm on the first control plane, installs the platform kit, and runs the health check. Use three control planes and at least two workers for the no-downtime topology described above.

## Self-service Nginx deployment

The repository includes an HA Nginx application under [templates/apps/nginx](templates/apps/nginx). It uses three replicas, readiness and liveness probes, `maxUnavailable: 0`, topology spreading, and a PodDisruptionBudget requiring two available pods. Deploy or upgrade it locally with:

```bash
./scripts/deploy-nginx.sh --dry-run
./scripts/deploy-nginx.sh image=ghcr.io/OWNER/REPOSITORY:TAG
kubectl -n nginx-app port-forward service/nginx 8080:80
```

GitHub users can run [self-service-nginx.yml](.github/workflows/self-service-nginx.yml) from the Actions tab, select an image, and deploy without shell access. Add a base64-encoded admin kubeconfig as the protected `KUBECONFIG_B64` production environment secret. The workflow waits for the rolling deployment to become available before completing.

## Separate Git repositories

The optional exporter creates and pushes three focused repositories with GitHub CLI: infrastructure (`k8s-infra`), platform services (`k8s-platform`), and the Nginx application (`nginx-app`). It never overwrites an existing repository without GitHub CLI reporting the conflict:

```bash
brew install gh
gh auth login
./scripts/export-and-push-repos.sh Somasundaram004
```

Override names or visibility when needed:

```bash
PRIVATE_REPOS=false INFRA_REPO_NAME=cluster-infra PLATFORM_REPO_NAME=platform-tools APP_REPO_NAME=web-nginx ./scripts/export-and-push-repos.sh Somasundaram004
```

After splitting, use [self-service-platform.yml](.github/workflows/self-service-platform.yml) for one-click Argo CD, Prometheus, Grafana, Alertmanager, Metrics Server, and exporter installation, then use `self-service-nginx.yml` for the application. Configure the protected `KUBECONFIG_B64` secret in each deployment repository.

For one repository per independent tool, use the focused exporter:

```bash
./scripts/export-tool-repos.sh Somasundaram004
```

It creates and pushes `k8s-argocd`, `k8s-observability`, `k8s-metrics-server`, `k8s-unikube`, `k8s-ai-agent`, and `k8s-ci-cd`. Existing infrastructure, platform, and application repositories remain available separately.

## Kubernetes upgrade

Kubernetes upgrades must advance one minor version at a time. Update `KUBERNETES_MINOR` and `KUBERNETES_VERSION` in `cluster.env`, then run the script one node at a time: control planes first, followed by workers. Never upgrade all nodes concurrently.

```bash
sudo ./scripts/upgrade.sh control-plane
sudo ./scripts/upgrade.sh worker
```

Repeat for each node. The script drains the node, upgrades kubeadm/kubelet/kubectl, restarts kubelet, and uncordons it. `kubeadm upgrade plan` is run before applying the control-plane change. Worker upgrades need `KUBECONFIG` set to a secured admin kubeconfig so the script can drain and uncordon the worker. Take an etcd snapshot and test application recovery before every production upgrade.

## UniKube upgrade

Set `UNIKUBE_VERSION` in `cluster.env`, then run `install-unikube.sh` again. If UniKube is an in-cluster application rather than a node CLI, use its documented Helm release upgrade with a rolling strategy and a PodDisruptionBudget; this repository installs the official CLI only.

## Security notes

Do not commit `cluster.env`, kubeconfigs, join tokens, certificate keys, or installer credentials. Restrict the API endpoint to trusted networks, use firewall rules for Kubernetes ports, and store etcd backups encrypted and off-host.