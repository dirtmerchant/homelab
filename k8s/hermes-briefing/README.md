# Hermes Briefing Bot

Telegram-accessible AI agent running on the k3s homelab cluster. Messages sent to `@dirtmerchant_bot` route through the Hermes gateway to Claude Opus 4.6 via OpenRouter.

## Architecture

```
Telegram --> Hermes gateway (long-poll) --> OpenRouter API --> Claude Opus 4.6
                  |
                  |-- PVC (5Gi, local-path) at /opt/data
                  |-- ExternalSecret --> 1Password (OPENROUTER_API_KEY, TELEGRAM_BOT_TOKEN)
                  '-- NetworkPolicy (egress-only: TCP 443 + kube-dns)
```

- **Chart**: Vendored from [ultraworkers/hermes-agent-helm-chart](https://github.com/ultraworkers/hermes-agent-helm-chart) v0.1.0 (commit `e3b685d`). Not published to a Helm registry, so the full chart lives in `chart/`.
- **ArgoCD**: Multi-source Helm pattern at sync wave 0. Application defined in `k8s/argocd/apps/hermes-briefing.yaml`.
- **Namespace**: `hermes-briefing`, defined in `k8s/namespaces.yaml` with PSA `baseline` enforce / `restricted` warn+audit.

## Secrets

Managed by External Secrets Operator via the `onepassword` ClusterSecretStore.

| Secret Key | 1Password Item | Field |
|------------|---------------|-------|
| `OPENROUTER_API_KEY` | `hermes-briefing` | `credential` |
| `TELEGRAM_BOT_TOKEN` | `telegram dirtmerchant_bot` | `credential` |

OpenRouter requires a funded account. The free tier does not provide enough tokens for Claude Opus 4.6.

## Security

The Hermes image uses s6-overlay, which requires root startup to initialize, then drops to an unprivileged user internally via `HERMES_UID`/`HERMES_GID` (1000/1000).

- `runAsUser: 0`, `runAsNonRoot: false` (required by s6-overlay)
- Drops ALL capabilities, adds back only: `CHOWN`, `DAC_OVERRIDE`, `FOWNER`, `SETUID`, `SETGID`
- `seccompProfile: RuntimeDefault`
- `allowPrivilegeEscalation: false`
- Egress-only NetworkPolicy (HTTPS + DNS)

Telegram access is restricted by allowlist (`TELEGRAM_ALLOWED_USERS`). Unauthorized chat IDs are rejected at the gateway.

## Storage

Uses `local-path` StorageClass (matching homeassistant/pihole precedent). The PVC is pinned to whichever node it first provisions on. If that node goes down, the pod will stay Pending until the node returns.

## Vendored Chart Patches

Two patches were applied to the upstream chart templates:

1. **`templates/external-secret.yaml`**: Changed `apiVersion` from `external-secrets.io/v1beta1` to `v1` (cluster only supports v1).
2. **`templates/external-secret.yaml`**: Wrapped the `metadata:` block in a conditional to prevent rendering `metadata: null` when no annotations/labels are set, which ESO v1 rejects.

## Known Operational Notes

- **Telegram polling conflicts**: On pod restart, the old long-poll session may linger on Telegram's servers. The new pod will retry and eventually connect once the old session expires (typically under 60s).
- **OpenRouter credits**: Monitor your OpenRouter balance. HTTP 402 errors in logs mean the account needs funding.
- **PV node affinity**: Check which node holds the PVC before doing maintenance drains. See `CLAUDE.local.md` for the current PV-to-node map.

## Deployment Sessions

| Session | Status | Scope |
|---------|--------|-------|
| B1 | Complete | Deploy and prove the spine (PVC persistence, Telegram round-trip, allowlist enforcement) |
| B2 | Planned | Scheduled briefings (CronJob, morning/evening summaries) |
| B3 | Planned | Tool harness (browser, terminal, file access) |
| B4 | Planned | Observability (Prometheus metrics, Grafana dashboard, alerting) |
