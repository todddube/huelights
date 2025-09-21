"""Modern Philips Hue Control Panel with Streamlit.

A comprehensive web interface for controlling Philips Hue smart lights
with advanced features including room management, color controls,
and real-time device monitoring.
"""

from __future__ import annotations

import asyncio
import base64
import colorsys
import json
import math
import random
import socket
import time
from concurrent.futures import ThreadPoolExecutor
from contextlib import asynccontextmanager
from dataclasses import dataclass, field
from datetime import datetime, timedelta
from enum import Enum
from pathlib import Path
from typing import Any, Dict, List, Optional, Tuple, Union, cast

import httpx
import streamlit as st
from aiohue import HueBridgeV2
from aiohue.discovery import discover_bridge
from aiohue.v2 import HueBridgeV2 as HueBridgeV2Client
from aiohue.v2.models.light import Light
from aiohue.v2.models.room import Room
from aiohue.v2.models.zone import Zone
from loguru import logger
from pydantic import BaseModel, Field, field_validator
from rich.console import Console
from tenacity import retry, stop_after_attempt, wait_exponential

# Create logs directory and configure structured logging
log_dir = Path("logs")
log_dir.mkdir(exist_ok=True)

logger.configure(
    handlers=[
        {
            "sink": log_dir / "hue_app.log",
            "format": "{time:YYYY-MM-DD HH:mm:ss} | {level} | {name}:{function}:{line} | {message}",
            "rotation": "10 MB",
            "retention": "1 week",
            "compression": "zip",
        },
        {
            "sink": lambda msg: st.sidebar.write(f"🔍 {msg}") if "st" in globals() else None,
            "level": "WARNING",
            "format": "{level}: {message}",
        },
    ]
)

console = Console()


class EffectType(str, Enum):
    """Supported lighting effect types."""

    RANDOM = "random"
    RAINBOW = "rainbow"
    WARM = "warm"
    COOL = "cool"
    PARTY = "party"


@dataclass
class ColorXY:
    """XY color coordinates for Hue lights."""

    x: float = field(default=0.3127)
    y: float = field(default=0.3290)

    def __post_init__(self) -> None:
        """Validate color coordinates."""
        self.x = max(0.0, min(1.0, self.x))
        self.y = max(0.0, min(1.0, self.y))

    def to_tuple(self) -> Tuple[float, float]:
        """Convert to tuple format."""
        return (self.x, self.y)


class BridgeCredentials(BaseModel):
    """Validated bridge credentials model."""

    bridge_ip: str = Field(..., pattern=r"^(?:[0-9]{1,3}\.){3}[0-9]{1,3}$")
    bridge_username: str = Field(..., min_length=32, max_length=50)
    created_at: datetime = Field(default_factory=datetime.now)
    version: str = Field(default="2.0")

    @field_validator("bridge_ip")
    @classmethod
    def validate_ip(cls, v: str) -> str:
        """Validate IP address format."""
        octets = v.split(".")
        for octet in octets:
            if not 0 <= int(octet) <= 255:
                raise ValueError(f"Invalid IP address: {v}")
        return v


class AppSettings(BaseModel):
    """Application settings model."""

    auto_refresh: bool = Field(default=True)
    poll_interval: int = Field(default=3, ge=1, le=30)
    transition_time: int = Field(default=4, ge=0, le=300)
    show_advanced: bool = Field(default=False)
    cache_duration: int = Field(default=2, ge=1, le=10)


@dataclass
class DiscoveredBridge:
    """Discovered bridge information."""

    method: str
    ip: str
    id: str
    port: str
    name: Optional[str] = None
    model: Optional[str] = None


class HueCredentials:
    """Secure credential management for Hue bridge authentication."""

    def __init__(self, filepath: str = "creds/hue_credentials.json") -> None:
        self.filepath = Path(filepath)
        self.filepath.parent.mkdir(exist_ok=True)

    @retry(
        stop=stop_after_attempt(3),
        wait=wait_exponential(multiplier=1, min=4, max=10)
    )
    def save(self, ip: str, username: str) -> None:
        """Save validated bridge credentials with secure encoding."""
        try:
            # Validate credentials using Pydantic
            creds = BridgeCredentials(
                bridge_ip=ip,
                bridge_username=username
            )

            # Encode for storage (not for security, just obfuscation)
            encoded_creds = {
                "bridge_ip": base64.b64encode(creds.bridge_ip.encode()).decode(),
                "bridge_username": base64.b64encode(creds.bridge_username.encode()).decode(),
                "created_at": creds.created_at.isoformat(),
                "version": creds.version,
            }

            with self.filepath.open("w") as f:
                json.dump(encoded_creds, f, indent=4)

            logger.info(f"Credentials saved to {self.filepath}")

        except Exception as e:
            logger.error(f"Error saving credentials: {e}")
            raise

    def load(self) -> Tuple[Optional[str], Optional[str]]:
        """Load and decode credentials from secure storage with legacy support."""
        try:
            if not self.filepath.exists():
                return None, None

            with self.filepath.open() as f:
                encoded_creds = json.load(f)

            # Handle both legacy and modern formats
            if self._is_legacy_format(encoded_creds):
                logger.info("Found legacy credentials, migrating to modern format")
                bridge_ip, bridge_username = self._migrate_legacy_credentials(encoded_creds)
            else:
                # Modern format
                bridge_ip = base64.b64decode(encoded_creds["bridge_ip"]).decode()
                bridge_username = base64.b64decode(encoded_creds["bridge_username"]).decode()

            # Validate loaded credentials
            BridgeCredentials(
                bridge_ip=bridge_ip,
                bridge_username=bridge_username
            )

            return bridge_ip, bridge_username

        except Exception as e:
            logger.error(f"Error loading credentials: {e}")
            return None, None

    def _is_legacy_format(self, creds: Dict[str, Any]) -> bool:
        """Check if credentials are in legacy format (missing metadata)."""
        # Legacy format only has bridge_ip and bridge_username
        # Modern format has created_at and version fields
        return "created_at" not in creds and "version" not in creds

    def _migrate_legacy_credentials(self, legacy_creds: Dict[str, Any]) -> Tuple[str, str]:
        """Migrate legacy credentials to modern format and save."""
        try:
            # Decode legacy credentials
            bridge_ip = base64.b64decode(legacy_creds["bridge_ip"]).decode()
            bridge_username = base64.b64decode(legacy_creds["bridge_username"]).decode()

            logger.info(f"Migrating credentials for bridge: {bridge_ip}")

            # Save in modern format (this will add metadata)
            self.save(bridge_ip, bridge_username)

            logger.info("✅ Successfully migrated legacy credentials to modern format")
            return bridge_ip, bridge_username

        except Exception as e:
            logger.error(f"Failed to migrate legacy credentials: {e}")
            raise

    @retry(
        stop=stop_after_attempt(2),
        wait=wait_exponential(multiplier=1, min=2, max=4)
    )
    async def is_valid_async(self) -> bool:
        """Async validation of stored credentials."""
        bridge_ip, bridge_username = self.load()
        if not bridge_ip or not bridge_username:
            return False

        try:
            async with httpx.AsyncClient(timeout=5.0) as client:
                bridge = HueBridgeV2Client(bridge_ip, bridge_username, client)
                await bridge.initialize()
                return True
        except Exception as e:
            logger.debug(f"Credential validation failed: {e}")
            return False

    def is_valid(self) -> bool:
        """Synchronous wrapper for credential validation."""
        try:
            return asyncio.run(self.is_valid_async())
        except Exception:
            return False


class HueBridgeDiscovery:
    """Advanced bridge discovery with multiple detection methods."""

    def __init__(self) -> None:
        self._discovery_timeout = 10.0
        self._scan_timeout = 1.0

    @retry(
        stop=stop_after_attempt(3),
        wait=wait_exponential(multiplier=1, min=2, max=8)
    )
    async def discover_bridges_async(self) -> List[DiscoveredBridge]:
        """Asynchronously discover Hue bridges using multiple methods."""
        bridges: List[DiscoveredBridge] = []

        # Method 1: Official Hue discovery
        try:
            async with httpx.AsyncClient(timeout=self._discovery_timeout) as client:
                discovered = await discover_bridge(client)
                for bridge in discovered:
                    bridges.append(
                        DiscoveredBridge(
                            method="aiohue_discovery",
                            ip=bridge.host,
                            id=bridge.id,
                            port=str(bridge.port or 443),
                            name=getattr(bridge, "name", None),
                        )
                    )

        except Exception as e:
            logger.warning(f"Official discovery failed: {e}")

        # Method 2: SSDP/UPnP discovery (fallback)
        if not bridges:
            bridges.extend(await self._ssdp_discovery())

        # Method 3: Network scan (last resort)
        if not bridges:
            bridges.extend(await self._network_scan_async())

        # Remove duplicates based on IP
        unique_bridges = {}
        for bridge in bridges:
            if bridge.ip not in unique_bridges:
                unique_bridges[bridge.ip] = bridge

        result = list(unique_bridges.values())
        logger.info(f"Discovered {len(result)} unique bridges")
        return result

    def discover_bridges(self) -> List[DiscoveredBridge]:
        """Synchronous wrapper for bridge discovery."""
        try:
            return asyncio.run(self.discover_bridges_async())
        except Exception as e:
            logger.error(f"Bridge discovery failed: {e}")
            return []

    async def _ssdp_discovery(self) -> List[DiscoveredBridge]:
        """SSDP/UPnP discovery method."""
        bridges: List[DiscoveredBridge] = []

        try:
            # Try the official Hue discovery endpoint
            async with httpx.AsyncClient() as client:
                response = await client.get(
                    "https://discovery.meethue.com",
                    timeout=5.0
                )
                if response.status_code == 200:
                    data = response.json()
                    for bridge_data in data:
                        bridges.append(
                            DiscoveredBridge(
                                method="meethue_discovery",
                                ip=bridge_data["internalipaddress"],
                                id=bridge_data["id"],
                                port="443",
                            )
                        )
        except Exception as e:
            logger.debug(f"SSDP discovery failed: {e}")

        return bridges

    async def _network_scan_async(self) -> List[DiscoveredBridge]:
        """Asynchronous network scan for bridges."""
        bridges: List[DiscoveredBridge] = []

        try:
            # Get local network range
            hostname = socket.gethostname()
            local_ip = socket.gethostbyname(hostname)
            network_base = ".".join(local_ip.split(".")[:-1]) + "."

            async def check_ip(ip: str) -> Optional[DiscoveredBridge]:
                try:
                    async with httpx.AsyncClient(timeout=self._scan_timeout) as client:
                        response = await client.get(f"http://{ip}/api/config")
                        if response.status_code == 200:
                            data = response.json()
                            if "bridgeid" in data:
                                return DiscoveredBridge(
                                    method="network_scan",
                                    ip=ip,
                                    id=data.get("bridgeid", ""),
                                    port="80",
                                    name=data.get("name"),
                                    model=data.get("modelid"),
                                )
                except Exception:
                    pass
                return None

            # Scan common IP ranges
            tasks = []
            for i in range(1, 255):
                ip = f"{network_base}{i}"
                tasks.append(check_ip(ip))

            results = await asyncio.gather(*tasks, return_exceptions=True)
            bridges = [r for r in results if isinstance(r, DiscoveredBridge)]

        except Exception as e:
            logger.warning(f"Network scan failed: {e}")

        return bridges


class HueController:
    """Advanced Hue bridge controller with modern async patterns."""

    def __init__(self, ip: str, username: str, settings: Optional[AppSettings] = None) -> None:
        self.bridge_ip = ip
        self.username = username
        self.settings = settings or AppSettings()
        self.bridge: Optional[HueBridgeV2Client] = None
        self.client: Optional[httpx.AsyncClient] = None
        self._cache: Dict[str, Any] = {}
        self._cache_expiry: Dict[str, datetime] = {}
        self._lock = asyncio.Lock()
        self._initialized = False

    @asynccontextmanager
    async def _ensure_connection(self):
        """Ensure bridge connection is established."""
        async with self._lock:
            if not self._initialized:
                await self._initialize_bridge()
            yield self.bridge

    @retry(
        stop=stop_after_attempt(3),
        wait=wait_exponential(multiplier=1, min=2, max=8)
    )
    async def _initialize_bridge(self) -> None:
        """Initialize bridge connection with retry logic."""
        try:
            if self.client:
                await self.client.aclose()

            self.client = httpx.AsyncClient(
                timeout=httpx.Timeout(30.0),
                limits=httpx.Limits(max_connections=10, max_keepalive_connections=5)
            )

            self.bridge = HueBridgeV2Client(self.bridge_ip, self.username, self.client)
            await self.bridge.initialize()
            self._initialized = True

            logger.info(f"Successfully connected to bridge at {self.bridge_ip}")

        except Exception as e:
            logger.error(f"Bridge initialization failed: {e}")
            if self.client:
                await self.client.aclose()
                self.client = None
            self._initialized = False
            raise

    def _is_cache_valid(self, key: str) -> bool:
        """Check if cache entry is still valid."""
        if key not in self._cache_expiry:
            return False
        return datetime.now() < self._cache_expiry[key]

    def _set_cache(self, key: str, value: Any) -> None:
        """Set cache with configurable expiry time."""
        self._cache[key] = value
        self._cache_expiry[key] = datetime.now() + timedelta(
            seconds=self.settings.cache_duration
        )

    def clear_cache(self) -> None:
        """Clear all cached data."""
        self._cache.clear()
        self._cache_expiry.clear()
        logger.debug("Cache cleared")

    async def get_lights_async(self, use_cache: bool = True) -> List[Light]:
        """Get lights asynchronously with optional caching."""
        cache_key = "lights"

        if use_cache and self._is_cache_valid(cache_key):
            return cast(List[Light], self._cache[cache_key])

        async with self._ensure_connection() as bridge:
            if not bridge:
                raise ConnectionError("Bridge not available")

            lights = list(bridge.lights.values())

            if use_cache:
                self._set_cache(cache_key, lights)

            logger.debug(f"Retrieved {len(lights)} lights from bridge")
            return lights

    def get_lights(self) -> List[Light]:
        """Synchronous wrapper for getting lights."""
        try:
            return asyncio.run(self.get_lights_async())
        except Exception as e:
            logger.error(f"Failed to get lights: {e}")
            return []

    async def get_groups_async(self, use_cache: bool = True) -> List[Union[Room, Zone]]:
        """Get rooms and zones asynchronously with optional caching."""
        cache_key = "groups"

        if use_cache and self._is_cache_valid(cache_key):
            return cast(List[Union[Room, Zone]], self._cache[cache_key])

        async with self._ensure_connection() as bridge:
            if not bridge:
                raise ConnectionError("Bridge not available")

            rooms = list(bridge.rooms.values())
            zones = list(bridge.zones.values())
            groups = rooms + zones

            if use_cache:
                self._set_cache(cache_key, groups)

            logger.debug(f"Retrieved {len(groups)} groups from bridge")
            return groups

    def get_groups(self) -> List[Union[Room, Zone]]:
        """Synchronous wrapper for getting groups."""
        try:
            return asyncio.run(self.get_groups_async())
        except Exception as e:
            logger.error(f"Failed to get groups: {e}")
            return []

    async def get_bridge_info_async(self, use_cache: bool = True) -> Dict[str, Any]:
        """Get bridge information asynchronously."""
        cache_key = "bridge_info"

        if use_cache and self._is_cache_valid(cache_key):
            return cast(Dict[str, Any], self._cache[cache_key])

        try:
            async with self._ensure_connection() as bridge:
                if not bridge or not hasattr(bridge, "bridge") or not bridge.bridge:
                    return {}

                bridge_info = bridge.bridge
                info = {
                    "name": getattr(bridge_info, "name", "Unknown"),
                    "id": getattr(bridge_info, "id", "Unknown"),
                    "bridge_id": getattr(bridge_info, "bridge_id", "Unknown"),
                    "api_version": "2.0",
                    "software_version": getattr(bridge_info, "software_version", "Unknown"),
                    "model_id": getattr(bridge_info, "model_id", "Unknown"),
                    "connected_at": datetime.now().isoformat(),
                }

                if use_cache:
                    self._set_cache(cache_key, info)

                return info

        except Exception as e:
            logger.error(f"Failed to get bridge info: {e}")
            return {}

    def get_bridge_info(self) -> Dict[str, Any]:
        """Synchronous wrapper for getting bridge info."""
        try:
            return asyncio.run(self.get_bridge_info_async())
        except Exception as e:
            logger.error(f"Failed to get bridge info: {e}")
            return {}

    @staticmethod
    def get_light_state(light: Light) -> bool:
        """Safely get current light on/off state."""
        try:
            return bool(getattr(getattr(light, "on", None), "on", False))
        except (AttributeError, TypeError):
            return False

    @staticmethod
    def get_light_brightness(light: Light) -> int:
        """Safely get current light brightness (0-100%)."""
        try:
            dimming = getattr(light, "dimming", None)
            if dimming:
                brightness = getattr(dimming, "brightness", 0)
                return max(0, min(100, int(brightness or 0)))
            return 0
        except (AttributeError, TypeError, ValueError):
            light_name = HueController.get_light_name(light)
            logger.debug(f"Light {light_name} has no brightness attribute")
            return 0

    @staticmethod
    def get_light_name(light: Light) -> str:
        """Safely get light name."""
        try:
            metadata = getattr(light, "metadata", None)
            if metadata:
                return getattr(metadata, "name", "Unknown Light")
            return "Unknown Light"
        except (AttributeError, TypeError):
            return "Unknown Light"

    @staticmethod
    def get_light_color_info(light: Light) -> Dict[str, Any]:
        """Get comprehensive light color information."""
        color_info: Dict[str, Any] = {}

        try:
            # XY color coordinates
            color = getattr(light, "color", None)
            if color and hasattr(color, "xy"):
                xy = color.xy
                color_info["xy"] = [getattr(xy, "x", 0), getattr(xy, "y", 0)]

            # Color temperature
            color_temp = getattr(light, "color_temperature", None)
            if color_temp:
                mirek = getattr(color_temp, "mirek", None)
                if mirek and mirek > 0:
                    color_info["ct"] = mirek
                    # Convert mirek to Kelvin for display
                    color_info["kelvin"] = int(1_000_000 / mirek)

            # Check if light supports color
            color_info["supports_color"] = bool(color)
            color_info["supports_temperature"] = bool(color_temp)

        except (AttributeError, TypeError, ZeroDivisionError) as e:
            logger.debug(f"Error getting color info: {e}")

        return color_info

    @staticmethod
    def rgb_to_xy(red: float, green: float, blue: float) -> ColorXY:
        """Convert RGB to XY color space using proper color science.

        Args:
            red: Red component (0.0 - 1.0)
            green: Green component (0.0 - 1.0)
            blue: Blue component (0.0 - 1.0)

        Returns:
            ColorXY object with validated coordinates
        """
        # Clamp input values
        red = max(0.0, min(1.0, red))
        green = max(0.0, min(1.0, green))
        blue = max(0.0, min(1.0, blue))

        # Apply gamma correction (sRGB to linear RGB)
        def gamma_correct(component: float) -> float:
            return (
                pow((component + 0.055) / 1.055, 2.4)
                if component > 0.04045
                else component / 12.92
            )

        linear_r = gamma_correct(red)
        linear_g = gamma_correct(green)
        linear_b = gamma_correct(blue)

        # Convert to XYZ using sRGB matrix
        X = linear_r * 0.664511 + linear_g * 0.154324 + linear_b * 0.162028
        Y = linear_r * 0.283881 + linear_g * 0.668433 + linear_b * 0.047685
        Z = linear_r * 0.000088 + linear_g * 0.072310 + linear_b * 0.986039

        # Convert to xy chromaticity coordinates
        total = X + Y + Z
        if total == 0:
            # Default to standard illuminant D65 white point
            return ColorXY(x=0.3127, y=0.3290)

        x = X / total
        y = Y / total

        return ColorXY(x=x, y=y)

    @staticmethod
    def generate_color_by_effect(effect: EffectType, index: int = 0, total: int = 1) -> ColorXY:
        """Generate colors based on effect type with deterministic results."""
        if effect == EffectType.RANDOM:
            # Use index as seed for reproducible randomness
            random.seed(index)
            hue = random.uniform(0, 1)
            saturation = random.uniform(0.6, 1.0)
            value = random.uniform(0.8, 1.0)

        elif effect == EffectType.RAINBOW:
            # Evenly distribute hues across the spectrum
            hue = (index / max(1, total)) % 1.0
            saturation = 1.0
            value = 1.0

        elif effect == EffectType.WARM:
            # Warm colors: reds, oranges, yellows
            if random.random() > 0.5:
                hue = random.uniform(0.0, 0.15)  # Red to yellow
            else:
                hue = random.uniform(0.85, 1.0)  # Red wrap-around
            saturation = random.uniform(0.7, 1.0)
            value = random.uniform(0.8, 1.0)

        elif effect == EffectType.COOL:
            # Cool colors: blues, greens, purples
            hue = random.uniform(0.3, 0.8)
            saturation = random.uniform(0.7, 1.0)
            value = random.uniform(0.8, 1.0)

        elif effect == EffectType.PARTY:
            # High saturation, bright colors
            hue = random.uniform(0, 1)
            saturation = random.uniform(0.8, 1.0)
            value = 1.0

        else:
            # Default to white
            return ColorXY()

        r, g, b = colorsys.hsv_to_rgb(hue, saturation, value)
        return HueController.rgb_to_xy(r, g, b)

    @classmethod
    def generate_colors_for_lights(
        cls, lights: List[Light], effect: EffectType
    ) -> Dict[str, ColorXY]:
        """Generate colors for a list of lights based on effect type."""
        colors = {}
        total_lights = len(lights)

        for i, light in enumerate(lights):
            colors[light.id] = cls.generate_color_by_effect(effect, i, total_lights)

        return colors

    async def control_light_async(
        self, light: Light, new_state: bool, transition: int = 4
    ) -> bool:
        """Control individual light state asynchronously."""
        try:
            async with self._ensure_connection() as bridge:
                if not bridge:
                    return False

                update_data = {
                    "on": {"on": new_state},
                    "dynamics": {"duration": transition * 100}
                }

                await bridge.lights.set_state(light.id, **update_data)

                # Invalidate cache
                if "lights" in self._cache:
                    del self._cache["lights"]

                light_name = self.get_light_name(light)
                logger.info(f"Set light {light_name} to state: {new_state}")
                return True

        except Exception as e:
            light_name = self.get_light_name(light)
            logger.error(f"Error controlling light {light_name}: {e}")
            return False

    def control_light(self, light: Light, new_state: bool, transition: int = 4) -> bool:
        """Synchronous wrapper for light control."""
        try:
            return asyncio.run(self.control_light_async(light, new_state, transition))
        except Exception as e:
            logger.error(f"Failed to control light: {e}")
            return False

    async def set_light_brightness_async(
        self, light: Light, brightness_pct: int, transition: int = 4
    ) -> bool:
        """Set light brightness asynchronously."""
        try:
            async with self._ensure_connection() as bridge:
                if not bridge:
                    return False

                update_data = {
                    "dimming": {"brightness": max(1, min(100, brightness_pct))},
                    "dynamics": {"duration": transition * 100}
                }

                await bridge.lights.set_state(light.id, **update_data)

                # Invalidate cache
                if "lights" in self._cache:
                    del self._cache["lights"]

                light_name = self.get_light_name(light)
                logger.info(f"Set light {light_name} brightness to: {brightness_pct}%")
                return True

        except Exception as e:
            light_name = self.get_light_name(light)
            logger.error(f"Error setting brightness for light {light_name}: {e}")
            return False

    def set_light_brightness(self, light: Light, brightness_pct: int, transition: int = 4) -> bool:
        """Synchronous wrapper for brightness control."""
        try:
            return asyncio.run(self.set_light_brightness_async(light, brightness_pct, transition))
        except Exception as e:
            logger.error(f"Failed to set brightness: {e}")
            return False

    async def set_light_color_async(
        self, light: Light, color: Union[str, ColorXY, Tuple[float, float]], transition: int = 4
    ) -> bool:
        """Set light color asynchronously with multiple input formats."""
        try:
            async with self._ensure_connection() as bridge:
                if not bridge:
                    return False

                update_data = {"dynamics": {"duration": transition * 100}}

                if isinstance(color, str) and color.startswith('#'):
                    # Hex color to XY conversion
                    hex_color = color.lstrip('#')
                    r, g, b = tuple(int(hex_color[i:i+2], 16) / 255.0 for i in (0, 2, 4))
                    xy_color = self.rgb_to_xy(r, g, b)
                    update_data["color"] = {"xy": {"x": xy_color.x, "y": xy_color.y}}

                elif isinstance(color, ColorXY):
                    update_data["color"] = {"xy": {"x": color.x, "y": color.y}}

                elif isinstance(color, (list, tuple)) and len(color) == 2:
                    # XY coordinates
                    update_data["color"] = {"xy": {"x": color[0], "y": color[1]}}

                elif isinstance(color, (list, tuple)) and len(color) == 3:
                    # RGB values (0-1 range)
                    r, g, b = color
                    xy_color = self.rgb_to_xy(r, g, b)
                    update_data["color"] = {"xy": {"x": xy_color.x, "y": xy_color.y}}

                else:
                    raise ValueError(f"Unsupported color format: {color}")

                await bridge.lights.set_state(light.id, **update_data)

                # Invalidate cache
                if "lights" in self._cache:
                    del self._cache["lights"]

                light_name = self.get_light_name(light)
                logger.info(f"Set light {light_name} color to: {color}")
                return True

        except Exception as e:
            light_name = self.get_light_name(light)
            logger.error(f"Error setting color for light {light_name}: {e}")
            return False

    def set_light_color(
        self, light: Light, color: Union[str, ColorXY, Tuple[float, float]], transition: int = 4
    ) -> bool:
        """Synchronous wrapper for color control."""
        try:
            return asyncio.run(self.set_light_color_async(light, color, transition))
        except Exception as e:
            logger.error(f"Failed to set color: {e}")
            return False

    async def cleanup(self) -> None:
        """Properly clean up resources."""
        if self.client:
            try:
                await self.client.aclose()
                logger.debug("HTTP client closed")
            except Exception as e:
                logger.warning(f"Error closing HTTP client: {e}")
            finally:
                self.client = None
                self.bridge = None
                self._initialized = False

    def __del__(self) -> None:
        """Cleanup when controller is destroyed."""
        if self.client and not self.client.is_closed:
            try:
                asyncio.run(self.cleanup())
            except Exception as e:
                logger.debug(f"Cleanup error in destructor: {e}")


class HueApp:
    """Modernized Hue application with enhanced UI and error handling."""

    def __init__(self) -> None:
        self.credentials = HueCredentials()
        self.controller: Optional[HueController] = None
        self.discovery = HueBridgeDiscovery()
        self.settings = AppSettings()

        # Initialize session state
        self._init_session_state()

    def _init_session_state(self) -> None:
        """Initialize Streamlit session state variables."""
        defaults = {
            'last_update': 0,
            'poll_interval': self.settings.poll_interval,
            'auto_refresh': self.settings.auto_refresh,
            'transition_time': self.settings.transition_time,
            'show_advanced': self.settings.show_advanced,
            'discovered_bridges': [],
        }

        for key, value in defaults.items():
            if key not in st.session_state:
                st.session_state[key] = value

    def should_update(self) -> bool:
        """Check if it's time to update based on polling interval."""
        if not st.session_state.auto_refresh:
            return False

        current_time = time.time()
        if current_time - st.session_state.last_update >= st.session_state.poll_interval:
            st.session_state.last_update = current_time
            return True
        return False

    def render_sidebar_settings(self) -> None:
        """Render enhanced sidebar with modern settings."""
        with st.sidebar:
            st.header("⚙️ Settings")

            # Auto-refresh settings
            st.session_state.auto_refresh = st.checkbox(
                "Auto-refresh",
                value=st.session_state.auto_refresh,
                help="Automatically refresh device states"
            )

            if st.session_state.auto_refresh:
                st.session_state.poll_interval = st.slider(
                    "Refresh interval (seconds)",
                    min_value=1,
                    max_value=30,
                    value=st.session_state.poll_interval,
                    help="How often to refresh device states"
                )

            # Transition settings
            st.session_state.transition_time = st.slider(
                "Transition time (100ms)",
                min_value=0,
                max_value=300,
                value=st.session_state.transition_time,
                step=1,
                help="Transition time for light changes (0 = instant)"
            )

            # Advanced settings
            st.session_state.show_advanced = st.checkbox(
                "Show advanced controls",
                value=st.session_state.show_advanced,
                help="Show color controls and advanced options"
            )

            st.divider()

            # Bridge management
            st.subheader("🌉 Bridge Management")

            col1, col2 = st.columns(2)

            with col1:
                if st.button("🔍 Discover", use_container_width=True):
                    with st.spinner("Discovering..."):
                        st.session_state.discovered_bridges = self.discovery.discover_bridges()
                    st.rerun()

            with col2:
                if st.button("🔄 Clear Cache", use_container_width=True):
                    if self.controller:
                        self.controller.clear_cache()
                    st.success("Cache cleared!", icon="✅")

            if st.button("❌ Clear Credentials", use_container_width=True):
                if self.credentials.filepath.exists():
                    self.credentials.filepath.unlink()
                    st.success("Credentials cleared!", icon="✅")
                    st.rerun()

    def main(self) -> None:
        """Main application entry point."""
        st.set_page_config(
            page_title="Modern Hue Control Panel",
            page_icon="💡",
            layout="wide",
            initial_sidebar_state="expanded"
        )

        st.title("💡 Modern Philips Hue Control Panel")
        st.caption("Powered by modern Python frameworks and best practices")

        # Render sidebar
        self.render_sidebar_settings()

        # Load and validate credentials
        bridge_ip, bridge_username = self.credentials.load()

        if not bridge_ip or not bridge_username or not self.credentials.is_valid():
            self._show_bridge_setup()
            return

        try:
            # Initialize controller
            if not self.controller:
                self.controller = HueController(bridge_ip, bridge_username, self.settings)

            # Auto-refresh
            if self.should_update():
                logger.info(f"Auto-refresh at {datetime.now().strftime('%H:%M:%S')}")
                st.rerun()

            # Render main content
            self._render_main_content()

        except Exception as e:
            st.error(f"🚨 Error connecting to bridge: {e}")
            logger.error(f"Bridge connection error: {e}")

            if st.button("🔄 Retry Connection"):
                if self.controller:
                    asyncio.run(self.controller.cleanup())
                    self.controller = None
                st.rerun()

    def _show_bridge_setup(self) -> None:
        """Show bridge discovery and setup interface."""
        st.warning("🔧 Bridge setup required")

        # Show discovered bridges
        if st.session_state.discovered_bridges:
            st.subheader("🔍 Discovered Bridges")

            for i, bridge in enumerate(st.session_state.discovered_bridges):
                with st.expander(f"Bridge {i+1}: {bridge.ip}"):
                    col1, col2 = st.columns(2)

                    with col1:
                        st.write(f"**IP:** {bridge.ip}")
                        st.write(f"**Method:** {bridge.method}")
                        st.write(f"**ID:** {bridge.id}")

                    with col2:
                        st.write(f"**Port:** {bridge.port}")
                        if bridge.name:
                            st.write(f"**Name:** {bridge.name}")
                        if bridge.model:
                            st.write(f"**Model:** {bridge.model}")

                    if st.button(f"Setup Bridge {i+1}", key=f"setup_{i}"):
                        self._setup_bridge(bridge.ip)
        else:
            st.info("No bridges discovered. Click 'Discover' in the sidebar or enter details manually below.")

        # Manual setup
        st.subheader("✏️ Manual Setup")

        with st.form("manual_bridge_setup"):
            ip = st.text_input("Bridge IP Address", placeholder="192.168.1.xxx")

            if st.form_submit_button("Setup Bridge") and ip:
                self._setup_bridge(ip)

    def _setup_bridge(self, bridge_ip: str) -> None:
        """Setup bridge with button press authentication."""
        st.info("🔴 Press the button on your Hue Bridge now!")
        st.write("You have 30 seconds to press the physical button.")

        progress = st.progress(0)
        status = st.empty()

        async def authenticate():
            async with httpx.AsyncClient() as client:
                bridge = HueBridgeV2Client(bridge_ip, None, client)
                return await bridge.create_user("modern_hue_app")

        for i in range(30):
            try:
                username = asyncio.run(authenticate())
                if username:
                    self.credentials.save(bridge_ip, username)
                    st.success("✅ Bridge setup successful!")
                    time.sleep(1)
                    st.rerun()
                    return
            except Exception:
                pass

            remaining = 30 - i
            status.text(f"⏳ Waiting for button press... {remaining}s")
            progress.progress((i + 1) / 30)
            time.sleep(1)

        st.error("❌ Setup failed. Please try again.")

    def _render_main_content(self) -> None:
        """Render the main application content."""
        if not self.controller:
            return

        # Status bar
        self._render_status_bar()

        # Get devices
        try:
            lights = self.controller.get_lights()
            groups = self.controller.get_groups()
        except Exception as e:
            st.error(f"🚨 Error fetching devices: {e}")
            return

        # Main tabs
        tab1, tab2, tab3 = st.tabs(["🏠 Rooms & Groups", "💡 All Lights", "📊 Bridge Info"])

        with tab1:
            self._render_groups_tab(groups, lights)

        with tab2:
            self._render_lights_tab(lights)

        with tab3:
            self._render_bridge_info_tab(lights, groups)

    def _render_status_bar(self) -> None:
        """Render status information bar."""
        if not self.controller:
            return

        bridge_info = self.controller.get_bridge_info()

        col1, col2, col3, col4 = st.columns(4)

        with col1:
            if bridge_info:
                st.metric("Bridge", bridge_info.get("name", "Unknown"))
            else:
                st.metric("Bridge", self.controller.bridge_ip)

        with col2:
            st.metric("API Version", bridge_info.get("api_version", "2.0"))

        with col3:
            status = "🔄 ON" if st.session_state.auto_refresh else "⏸️ OFF"
            st.metric("Auto-refresh", status)

        with col4:
            st.metric("Time", datetime.now().strftime("%H:%M:%S"))

    def _render_groups_tab(self, groups: List[Union[Room, Zone]], lights: List[Light]) -> None:
        """Render groups/rooms tab."""
        if not groups:
            st.info("No groups found on your bridge.")
            return

        for group in groups:
            with st.container():
                # Group controls would go here
                group_name = getattr(group.metadata, 'name', 'Unknown') if hasattr(group, 'metadata') else 'Unknown'
                st.subheader(f"🏠 {group_name}")

                # Basic group control placeholder
                col1, col2 = st.columns(2)

                with col1:
                    if st.button(f"Toggle {group_name}", key=f"toggle_{group.id}"):
                        st.info("Group control functionality would be implemented here")

                with col2:
                    st.write(f"Group ID: {group.id}")

                st.divider()

    def _render_lights_tab(self, lights: List[Light]) -> None:
        """Render individual lights tab."""
        if not lights:
            st.info("No lights found on your bridge.")
            return

        st.subheader(f"💡 All Lights ({len(lights)} total)")

        # Global controls
        if st.session_state.show_advanced:
            col1, col2, col3, col4 = st.columns(4)

            with col1:
                if st.button("🌞 All On"):
                    st.info("Global controls would be implemented here")

            with col2:
                if st.button("🌙 All Off"):
                    st.info("Global controls would be implemented here")

            with col3:
                if st.button("🎨 Random Colors"):
                    st.info("Color effects would be implemented here")

            with col4:
                if st.button("🌈 Rainbow"):
                    st.info("Rainbow effect would be implemented here")

        # Individual light controls
        for light in lights:
            self._render_light_controls(light)

    def _render_light_controls(self, light: Light) -> None:
        """Render individual light controls."""
        if not self.controller:
            return

        light_name = self.controller.get_light_name(light)
        current_state = self.controller.get_light_state(light)
        current_brightness = self.controller.get_light_brightness(light)

        with st.container():
            col1, col2, col3 = st.columns([3, 1, 1])

            with col1:
                st.write(f"💡 **{light_name}**")

            with col2:
                status = "🟢" if current_state else "⚫"
                st.write(status)

            with col3:
                button_text = "Turn Off" if current_state else "Turn On"
                if st.button(button_text, key=f"toggle_{light.id}"):
                    success = self.controller.control_light(
                        light,
                        not current_state,
                        st.session_state.transition_time
                    )
                    if success:
                        st.rerun()
                    else:
                        st.error("Failed to control light")

            # Brightness control
            if current_state:
                brightness = st.slider(
                    f"Brightness for {light_name}",
                    min_value=1,
                    max_value=100,
                    value=current_brightness,
                    key=f"brightness_{light.id}"
                )

                if brightness != current_brightness:
                    success = self.controller.set_light_brightness(
                        light, brightness, st.session_state.transition_time
                    )
                    if not success:
                        st.error("Failed to set brightness")

            # Advanced color controls
            if st.session_state.show_advanced and current_state:
                color_info = self.controller.get_light_color_info(light)

                if color_info.get("supports_color"):
                    color = st.color_picker(
                        f"Color for {light_name}",
                        value="#FFFFFF",
                        key=f"color_{light.id}"
                    )

                    if st.button(f"Apply Color", key=f"apply_color_{light.id}"):
                        success = self.controller.set_light_color(
                            light, color, st.session_state.transition_time
                        )
                        if success:
                            st.rerun()
                        else:
                            st.error("Failed to set color")

            st.divider()

    def _render_bridge_info_tab(self, lights: List[Light], groups: List[Union[Room, Zone]]) -> None:
        """Render bridge information tab."""
        if not self.controller:
            return

        bridge_info = self.controller.get_bridge_info()

        col1, col2 = st.columns(2)

        with col1:
            st.subheader("🌉 Bridge Information")
            if bridge_info:
                for key, value in bridge_info.items():
                    st.write(f"**{key.replace('_', ' ').title()}:** {value}")
            else:
                st.warning("Bridge information unavailable")

        with col2:
            st.subheader("📊 Statistics")
            st.metric("Total Lights", len(lights))
            st.metric("Total Groups", len(groups))

            lights_on = sum(1 for light in lights if self.controller.get_light_state(light))
            st.metric("Lights On", lights_on)

        # Connection test
        st.subheader("🔧 Diagnostics")
        if st.button("🧪 Test Connection"):
            try:
                test_lights = self.controller.get_lights()
                st.success(f"✅ Connection successful! Found {len(test_lights)} lights.")
            except Exception as e:
                st.error(f"❌ Connection failed: {e}")


def main() -> None:
    """Main entry point for the modernized Hue application."""
    try:
        logger.info(f"Modern Hue App started at {datetime.now().isoformat()}")
        app = HueApp()
        app.main()
    except KeyboardInterrupt:
        logger.info("Application interrupted by user")
    except Exception as e:
        logger.error(f"Application error: {e}")
        console.print(f"[red]Error: {e}[/red]")
    finally:
        logger.info("Application shutdown")


if __name__ == "__main__":
    main()