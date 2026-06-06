# /validate

Runs the same validation checks as CI: yamllint and kubeconform.

## Usage

```
/validate
```

## Instructions

Run the two validation commands from the project's CI pipeline in sequence. Report results clearly.

### Step 1: yamllint

```bash
yamllint -c .yamllint.yaml k8s/
```

Report any errors or warnings. If yamllint passes, state that clearly.

### Step 2: kubeconform

```bash
find k8s/ -name '*.yaml' -not -name 'values.yaml' -not -path 'k8s/longhorn/*' \
  | xargs kubeconform -strict -kubernetes-version 1.34.0 \
    -schema-location default \
    -schema-location 'https://raw.githubusercontent.com/datreeio/CRDs-catalog/main/{{.Group}}/{{.ResourceKind}}_{{.ResourceVersion}}.json' \
    -skip ArgoCD,Application -summary
```

Report any validation failures. If kubeconform passes, state that clearly.

### Summary

Give a clear pass/fail result for each check. If both pass, confirm the manifests are valid. If either fails, list the specific errors so the user can fix them.

## allowed-tools

Bash
