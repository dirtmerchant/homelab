# Gitea Migration Plan — Self-Hosted Git on k3s

## Goal

Replace GitHub with a self-hosted Gitea instance on the k3s cluster. The homelab repo stays entirely on the LAN, eliminating the need to sanitize sensitive network details from commits.

## Architecture

Gitea runs as a k8s Deployment with a PVC for data, exposed via Traefik IngressRoute at `gitea.homelab.bertbullough.com`. ArgoCD's repo source changes from GitHub to the local Gitea URL.

## Steps

### 1. Deploy Gitea

- Create `k8s/gitea/` directory
- Option A: Plain manifests (Deployment, Service, PVC, IngressRoute)
- Option B: Helm chart via multi-source ArgoCD app (like monitoring/cert-manager pattern)
- Gitea is lightweight — 512MB RAM, minimal CPU
- PVC on `local-path` storage class
- SQLite backend (sufficient for single-user)

### 2. Configure networking

- Add ArgoCD Application in `k8s/argocd/apps/gitea.yaml` (sync wave 0)
- Add IngressRoute with `tls: {}` and `security-headers@kubernetescrd` middleware
- Add DNS entry in `k8s/pihole/custom-dns.yaml`: `address=/gitea.homelab.bertbullough.com/192.168.1.202`
- Add NetworkPolicy restricting ingress to Traefik and monitoring namespaces
- Add namespace to `k8s/namespaces.yaml` with pod security labels

### 3. Set up Gitea

- Create admin user
- Create `homelab` repository
- Push existing repo to Gitea: `git remote add gitea https://gitea.homelab.bertbullough.com/bert/homelab.git && git push gitea main`

### 4. Reconfigure ArgoCD

- Update ArgoCD repo secret to point to Gitea URL instead of GitHub
- Update all Application resources in `k8s/argocd/apps/` if they reference the GitHub repo URL
- Test sync works from the new repo

### 5. Un-sanitize and migrate

- Restore full detail in docs/network.md and CLAUDE.md (no longer public)
- Verify ArgoCD auto-syncs from Gitea
- Optionally keep GitHub as a public mirror with sanitized content, or archive/delete it

## Considerations

- **Chicken-and-egg:** ArgoCD syncs from the repo, but the repo is in the cluster. If the cluster goes down, you lose both. Keep a local clone on the Mac and/or NAS as backup.
- **SSH vs HTTPS for ArgoCD:** HTTPS is simpler. Add a Gitea access token as a k8s Secret for ArgoCD.
- **Backup:** The Gitea PVC should be included in any cluster backup strategy. A cron job to `git clone --mirror` to the NAS would be a simple safeguard.
- **CI/CD:** GitHub Actions won't work. Gitea has built-in Actions (compatible with GitHub Actions workflows) or use Gitea webhooks to trigger validation.
