# /cluster-status

Read-only dashboard showing cluster health, pod status, ArgoCD sync state, resource usage, events, and PVC status.

## Usage

```
/cluster-status
```

## Instructions

Run the following kubectl commands and present the results as a concise dashboard. All commands are read-only. Run independent commands in parallel where possible.

### Commands to run

1. **Node health:**
   ```bash
   kubectl get nodes -o wide
   ```

2. **Pod status** (non-Running pods highlighted):
   ```bash
   kubectl get pods -A --field-selector=status.phase!=Running,status.phase!=Succeeded
   ```

3. **ArgoCD application sync state:**
   ```bash
   kubectl get applications -n argocd -o custom-columns='NAME:.metadata.name,SYNC:.status.sync.status,HEALTH:.status.health.status,MESSAGE:.status.conditions[0].message'
   ```

4. **Node resource usage:**
   ```bash
   kubectl top nodes
   ```

5. **Warning events** (last hour):
   ```bash
   kubectl get events -A --field-selector=type=Warning --sort-by='.lastTimestamp' | tail -20
   ```

6. **PVC status:**
   ```bash
   kubectl get pvc -A
   ```

### Presentation

Format the output as a readable dashboard summary:
- Start with an overall health assessment (all good / issues found)
- Group the information by section with clear headers
- Highlight any problems: non-Running pods, out-of-sync ArgoCD apps, unhealthy nodes, warning events
- If everything is healthy, keep it brief

Do NOT suggest any changes or fixes — this is purely informational.

## allowed-tools

Bash
