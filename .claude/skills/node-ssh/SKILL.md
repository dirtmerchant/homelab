# /node-ssh

Runs a command on one or all cluster nodes via SSH.

## Usage

```
/node-ssh <node> <command>
```

Where `<node>` is a node name (e.g. `nuc1`) or `all`.

## Instructions

Parse `$ARGUMENTS` to extract the target node and the command. The first word is the node identifier; everything after it is the command to run.

### Resolve node details

Read `CLAUDE.md` to get:
- The list of node names and their IP addresses (under "Cluster Nodes")
- The SSH username and access pattern (under "Cluster Nodes")

Build the node-to-IP mapping from what you find there. `all` means run on every node in sequence.

If the user provides a node name that doesn't match any node in CLAUDE.md, inform them and list the valid node names.

### Safety checks

**REFUSE to run the command** if it matches any of these patterns. Inform the user why it was blocked:

- `rm -rf /` or any recursive delete on `/`, `/etc`, `/var`, `/usr`, `/home`, `/boot`
- `mkfs` or `fdisk` (disk formatting)
- `dd if=` writing to block devices
- `:(){ :|:& };:` or similar fork bombs
- `shutdown`, `reboot`, `poweroff`, `halt`, `init 0`, `init 6`
- `kubeadm reset` or `k3s-uninstall` (cluster destruction)
- Any command containing `> /dev/sda` or similar block device writes
- `chmod -R 777` or `chmod -R 000` on system directories
- `iptables -F` or `iptables --flush` (would break networking)

### Execution

For a single node, SSH using the access pattern from CLAUDE.md:

```bash
ssh <user>@<ip> '<command>'
```

For `all`, run the command on each node sequentially. Prefix each output block with the node name so the user can tell which output came from where.

### Presentation

Show the command output with the node name as a header. If a command fails (non-zero exit code), report the failure but continue to the next node when running on `all`.

## allowed-tools

Bash, Read
