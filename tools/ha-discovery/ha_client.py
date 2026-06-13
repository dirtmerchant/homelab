"""Async client for Home Assistant REST and WebSocket APIs."""

import os
import subprocess

import aiohttp

HA_BASE_URL = "https://hass.homelab.bertbullough.com"
HA_WS_URL = "wss://hass.homelab.bertbullough.com/api/websocket"

# 1Password path for the HA long-lived access token
OP_TOKEN_REF = "op://Homelab/home-assistant-mcp/password"

_token_cache: str | None = None


def _get_token() -> str:
    """Load HA token from env var or 1Password. Cached after first call."""
    global _token_cache
    if _token_cache is not None:
        return _token_cache

    token = os.environ.get("HA_TOKEN")
    if token:
        _token_cache = token
        return token
    try:
        result = subprocess.run(
            ["op", "read", OP_TOKEN_REF],
            capture_output=True,
            text=True,
            timeout=10,
        )
        if result.returncode == 0 and result.stdout.strip():
            _token_cache = result.stdout.strip()
            return _token_cache
    except (FileNotFoundError, subprocess.TimeoutExpired):
        pass
    raise RuntimeError(
        "No HA token found. Set HA_TOKEN env var or ensure "
        f"'op read {OP_TOKEN_REF}' works."
    )


def _headers() -> dict[str, str]:
    return {
        "Authorization": f"Bearer {_get_token()}",
        "Content-Type": "application/json",
    }


def _ssl_context():
    """Return False to skip SSL verification for self-signed homelab cert."""
    return False


async def rest_get(path: str) -> dict | list:
    """GET request to HA REST API."""
    async with aiohttp.ClientSession() as session:
        async with session.get(
            f"{HA_BASE_URL}{path}",
            headers=_headers(),
            ssl=_ssl_context(),
        ) as resp:
            resp.raise_for_status()
            return await resp.json()


async def rest_post(path: str, data: dict | None = None) -> dict:
    """POST request to HA REST API."""
    async with aiohttp.ClientSession() as session:
        async with session.post(
            f"{HA_BASE_URL}{path}",
            headers=_headers(),
            json=data or {},
            ssl=_ssl_context(),
        ) as resp:
            resp.raise_for_status()
            return await resp.json()


async def rest_delete(path: str) -> dict:
    """DELETE request to HA REST API."""
    async with aiohttp.ClientSession() as session:
        async with session.delete(
            f"{HA_BASE_URL}{path}",
            headers=_headers(),
            ssl=_ssl_context(),
        ) as resp:
            resp.raise_for_status()
            return await resp.json()


async def ws_command(message: dict) -> dict:
    """Send a single WebSocket command and return the result.

    Opens a connection, authenticates, sends the command, waits for
    the result message, and closes. Suitable for one-shot commands
    like listing in-progress flows.
    """
    async with aiohttp.ClientSession() as session:
        async with session.ws_connect(
            HA_WS_URL, ssl=_ssl_context()
        ) as ws:
            # Wait for auth_required
            auth_req = await ws.receive_json()
            if auth_req.get("type") != "auth_required":
                raise RuntimeError(f"Unexpected WS message: {auth_req}")

            # Authenticate
            await ws.send_json({"type": "auth", "access_token": _get_token()})
            auth_resp = await ws.receive_json()
            if auth_resp.get("type") != "auth_ok":
                raise RuntimeError(f"WS auth failed: {auth_resp}")

            # Send command with id
            message["id"] = 1
            await ws.send_json(message)

            # Wait for result
            while True:
                resp = await ws.receive_json()
                if resp.get("id") == 1:
                    if not resp.get("success"):
                        error = resp.get("error", {})
                        raise RuntimeError(
                            f"WS command failed: {error.get('code')} - "
                            f"{error.get('message')}"
                        )
                    return resp.get("result")
