# NUC Reconnect Plan

## Pre-flight (before plugging in)

1. **Verify switch ports** — 7 ports currently active (2, 5, 7, 19, 22-24). Know which ports the NUCs will connect to.
2. **Verify DHCP reservations** — confirm the router (192.168.1.1) has static leases for:
   - nuc1 → 192.168.1.20
   - nuc2 → 192.168.1.21
   - nuc3 → 192.168.1.22

   If not, set them before powering on.

## Phase 1: Bring nodes online

3. **Plug in and power on all 3 NUCs**
4. **Verify SSH access** from Mac:
   ```
   ssh bert@192.168.1.20
   ssh bert@192.168.1.21
   ssh bert@192.168.1.22
   ```
5. **Check node health** on each node:
   - `uptime`, `df -h`, `free -h`
   - `sudo systemctl status k3s` (nuc1) / `sudo systemctl status k3s-agent` (nuc2, nuc3)
   - `sudo journalctl -u k3s -n 50 --no-pager` — check for errors

## Phase 2: Cluster health

6. **Verify cluster from Mac**:
   ```
   kubectl get nodes
   kubectl get pods -A
   ```
   Wait for all nodes to show `Ready`. Pods will take a few minutes to schedule.

7. **Check for stuck pods** — anything in `CrashLoopBackOff`, `ImagePullBackOff`, or `Pending`

8. **Verify manual secrets exist** — these are not in Git:
   ```
   kubectl get secret pihole-secret -n pihole
   kubectl get secret tailscale-auth -n tailscale
   kubectl get secret grafana-admin-secret -n monitoring
   kubectl get secret traefik-dashboard-auth -n traefik
   ```
   If any are missing, recreate them before ArgoCD syncs.

## Phase 3: ArgoCD sync

9. **Check ArgoCD status**:
   ```
   kubectl get applications -n argocd
   ```
   All apps should auto-sync from the pushed commits. Watch for sync errors.

10. **Verify services come up** in sync wave order:
    - Wave -3: namespaces
    - Wave -2: MetalLB (192.168.1.200-250 pool)
    - Wave -1: Traefik (should claim 192.168.1.202)
    - Wave 0: Pi-hole (192.168.1.200), cert-manager, monitoring, Home Assistant, Ollama, Longhorn, Tailscale
    - Wave 1: cert-manager resources (CA chain)
    - Wave 2: ArgoCD ingress, monitoring ingress

## Phase 4: Verify services

11. **Test MetalLB** — confirm no IP conflicts with DHCP:
    ```
    kubectl get svc -A | grep LoadBalancer
    ```
    Pi-hole should be on 192.168.1.200, Traefik on 192.168.1.202.

12. **Test DNS** — `dig @192.168.1.200 grafana.homelab.bertbullough.com`

13. **Test ingress** — `curl -k https://grafana.homelab.bertbullough.com`

14. **Check cert-manager** — `kubectl get certificates -A` — wildcard cert should be issued

15. **Check Grafana/Prometheus** — verify monitoring dashboards load, Prometheus has targets

## Potential Issues

| Issue | Fix |
|-------|-----|
| Nodes don't get expected IPs | Set DHCP reservations on router |
| k3s won't start (cert expired) | `sudo k3s certificate rotate` on nuc1, restart k3s |
| Pods stuck `ImagePullBackOff` | Images may have been garbage collected; nodes need internet to re-pull |
| MetalLB IP conflict | `arping -c 3 192.168.1.200` before MetalLB starts |
| ArgoCD can't reach GitHub | Check DNS from cluster; Pi-hole may not be up yet |
| Missing secrets | Recreate from 1Password before services sync |
| Longhorn volumes degraded | `kubectl get volumes -n longhorn-system`; may need rebuild time |

## Switch TODO (web UI)

- Remove weak HTTPS ciphers (RC4, DES) via Security settings
- Configure NTP via System > System Time
- Enable flash logging
