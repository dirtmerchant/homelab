# /ha-discover

Discover and configure new IoT devices in Home Assistant.

## Usage

```
/ha-discover
```

## Instructions

You are an agent that discovers new devices on the Home Assistant instance and drives their config flows to completion. Use the `ha-discovery` MCP server tools throughout this workflow.

### 1. Survey the current state

Run these in parallel:
- Call `list_discovered_devices` to see what HA has found on the network
- Call `list_configured_integrations` to see what's already set up

If there are no discovered devices, report that and stop.

### 2. Classify discovered devices

For each discovered device, classify it into one of these categories based on the integration type:

- **Zero-config**: Integrations like `upnp`, `ipp` (printers), `cast`, `homekit` that typically have an empty form schema and can be auto-accepted
- **Needs credentials**: Integrations like `irobot`, `ring`, `nest` that require a username/password
- **Needs pairing**: Integrations like `apple_tv`, `hue` that require a PIN or button press
- **Needs OAuth**: Integrations like `xbox`, `ecobee`, `spotify` that redirect to an external auth page
- **Unknown**: Anything you're not sure about — start the flow to inspect the schema

Present the classified list to the user with a summary like:
```
Found N discovered devices:
- 2 zero-config (can auto-accept)
- 1 needs pairing (Apple TV — will need PIN)
- 1 unknown (will inspect)
```

### 3. Auto-accept zero-config devices

For each zero-config device:
1. Call `start_config_flow` with the handler name
2. If the first step has an empty `data_schema` (or no required fields), call `advance_flow` with `{}`
3. If it returns `create_entry`, report success
4. If it returns another form step, it's not actually zero-config — add it to the interactive list
5. If it returns `abort`, report the reason and move on

Report results as you go: "Added UPnP (router)" / "Added IPP printer" / etc.

### 4. Handle interactive devices

For remaining devices that need user input:
1. Call `start_config_flow` with the handler name
2. Inspect the step:
   - **`form` with fields**: Read the `data_schema` to understand what's needed. Fill in any fields with obvious defaults. Use `AskUserQuestion` to ask the user for required fields that need real values (passwords, PINs, IPs, etc.). Then call `advance_flow`.
   - **`external` (OAuth)**: Present the URL to the user and tell them to complete auth in their browser. Poll `get_flow_step` every few seconds until the step advances.
   - **`menu`**: Present the menu options to the user via `AskUserQuestion` and let them choose.
   - **`progress`**: Tell the user to wait, poll `get_flow_step` until done.
3. Continue advancing through steps until `create_entry` (success) or `abort` (failure).

### 5. Offer to ignore unwanted devices

After processing, if any devices were skipped or failed, ask the user if they want to permanently ignore any of them (so they don't show up in future discoveries). Use `ignore_discovery` for each one the user wants to dismiss.

### 6. Summary

Print a final summary:
- Devices successfully added (with their HA names)
- Devices that failed (with reasons)
- Devices ignored
- Devices still pending (need user action later)

## allowed-tools

Bash, mcp__ha-discovery__list_discovered_devices, mcp__ha-discovery__list_configured_integrations, mcp__ha-discovery__start_config_flow, mcp__ha-discovery__get_flow_step, mcp__ha-discovery__advance_flow, mcp__ha-discovery__abort_flow, mcp__ha-discovery__ignore_discovery, AskUserQuestion
