"""
discovery.py — advertises this server on the local network via Bonjour
(mDNS), so the iPhone app can find it without anyone typing an IP
address into a source file.

The recurring failure mode this fixes: this Mac's LAN IP changes
silently between networks (already hit twice this project -- see Week
view's and APIClient's commit history), and every time it does, the
app's hardcoded address goes stale until someone notices and fixes it
by hand. Bonjour is the standard, boring answer to "find a service on
my own LAN" -- not a custom broadcast/retry scheme reinventing it.

Registered under the service type "_hybridcoach._tcp.local." -- the
iOS side (ServerDiscovery.swift) browses for exactly that type.

Uses zeroconf's asyncio API (AsyncZeroconf), not the plain sync
Zeroconf class -- the sync class runs its own work on a background
event loop and blocks waiting for it, which deadlocks when called from
inside FastAPI's own running event loop (as api.py's lifespan does).
"""

import socket

from zeroconf import ServiceInfo
from zeroconf.asyncio import AsyncZeroconf

SERVICE_TYPE = "_hybridcoach._tcp.local."
SERVICE_NAME = f"Hybrid Coach.{SERVICE_TYPE}"

_azc = None
_service_info = None


def _local_ip():
    """The IP this machine would use to reach the outside world --
    the reliable cross-platform trick for "what's my real LAN IP,"
    since hostname-based lookups can return 127.0.0.1 or a stale
    address on some systems. Doesn't actually send any packets: UDP
    connect() just asks the OS to pick the outbound route."""
    s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    try:
        s.connect(("8.8.8.8", 80))
        return s.getsockname()[0]
    finally:
        s.close()


async def start(port):
    """Register the Bonjour service. Safe to call once at server
    startup; does nothing if already registered."""
    global _azc, _service_info
    if _azc is not None:
        return

    ip = _local_ip()
    _service_info = ServiceInfo(
        SERVICE_TYPE,
        SERVICE_NAME,
        addresses=[socket.inet_aton(ip)],
        port=port,
        properties={},
    )
    _azc = AsyncZeroconf()
    await _azc.async_register_service(_service_info)


async def stop():
    """Unregister cleanly on shutdown so the service doesn't linger
    as a stale, unreachable entry on the network."""
    global _azc, _service_info
    if _azc is None:
        return
    await _azc.async_unregister_service(_service_info)
    await _azc.async_close()
    _azc = None
    _service_info = None
