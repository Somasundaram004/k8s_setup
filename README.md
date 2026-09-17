# Kubernetes and UniKube setup

This repository provides repeatable Bash scripts for an Ubuntu kubeadm cluster. It installs containerd, Kubernetes, a Calico network, and UniKube, then upgrades nodes with drain/uncordon protection.

The repository also includes a macOS operator path. macOS is not used as a production kubeadm node; it connects to Ubuntu nodes over SSH.

Every setup script supports `--dry-run`. It prints the components and operations that would be affected without requiring root, opening SSH, installing packages, draining nodes, or changing Kubernetes:

```bash
./scripts/bootstrap.sh --dry-run control-plane
./scripts/upgrade.sh control-plane --dry-run
./scripts/install-unikube.sh --dry-run
./scripts/health-check.sh --dry-run
```

## Zero-downtime requirement

Zero downtime is a topology property, not just a script feature. Use three control-plane nodes behind a TCP load balancer and at least two worker nodes. Applications must have multiple replicas, a PodDisruptionBudget, and readiness probes. A single server or a single worker cannot be upgraded without a service interruption; the scripts reject that case unless `ALLOW_DOWNTIME=true`.

## First install

1. Use Ubuntu 22.04 or 24.04 on every node. Provide a stable DNS name or load-balancer address for `CONTROL_PLANE_ENDPOINT`.
2. Copy `.env.example` to `cluster.env`, pin the Kubernetes and UniKube versions, and set the endpoint and CNI version.
3. On each node, make the scripts executable once: `chmod +x scripts/*.sh`.
4. On the first control plane, run:

   ```bash
   sudo ./scripts/bootstrap.sh control-plane
   ```

5. Copy the worker join command from `/root/worker-join-command.txt` to each worker and run:

   ```bash
   sudo JOIN_COMMAND='paste-the-command-here' ./scripts/bootstrap.sh worker
   ```

   Generate a separate control-plane join command with `kubeadm token create --print-join-command`, adding `--control-plane --certificate-key <key>` from `/root/control-plane-certificate-key.txt`.
6. Install UniKube on the node where its CLI is needed:

   ```bash
   sudo ./scripts/install-unikube.sh
   ```

   The script installs the official `unikube` Python package from PyPI. Pin `UNIKUBE_VERSION` in production.
7. Verify the cluster:

   ```bash
   sudo ./scripts/health-check.sh
   ```

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
```

Preview a remote operation without connecting to the server:

```bash
REMOTE_USER=ubuntu ./scripts/macos/remote.sh --dry-run upgrade worker 10.0.0.20
```

For worker upgrades, provide a local admin kubeconfig temporarily so the wrapper can drain and uncordon the worker:

```bash
ADMIN_KUBECONFIG="$HOME/.kube/config" REMOTE_USER=ubuntu ./scripts/macos/remote.sh upgrade worker 10.0.0.20
```

Run upgrades one node at a time, control planes first. The wrapper requires standard `ssh` and `scp`; configure SSH keys rather than passwords for repeatable operation.

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