# Kubernetes Platform Architecture

```mermaid
flowchart TB
    operator[macOS or operator workstation]
    config[Local cluster.env and reviewed templates]
    runner[setup-all.sh and remote SSH runner]
    lb[Stable API endpoint or TCP load balancer]
    cp[Three Kubernetes control planes<br/>kubeadm and containerd]
    workers[Worker nodes<br/>containerd and kubelet]
    calico[Calico pod network]
    platform[Argo CD<br/>Prometheus and Grafana<br/>Alertmanager and Metrics Server]
    app[HA Nginx application<br/>3 replicas and PDB]
    ci[GitHub Actions<br/>build and publish image]
    registry[Container registry]
    agent[Principal AI agent<br/>specialists and reviewable memory]
    approval[Human approval boundary]

    operator --> config --> runner
    runner --> lb --> cp
    runner --> workers
    cp --> calico --> workers
    cp --> platform
    ci --> registry --> app
    platform --> app
    agent --> approval --> operator
    agent -. reviews .-> config

    classDef control fill:#e8f1ff,stroke:#2457a6,color:#102a56
    classDef cluster fill:#eaf8ef,stroke:#237a44,color:#123d23
    classDef service fill:#fff2df,stroke:#a65b00,color:#5b3100
    class operator,config,runner,lb,ci,registry,agent,approval control
    class cp,workers,calico,app cluster
    class platform service
```

## Flow ownership

- The operator reviews configuration and starts the Mac or Linux orchestration path.
- The API endpoint load-balances requests across three control planes.
- Control planes schedule workloads onto workers through the Calico pod network.
- Argo CD and the monitoring stack are installed through local Helm values.
- GitHub Actions builds images and publishes them to the configured registry.
- The HA Nginx deployment uses replicas, probes, topology spreading, and a PodDisruptionBudget.
- The AI agent can advise and prepare proposals, but the human approval boundary prevents autonomous changes.