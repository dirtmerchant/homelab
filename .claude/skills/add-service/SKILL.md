# /add-service

Scaffolds a new Kubernetes service for the homelab cluster end-to-end.

## Usage

```
/add-service <name>
```

## Instructions

You are adding a new service called `$ARGUMENTS` to the homelab k3s cluster. Follow these steps:

### 0. Read project context

Read `CLAUDE.md` to get the domain name, Traefik ingress IP, and other cluster details. Read an existing ArgoCD Application (e.g. `k8s/argocd/apps/pihole.yaml`) to get the git `repoURL`. These values will be needed in the templates below.

### 1. Gather requirements

Ask the user the following questions using the AskUserQuestion tool:

**Service type:** Is this a plain-manifest service (raw YAML you write yourself) or a Helm chart service (upstream chart + values.yaml)?

**Ingress:** Does this service need a web UI exposed via Traefik? If yes, ask for:
- The subdomain (e.g. `myapp` becomes `myapp.<domain>`)
- The container port the service listens on

**Storage:** Does this service need a PersistentVolumeClaim? If yes, ask for the storage size (default 5Gi).

**Container image:** For plain-manifest services, ask for the container image and tag.

**Helm chart:** For Helm services, ask for the Helm repository URL, chart name, and version constraint (e.g. `1.*`).

### 2. Create the namespace entry

Append a new namespace to `k8s/namespaces.yaml` following the existing pattern. Use baseline pod security standards (match the format already in the file).

### 3. Create the ArgoCD Application

Create `k8s/argocd/apps/<name>.yaml`.

**For plain-manifest services**, follow the pattern in `k8s/argocd/apps/pihole.yaml`: singular `source` with `path: k8s/<name>`, sync wave `"0"`, automated prune + selfHeal. Use the same `repoURL` as the existing apps.

**For Helm chart services**, follow the pattern in `k8s/argocd/apps/ollama.yaml`: plural `sources` array with a git `ref: values` source and a Helm chart source referencing `$values/k8s/<name>/values.yaml`. Use the same git `repoURL` as the existing apps.

### 4. Create service manifests

Create `k8s/<name>/` directory.

**For plain-manifest services**, create these files:

**deployment.yaml** — Follow the pattern from `k8s/homeassistant/deployment.yaml`:
- `strategy.type: Recreate` (single-replica stateful services)
- `automountServiceAccountToken: false`
- Pod securityContext with `seccompProfile.type: RuntimeDefault`
- Container securityContext with `allowPrivilegeEscalation: false` and `capabilities.drop: [ALL]`
- Startup, readiness, and liveness probes using the service port
- Resource requests (cpu: 100m, memory: 128Mi) and limits (cpu: 500m, memory: 512Mi) as sensible defaults
- Volume mount for PVC if storage was requested

**service.yaml** — ClusterIP service exposing the container port.

**pvc.yaml** (if storage requested) — Using `local-path` storage class, `ReadWriteOnce` access mode.

**For Helm chart services**, create only `k8s/<name>/values.yaml` with a comment explaining it holds overrides for the upstream chart. Ask the user what values to set, or create a minimal file with an explanatory comment.

### 5. Optional: IngressRoute + DNS + NetworkPolicy

If the user requested ingress:

**ingress.yaml** — Traefik IngressRoute following the pattern in `k8s/pihole/ingress.yaml`: websecure entrypoint, `tls: {}`, Host match rule with the project's domain, security-headers middleware from the traefik namespace.

**DNS entry** — Add a line to `k8s/pihole/custom-dns.yaml` in the `02-custom-dns.conf` data block, maintaining alphabetical order among existing entries. Use the same `address=/` format and Traefik IP as the existing entries.

**networkpolicy.yaml** — Follow `k8s/homeassistant/networkpolicy.yaml` pattern: allow ingress from the traefik namespace on the service port, unrestricted egress.

### 6. Validate

Run yamllint on all created/modified files:

```bash
yamllint -c .yamllint.yaml k8s/<name>/ k8s/namespaces.yaml k8s/argocd/apps/<name>.yaml
```

If the service got a DNS entry, also lint:

```bash
yamllint -c .yamllint.yaml k8s/pihole/custom-dns.yaml
```

Report any issues and fix them before finishing.

### 7. Summary

Print a summary of all files created and modified, and remind the user to:
- Push to `main` for ArgoCD to auto-sync
- Verify with `/cluster-status` after deployment

## allowed-tools

Bash, Read, Write, Edit, Glob, Grep
