"""MCP server for Home Assistant device discovery and config flow management."""

from fastmcp import FastMCP

from ha_client import rest_delete, rest_get, rest_post, ws_command

mcp = FastMCP(
    "ha-discovery",
    instructions=(
        "Tools for discovering new devices on the Home Assistant instance "
        "and driving config flows to add them. Use list_discovered_devices "
        "to see what HA has found, then start_config_flow and advance_flow "
        "to configure each device. Zero-config devices (empty form schema) "
        "can be auto-accepted by submitting {}. Devices requiring credentials "
        "or pairing codes will have form fields you should ask the user about."
    ),
)


@mcp.tool()
async def list_discovered_devices() -> list[dict]:
    """List devices Home Assistant has discovered but not yet configured.

    Returns a list of in-progress discovery flows, each with:
    - flow_id: Use with start_config_flow or ignore_discovery
    - handler: Integration name (e.g. 'upnp', 'apple_tv')
    - context: Discovery context with source and unique_id
    """
    return await ws_command({"type": "config_entries/flow/progress"})


@mcp.tool()
async def list_configured_integrations() -> list[dict]:
    """List all configured config entries (already set up integrations).

    Useful to check what's already configured before adding duplicates.
    Each entry includes: entry_id, domain, title, state, source.
    """
    return await rest_get("/api/config/config_entries/entry")


@mcp.tool()
async def start_config_flow(handler: str) -> dict:
    """Start a new config flow for an integration.

    Args:
        handler: Integration domain name (e.g. 'upnp', 'apple_tv', 'ipp').
                 Use the 'handler' field from list_discovered_devices.

    Returns the first step of the flow, which includes:
    - flow_id: ID to use with advance_flow and get_flow_step
    - type: Step type ('form', 'external', 'progress', 'menu',
            'create_entry', 'abort')
    - step_id: Current step identifier
    - data_schema: For 'form' type, the fields the user needs to fill in.
                   Empty schema means zero-config (submit {} to auto-accept).
    - errors: Any validation errors from previous submission
    """
    return await rest_post(
        "/api/config/config_entries/flow",
        {"handler": handler, "show_advanced_options": True},
    )


@mcp.tool()
async def get_flow_step(flow_id: str) -> dict:
    """Get the current step of an in-progress config flow.

    Args:
        flow_id: The flow ID from start_config_flow or advance_flow.

    Returns the current step with the same structure as start_config_flow.
    Useful for polling 'external' (OAuth) or 'progress' steps.
    """
    return await rest_get(f"/api/config/config_entries/flow/{flow_id}")


@mcp.tool()
async def advance_flow(flow_id: str, user_input: dict) -> dict:
    """Submit user input to advance a config flow to the next step.

    Args:
        flow_id: The flow ID from start_config_flow.
        user_input: Dict of field values matching the current step's
                    data_schema. For zero-config steps (empty schema),
                    submit {}. For menu steps, submit
                    {"next_step_id": "<option>"}.

    Returns the next step of the flow. If type is 'create_entry',
    the device was successfully added. If type is 'abort', the flow
    failed (check 'reason' field).
    """
    return await rest_post(
        f"/api/config/config_entries/flow/{flow_id}",
        user_input,
    )


@mcp.tool()
async def abort_flow(flow_id: str) -> dict:
    """Cancel an in-progress config flow.

    Args:
        flow_id: The flow ID to cancel.
    """
    return await rest_delete(f"/api/config/config_entries/flow/{flow_id}")


@mcp.tool()
async def ignore_discovery(flow_id: str, title: str) -> None:
    """Permanently ignore a discovered device so it won't appear again.

    Args:
        flow_id: The flow ID from list_discovered_devices.
        title: A human-readable label for the ignored device.
    """
    await ws_command(
        {
            "type": "config_entries/ignore_flow",
            "flow_id": flow_id,
            "title": title,
        }
    )


if __name__ == "__main__":
    mcp.run()
