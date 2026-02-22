# Tailscale Subnet Router

Runs a [Tailscale](https://tailscale.com) subnet router that advertises `192.168.1.0/24`, enabling remote access to all cluster services and LAN devices from any Tailscale-connected device.

## Prerequisites

1. **Tailscale account** at https://login.tailscale.com
2. **Install Tailscale** on your client device (Mac, phone, etc.)

## Auth Key Setup

Generate a reusable auth key at https://login.tailscale.com/admin/settings/keys (reusable: yes, ephemeral: no), then create the secret:

```bash
kubectl create namespace tailscale
kubectl create secret generic tailscale-auth \
  --namespace tailscale \
  --from-literal=TS_AUTHKEY=tskey-auth-xxxxx
```

ArgoCD will deploy the pod once the secret exists and the manifests are merged to `main`.

## Post-Deployment Setup

### 1. Approve subnet routes

Go to Tailscale admin console -> Machines -> `k3s-subnet-router` -> Edit route settings -> enable `192.168.1.0/24`.

### 2. Configure DNS (optional but recommended)

Go to Tailscale admin console -> DNS -> Add nameserver:
- Nameserver: `192.168.1.200` (Pi-hole)
- Restrict to domain: `homelab.bertbullough.com`

This lets `*.homelab.bertbullough.com` hostnames resolve over Tailscale without changing your device's DNS.

### 3. Verify

```bash
# From your Mac connected to Tailscale (not on the LAN):
ping 192.168.1.20                                    # nuc1
curl -k https://grafana.homelab.bertbullough.com      # Grafana UI
```

## Rotating the Auth Key

```bash
kubectl delete secret tailscale-auth -n tailscale
kubectl create secret generic tailscale-auth \
  --namespace tailscale \
  --from-literal=TS_AUTHKEY=tskey-auth-NEW-KEY
kubectl rollout restart deployment tailscale -n tailscale
```

## Troubleshooting

**Pod in `CreateContainerConfigError`**: The `tailscale-auth` secret is missing. Create it with the command above.

**Pod running but readiness probe failing**: Tailscale hasn't authenticated yet. Check logs:

```bash
kubectl logs -n tailscale -l app=tailscale
```

**Routes not working**: Ensure routes are approved in the Tailscale admin console. Unapproved routes won't forward traffic.

**Can't reach LAN devices**: The pod uses `hostNetwork: true` so it shares the node's network stack. Verify the node itself can reach the target:

```bash
# Find which node the pod is on
kubectl get pods -n tailscale -o wide

# SSH to that node and test
ssh bert@<node-ip> "ping -c1 192.168.1.1"
```

**DNS not resolving `*.homelab.bertbullough.com`**: Either configure Tailscale DNS (see post-deployment step 2) or point your device DNS to `192.168.1.200` (Pi-hole).
