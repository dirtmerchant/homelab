# OpenClaw

AI assistant powered by the [OpenClaw Helm chart](https://serhanekicii.github.io/openclaw-helm), deployed via ArgoCD.

UI: `https://openclaw.homelab.bertbullough.com`

## Prerequisites

- k3s cluster running with ArgoCD, Traefik, cert-manager, and Pi-hole
- ArgoCD app-of-apps (`k8s/argocd/apps/root.yaml`) already applied
- An [Anthropic API key](https://console.anthropic.com/settings/keys)

## Deployment Steps

### 1. Create the namespace

ArgoCD creates this automatically, but if deploying for the first time:

```bash
kubectl create namespace openclaw
```

### 2. Create the API key secret

```bash
kubectl create secret generic openclaw-env-secret \
  --namespace openclaw \
  --from-literal=ANTHROPIC_API_KEY=sk-ant-your-key-here
```

### 3. Push manifests to `main`

ArgoCD auto-syncs from the `main` branch. Commit and push changes to:

- `k8s/openclaw/values.yaml` — Helm values (probes, security, NetworkPolicy, config)
- `k8s/openclaw/ingress.yaml` — Traefik IngressRoute
- `k8s/argocd/apps/openclaw.yaml` — ArgoCD Application (Helm chart source)
- `k8s/argocd/apps/openclaw-ingress.yaml` — ArgoCD Application (IngressRoute)

ArgoCD will deploy the Helm chart and ingress automatically.

### 4. Verify deployment

```bash
# Check ArgoCD sync status
kubectl get application openclaw openclaw-ingress -n argocd

# Check pod is running
kubectl get pods -n openclaw

# Check logs
kubectl logs -n openclaw -l app.kubernetes.io/name=openclaw

# Verify NetworkPolicy is applied
kubectl get networkpolicy -n openclaw
```

### 5. Access the UI

Open `https://openclaw.homelab.bertbullough.com` in a browser.

Requires Pi-hole DNS (192.168.1.200) or manual `/etc/hosts` entry pointing the hostname to 192.168.1.202 (Traefik LB IP).

## Workload Isolation

OpenClaw is hardened with multiple layers of isolation:

| Layer | Control | Purpose |
|-------|---------|---------|
| NetworkPolicy | Ingress from Traefik only | No direct pod-to-pod access |
| NetworkPolicy | Egress blocks all private IPs | Cannot reach cluster services, nodes, or LAN |
| NetworkPolicy | DNS scoped to CoreDNS only | No arbitrary DNS |
| K8s API | `automountServiceAccountToken: false` | Cannot interact with Kubernetes API |
| OpenClaw config | Web search/fetch disabled | Defense-in-depth against SSRF |
| Container | Non-root (UID 1000), all capabilities dropped | Least privilege |
| Container | seccomp RuntimeDefault | Syscall filtering |
| Ingress | TLS + security headers middleware | Transport security |

## Updating the API Key

```bash
kubectl delete secret openclaw-env-secret -n openclaw
kubectl create secret generic openclaw-env-secret \
  --namespace openclaw \
  --from-literal=ANTHROPIC_API_KEY=sk-ant-NEW-KEY
kubectl rollout restart deployment openclaw -n openclaw
```

## Troubleshooting

| Symptom | Cause | Fix |
|---------|-------|-----|
| `CreateContainerConfigError` | `openclaw-env-secret` missing | Create the secret (step 2) |
| ArgoCD app `Unknown` sync | Helm template error | Check `kubectl get app openclaw -n argocd -o jsonpath='{.status.operationState.message}'` |
| Pod running but UI unreachable | DNS not resolving | Verify Pi-hole has `openclaw.homelab.bertbullough.com` in `custom-dns.yaml` |
| Pod can't reach Anthropic API | NetworkPolicy egress | Verify egress allows `0.0.0.0/0` minus private ranges |
