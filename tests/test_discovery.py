"""Tests for HueBridgeDiscovery class."""

from unittest.mock import AsyncMock, MagicMock, patch

import pytest

from hue_app_modern import DiscoveredBridge, HueBridgeDiscovery


class TestDiscoveredBridge:
    """Test the DiscoveredBridge dataclass."""

    def test_create_discovered_bridge(self):
        """Test creating a DiscoveredBridge instance."""
        bridge = DiscoveredBridge(
            method="test_method",
            ip="192.168.1.100",
            id="test_id",
            port="443",
            name="Test Bridge",
            model="BSB002"
        )

        assert bridge.method == "test_method"
        assert bridge.ip == "192.168.1.100"
        assert bridge.id == "test_id"
        assert bridge.port == "443"
        assert bridge.name == "Test Bridge"
        assert bridge.model == "BSB002"

    def test_create_bridge_without_optional_fields(self):
        """Test creating bridge without optional fields."""
        bridge = DiscoveredBridge(
            method="test_method",
            ip="192.168.1.100",
            id="test_id",
            port="443"
        )

        assert bridge.method == "test_method"
        assert bridge.ip == "192.168.1.100"
        assert bridge.id == "test_id"
        assert bridge.port == "443"
        assert bridge.name is None
        assert bridge.model is None


class TestHueBridgeDiscovery:
    """Test the HueBridgeDiscovery class."""

    def test_init(self):
        """Test discovery class initialization."""
        discovery = HueBridgeDiscovery()
        assert discovery._discovery_timeout == 10.0
        assert discovery._scan_timeout == 1.0

    @pytest.mark.asyncio
    async def test_discover_bridges_async_success(self):
        """Test successful bridge discovery."""
        discovery = HueBridgeDiscovery()

        # Mock discovered bridge
        mock_bridge = MagicMock()
        mock_bridge.host = "192.168.1.100"
        mock_bridge.id = "test_bridge_id"
        mock_bridge.port = 443
        mock_bridge.name = "Test Bridge"

        with patch("hue_app_modern.discover_bridge") as mock_discover:
            mock_discover.return_value = [mock_bridge]

            with patch("httpx.AsyncClient"):
                bridges = await discovery.discover_bridges_async()

            assert len(bridges) == 1
            bridge = bridges[0]
            assert bridge.method == "aiohue_discovery"
            assert bridge.ip == "192.168.1.100"
            assert bridge.id == "test_bridge_id"
            assert bridge.port == "443"

    @pytest.mark.asyncio
    async def test_discover_bridges_async_fallback_to_ssdp(self):
        """Test fallback to SSDP discovery."""
        discovery = HueBridgeDiscovery()

        # Mock failed aiohue discovery, successful SSDP
        with patch("hue_app_modern.discover_bridge") as mock_discover:
            mock_discover.side_effect = Exception("Discovery failed")

            with patch.object(discovery, "_ssdp_discovery") as mock_ssdp:
                mock_ssdp.return_value = [
                    DiscoveredBridge(
                        method="meethue_discovery",
                        ip="192.168.1.100",
                        id="test_id",
                        port="443"
                    )
                ]

                with patch.object(discovery, "_network_scan_async") as mock_scan:
                    mock_scan.return_value = []

                    bridges = await discovery.discover_bridges_async()

            assert len(bridges) == 1
            assert bridges[0].method == "meethue_discovery"

    @pytest.mark.asyncio
    async def test_discover_bridges_async_fallback_to_scan(self):
        """Test fallback to network scan."""
        discovery = HueBridgeDiscovery()

        # Mock failed aiohue and SSDP, successful scan
        with patch("hue_app_modern.discover_bridge") as mock_discover:
            mock_discover.side_effect = Exception("Discovery failed")

            with patch.object(discovery, "_ssdp_discovery") as mock_ssdp:
                mock_ssdp.return_value = []

                with patch.object(discovery, "_network_scan_async") as mock_scan:
                    mock_scan.return_value = [
                        DiscoveredBridge(
                            method="network_scan",
                            ip="192.168.1.100",
                            id="test_id",
                            port="80"
                        )
                    ]

                    bridges = await discovery.discover_bridges_async()

            assert len(bridges) == 1
            assert bridges[0].method == "network_scan"

    @pytest.mark.asyncio
    async def test_ssdp_discovery_success(self):
        """Test successful SSDP discovery."""
        discovery = HueBridgeDiscovery()

        mock_response = AsyncMock()
        mock_response.status_code = 200
        mock_response.json.return_value = [
            {
                "internalipaddress": "192.168.1.100",
                "id": "test_bridge_id"
            }
        ]

        with patch("httpx.AsyncClient") as mock_client_class:
            mock_client = AsyncMock()
            mock_client_class.return_value.__aenter__.return_value = mock_client
            mock_client.get.return_value = mock_response

            bridges = await discovery._ssdp_discovery()

        assert len(bridges) == 1
        bridge = bridges[0]
        assert bridge.method == "meethue_discovery"
        assert bridge.ip == "192.168.1.100"
        assert bridge.id == "test_bridge_id"
        assert bridge.port == "443"

    @pytest.mark.asyncio
    async def test_ssdp_discovery_failure(self):
        """Test SSDP discovery failure."""
        discovery = HueBridgeDiscovery()

        with patch("httpx.AsyncClient") as mock_client_class:
            mock_client = AsyncMock()
            mock_client_class.return_value.__aenter__.return_value = mock_client
            mock_client.get.side_effect = Exception("Request failed")

            bridges = await discovery._ssdp_discovery()

        assert len(bridges) == 0

    @pytest.mark.asyncio
    async def test_network_scan_async_success(self):
        """Test successful network scan."""
        discovery = HueBridgeDiscovery()

        # Mock socket to return local IP
        with patch("socket.gethostname") as mock_hostname:
            mock_hostname.return_value = "test_host"

            with patch("socket.gethostbyname") as mock_getbyname:
                mock_getbyname.return_value = "192.168.1.50"

                # Mock httpx client for bridge response
                mock_response = AsyncMock()
                mock_response.status_code = 200
                mock_response.json.return_value = {
                    "bridgeid": "test_bridge_id",
                    "name": "Test Bridge",
                    "modelid": "BSB002"
                }

                with patch("httpx.AsyncClient") as mock_client_class:
                    mock_client = AsyncMock()
                    mock_client_class.return_value.__aenter__.return_value = mock_client
                    mock_client.get.return_value = mock_response

                    # Mock asyncio.gather to simulate one successful response
                    with patch("asyncio.gather") as mock_gather:
                        mock_gather.return_value = [
                            DiscoveredBridge(
                                method="network_scan",
                                ip="192.168.1.100",
                                id="test_bridge_id",
                                port="80",
                                name="Test Bridge",
                                model="BSB002"
                            )
                        ] + [None] * 253  # Simulate other IPs returning None

                        bridges = await discovery._network_scan_async()

        assert len(bridges) == 1
        bridge = bridges[0]
        assert bridge.method == "network_scan"
        assert bridge.ip == "192.168.1.100"
        assert bridge.id == "test_bridge_id"

    @pytest.mark.asyncio
    async def test_network_scan_async_no_bridges(self):
        """Test network scan with no bridges found."""
        discovery = HueBridgeDiscovery()

        with patch("socket.gethostname") as mock_hostname:
            mock_hostname.return_value = "test_host"

            with patch("socket.gethostbyname") as mock_getbyname:
                mock_getbyname.return_value = "192.168.1.50"

                with patch("asyncio.gather") as mock_gather:
                    mock_gather.return_value = [None] * 254  # No bridges found

                    bridges = await discovery._network_scan_async()

        assert len(bridges) == 0

    def test_discover_bridges_sync_wrapper(self):
        """Test synchronous wrapper for discovery."""
        discovery = HueBridgeDiscovery()

        with patch.object(discovery, "discover_bridges_async") as mock_async:
            mock_async.return_value = [
                DiscoveredBridge(
                    method="test",
                    ip="192.168.1.100",
                    id="test_id",
                    port="443"
                )
            ]

            bridges = discovery.discover_bridges()

        assert len(bridges) == 1
        assert bridges[0].ip == "192.168.1.100"

    def test_discover_bridges_sync_wrapper_exception(self):
        """Test synchronous wrapper handling exceptions."""
        discovery = HueBridgeDiscovery()

        with patch("asyncio.run") as mock_run:
            mock_run.side_effect = Exception("Async error")

            bridges = discovery.discover_bridges()

        assert len(bridges) == 0

    @pytest.mark.asyncio
    async def test_duplicate_bridge_removal(self):
        """Test that duplicate bridges are removed."""
        discovery = HueBridgeDiscovery()

        # Mock discovery returning the same bridge from different methods
        mock_bridge = MagicMock()
        mock_bridge.host = "192.168.1.100"
        mock_bridge.id = "test_bridge_id"
        mock_bridge.port = 443

        with patch("hue_app_modern.discover_bridge") as mock_discover:
            mock_discover.return_value = [mock_bridge]

            with patch.object(discovery, "_ssdp_discovery") as mock_ssdp:
                mock_ssdp.return_value = [
                    DiscoveredBridge(
                        method="meethue_discovery",
                        ip="192.168.1.100",  # Same IP
                        id="different_id",
                        port="443"
                    )
                ]

                with patch("httpx.AsyncClient"):
                    bridges = await discovery.discover_bridges_async()

        # Should only have one bridge despite multiple discoveries
        assert len(bridges) == 1
        assert bridges[0].ip == "192.168.1.100"