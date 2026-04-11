# Argo CD GitOps Platform

Argo CD bootstraps from this repo: a root `Application` in Git pulls in child Applications for the platform stack, Argo self-manages via Helm, and I add Prometheus and Grafana with dashboards and alerts for Argo. The repo-server runs Helm **3.16.4** from an init container so the version stays in Git without rebuilding the Argo image. `Dockerfile.custom-argocd` shows how to put Helm in a custom Argo image if I go that route instead.

---

## Prerequisites

- Docker
- minikube
- kubectl, Helm, Git

---

## Quick start

**Clone**

```bash
git clone https://github.com/Nik-stack2597/Argocd-gitops-takehome.git
cd Argocd-gitops-takehome
```

**Fork / different URL:** same string in both places:

```bash
REPO_URL="https://github.com/ORGNAME/REPONAME.git"
sed -i '' "s|https://github.com/Nik-stack2597/Argocd-gitops-takehome.git|${REPO_URL}|g" \
  bootstrap/root-application.yaml apps/values.yaml
```

Private repo: GitHub will show “repo not found” unless Argo can auth. I add a repo `Secret` in `argocd` with the usual `argocd.argoproj.io/secret-type: repository` label (PAT + username). Nothing secret lives in this Git tree.

**Bootstrap**

```bash
make bootstrap
```

That starts minikube (4 CPU / 4G RAM), waits for the API, enables metrics-server, does a one-time Helm install of Argo CD, then applies the root `Application` so the rest syncs.

**UIs**

```bash
make port-forward-argocd   # https://localhost:8080
make argocd-password

make port-forward-grafana  # http://localhost:3000
```

If port 8080 is in use locally (e.g. Apache), I change the `port-forward-argocd` target in the Makefile to another port.

**Checks**

```bash
make verify-helm-version   # expect v3.16.4+ inside repo-server
make status
```

**Clean up**

```bash
make teardown
```

---

## Repo layout

- `bootstrap/`: `install.sh` (first Argo CD install) + `root-application.yaml`
- `apps/`: Helm chart that defines the child Applications (`project`, `argocd`, `monitoring`) and their sync waves
- `platform/argocd/`: Argo CD upstream chart + values (Helm binary swap, metrics, etc.)
- `platform/monitoring/`: kube-prometheus-stack + extra Grafana dashboard ConfigMap + PrometheusRule for Argo alerts

---

## Design notes

**`apps/`:** Helm chart that defines one Argo `Application` per platform (project, Argo CD, monitoring) so sync options stay separate.

**Helm on repo-server:** Init container downloads Helm 3.16.4 into a volume; see `platform/argocd/values.yaml`.

---

## Assumptions

- Tested on **minikube + Docker**.
- Argo talks to the **in-cluster** API (`https://kubernetes.default.svc`).
- Grafana password and similar are **plain values** for the exercise. In production I would use External Secrets or Vault.
- **No ingress:** only `kubectl port-forward`.
- **Polling:** no Git webhook; default Argo refresh interval.

---

## Troubleshooting

**Pods Pending / ImagePullBackOff:** `kubectl describe pod -n argocd <name>`. Often RAM: bump minikube memory or give Docker Desktop more RAM.

**Git authentication / connection errors:** If the Application shows `repository not found`, `authentication required`, or stays out of sync, Argo may not be able to clone the Git URL. GitHub returns “not found” for private repos when there is no credential, same as a bad URL. Add a repository Secret in `argocd` with label `argocd.argoproj.io/secret-type: repository` and HTTPS URL + username + token. `kubectl logs -n argocd -l app.kubernetes.io/component=repo-server` and `kubectl describe application <name> -n argocd` show the underlying error.

**Helm init container fails:** `kubectl logs -n argocd <repo-server-pod> -c download-helm`. Check DNS from inside minikube (`minikube ssh -- nslookup get.helm.sh`) or proxy settings.

**Grafana “No data” for Argo:** Confirm Prometheus sees the Argo ServiceMonitors (`kubectl port-forward` to prometheus:9090, check `/targets`). Query `argocd_app_info` in Prometheus. Label selectors (`release: monitoring`) need to line up.

**Delete and retry:** `make teardown && make bootstrap`

---

## Makefile targets

| Target | What it does |
|--------|----------------|
| `make help` | Lists targets |
| `make bootstrap` | Cluster + Argo CD + root app |
| `make teardown` | Deletes minikube profile |
| `make status` | Applications + pod snapshot |
| `make port-forward-argocd` | Argo UI on 8080 |
| `make port-forward-grafana` | Grafana on 3000 |
| `make argocd-password` | Prints admin password |
| `make verify-helm-version` | Helm version inside repo-server |
| `make lint` | `helm lint` on charts |

Docs: [Argo CD](https://argo-cd.readthedocs.io/en/stable/), [kube-prometheus-stack](https://github.com/prometheus-community/helm-charts/tree/main/charts/kube-prometheus-stack).
