# TP-Link T1600G-28TS V3 Factory Reset Recovery Plan

## Important Notes

- Management is **web UI only** — SSH is unusable because the switch only offers `ssh-dss` host keys, which OpenSSH 10.2+ has permanently removed
- The hard reset button can be unreliable — may require multiple power cycles before the management interface stabilizes
- Always click **Save** (top right) after making changes, otherwise a power cycle resets everything

## Factory Defaults

| Setting  | Value         |
|----------|---------------|
| IP       | 192.168.0.1   |
| Subnet   | 255.255.255.0 |
| Username | admin         |
| Password | admin         |

## Step 1: Connect via USB ethernet dongle

Connect a USB ethernet adapter directly to a switch port. Disconnect Wi-Fi on the Mac to avoid routing conflicts.

## Step 2: Add temporary IP alias

The switch defaults to 192.168.0.1 which is unreachable from the 192.168.1.x network.
Add a temporary address on the same subnet (use the correct interface — check with `ifconfig`):

```bash
sudo ifconfig en5 alias 192.168.0.2 netmask 255.255.255.0
```

## Step 3: Verify connectivity

```bash
ping -c 2 192.168.0.1
```

If no response, try power cycling the switch and waiting 1-2 minutes. The management interface may take time to come up after a factory reset.

## Step 4: Access the web management UI

```bash
open http://192.168.0.1
```

Log in with `admin` / `admin`.

## Step 5: Reconfigure the switch

1. **L3 FEATURES > Interface** — Edit IPv4 on VLAN1: change IP Address Mode to Static, set IP to 192.168.1.2, subnet 255.255.255.0
2. **SYSTEM > User Management** — change the default admin password
3. **SECURITY > SSH Config** — disable Protocol V1, disable CAST128-CBC/3DES-CBC/HMAC-MD5, import SSH public key
4. **Save** (top right) — persist config across reboots

## Step 6: Clean up and verify

Re-enable Wi-Fi. Remove the temporary alias:

```bash
sudo ifconfig en5 -alias 192.168.0.2
```

Verify switch is reachable:

```bash
ping -c 2 192.168.1.2
open http://192.168.1.2
```
