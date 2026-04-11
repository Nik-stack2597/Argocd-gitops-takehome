.PHONY: bootstrap teardown status cluster-up cluster-down \
       install-argocd apply-root-app port-forward-argocd port-forward-grafana \
       argocd-password verify-helm-version lint help

CLUSTER_PROFILE   := argocd-gitops
ARGOCD_NAMESPACE  := argocd
MONITOR_NAMESPACE := monitoring
MINIKUBE_CPUS     := 4
MINIKUBE_MEMORY   := 4096
MINIKUBE_DRIVER   := docker
REPO_URL          := $(shell git remote get-url origin 2>/dev/null || echo "https://github.com/Nik-stack2597/Argocd-gitops-takehome.git")

help: ## Show this help
	@grep -E '^[a-zA-Z_-]+:.*##' $(MAKEFILE_LIST) | awk 'BEGIN {FS = ":.*## "}; {printf "  \033[36m%-24s\033[0m %s\n", $$1, $$2}'

cluster-up: ## Start minikube cluster
	@echo "==> Starting minikube cluster (profile: $(CLUSTER_PROFILE))..."
	minikube start \
		--profile $(CLUSTER_PROFILE) \
		--cpus $(MINIKUBE_CPUS) \
		--memory $(MINIKUBE_MEMORY) \
		--driver $(MINIKUBE_DRIVER)
	@echo "==> Waiting for Kubernetes API (metrics-server needs a live apiserver)..."
	@set -e; sec=0; \
	  until kubectl --context "$(CLUSTER_PROFILE)" get --raw='/readyz' >/dev/null 2>&1; do \
	    if [ $$sec -ge 180 ]; then echo "Timeout waiting for API server"; exit 1; fi; \
	    sleep 2; sec=$$((sec+2)); \
	  done
	@echo "==> Enabling metrics-server add-on..."
	minikube addons enable metrics-server --profile "$(CLUSTER_PROFILE)"
	@echo "==> Cluster ready."

cluster-down: ## Delete minikube cluster
	minikube delete --profile $(CLUSTER_PROFILE)

bootstrap: cluster-up install-argocd apply-root-app ## Full bootstrap: cluster + ArgoCD + root app
	@echo ""
	@echo "============================================="
	@echo " Bootstrap complete."
	@echo " ArgoCD UI:  make port-forward-argocd"
	@echo " Grafana UI: make port-forward-grafana"
	@echo " Password:   make argocd-password"
	@echo "============================================="

install-argocd: ## Helm-install ArgoCD (initial bootstrap only)
	./bootstrap/install.sh

apply-root-app: ## Apply the root App-of-Apps to the cluster
	@echo "==> Applying root Application..."
	kubectl apply -f bootstrap/root-application.yaml -n $(ARGOCD_NAMESPACE)
	@echo "==> Root Application applied. ArgoCD will now reconcile all child apps."

teardown: cluster-down ## Destroy everything (cluster + data)
	@echo "==> Environment torn down."

status: ## Show status of all ArgoCD Applications and pods
	@echo "==> ArgoCD Applications:"
	@kubectl get applications -n $(ARGOCD_NAMESPACE) -o wide 2>/dev/null || echo "  (none found — is ArgoCD running?)"
	@echo ""
	@echo "==> ArgoCD pods:"
	@kubectl get pods -n $(ARGOCD_NAMESPACE) 2>/dev/null || echo "  (namespace not found)"
	@echo ""
	@echo "==> Monitoring pods:"
	@kubectl get pods -n $(MONITOR_NAMESPACE) 2>/dev/null || echo "  (namespace not found)"

port-forward-argocd: ## Forward ArgoCD UI to localhost:8080
	@echo "==> ArgoCD UI at https://localhost:8080  (admin / $$(make -s argocd-password))"
	kubectl port-forward svc/argocd-server -n $(ARGOCD_NAMESPACE) 8080:443

port-forward-grafana: ## Forward Grafana UI to localhost:3000
	@echo "==> Grafana at http://localhost:3000  (admin / prom-operator)"
	kubectl port-forward svc/monitoring-grafana -n $(MONITOR_NAMESPACE) 3000:80

argocd-password: ## Print the ArgoCD admin password
	@kubectl -n $(ARGOCD_NAMESPACE) get secret argocd-initial-admin-secret \
		-o jsonpath='{.data.password}' 2>/dev/null | base64 -d; echo

verify-helm-version: ## Verify the replaced Helm binary version inside repo-server
	@echo "==> Helm version inside repo-server:"
	@kubectl exec -n $(ARGOCD_NAMESPACE) \
		$$(kubectl get pods -n $(ARGOCD_NAMESPACE) -l app.kubernetes.io/component=repo-server -o jsonpath='{.items[0].metadata.name}') \
		-- helm version --short

lint: ## Lint all Helm charts
	helm lint apps/
	helm lint platform/argocd/
	helm lint platform/monitoring/
