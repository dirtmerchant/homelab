# /add-dns

Adds a DNS entry to Pi-hole's custom DNS configuration.

## Usage

```
/add-dns <subdomain>
```

The argument is just the subdomain part (e.g. `myapp`).

## Instructions

You are adding a DNS entry for the subdomain `$ARGUMENTS`.

### Step 1: Read the current DNS config

Read `k8s/pihole/custom-dns.yaml` to determine:
- The domain suffix used by existing entries (e.g. from the existing `address=` lines)
- The Traefik ingress IP used by existing entries
- The current list of DNS entries

### Step 2: Check for duplicates

Search the file for `$ARGUMENTS` in the existing `address=` lines. If it already exists, inform the user and stop.

### Step 3: Add the entry

Add a new `address=` line to the `02-custom-dns.conf` data block using the same domain suffix and IP as the existing entries.

Insert it in alphabetical order among the existing `address=` lines. Keep all `address=` lines sorted alphabetically after the comment lines.

### Step 4: Validate

Run yamllint on the modified file:

```bash
yamllint -c .yamllint.yaml k8s/pihole/custom-dns.yaml
```

Fix any issues before finishing.

### Step 5: Confirm

Tell the user the DNS entry was added and remind them to push to `main` for ArgoCD to sync the change to Pi-hole.

## allowed-tools

Bash, Read, Edit
