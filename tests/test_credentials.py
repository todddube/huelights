"""Tests for HueCredentials class."""

import json
import tempfile
from pathlib import Path
from unittest.mock import AsyncMock, patch

import pytest

from hue_app_modern import BridgeCredentials, HueCredentials


class TestBridgeCredentials:
    """Test the BridgeCredentials Pydantic model."""

    def test_valid_credentials(self):
        """Test creation of valid credentials."""
        creds = BridgeCredentials(
            bridge_ip="192.168.1.100",
            bridge_username="abcdef1234567890abcdef1234567890abcdef12"
        )
        assert creds.bridge_ip == "192.168.1.100"
        assert creds.bridge_username == "abcdef1234567890abcdef1234567890abcdef12"
        assert creds.version == "2.0"

    def test_invalid_ip_address(self):
        """Test validation of invalid IP addresses."""
        with pytest.raises(ValueError):
            BridgeCredentials(
                bridge_ip="300.168.1.100",  # Invalid octet
                bridge_username="abcdef1234567890abcdef1234567890abcdef12"
            )

        with pytest.raises(ValueError):
            BridgeCredentials(
                bridge_ip="not.an.ip.address",
                bridge_username="abcdef1234567890abcdef1234567890abcdef12"
            )

    def test_invalid_username_length(self):
        """Test validation of username length."""
        with pytest.raises(ValueError):
            BridgeCredentials(
                bridge_ip="192.168.1.100",
                bridge_username="short"  # Too short
            )

        with pytest.raises(ValueError):
            BridgeCredentials(
                bridge_ip="192.168.1.100",
                bridge_username="x" * 60  # Too long
            )


class TestHueCredentials:
    """Test the HueCredentials class."""

    def test_save_and_load_credentials(self):
        """Test saving and loading credentials."""
        with tempfile.TemporaryDirectory() as temp_dir:
            filepath = Path(temp_dir) / "test_creds.json"
            creds = HueCredentials(str(filepath))

            # Save credentials
            test_ip = "192.168.1.100"
            test_username = "abcdef1234567890abcdef1234567890abcdef12"
            creds.save(test_ip, test_username)

            # Verify file exists and has correct structure
            assert filepath.exists()

            with filepath.open() as f:
                data = json.load(f)

            assert "bridge_ip" in data
            assert "bridge_username" in data
            assert "created_at" in data
            assert "version" in data

            # Load credentials back
            loaded_ip, loaded_username = creds.load()
            assert loaded_ip == test_ip
            assert loaded_username == test_username

    def test_load_nonexistent_file(self):
        """Test loading from non-existent file."""
        with tempfile.TemporaryDirectory() as temp_dir:
            filepath = Path(temp_dir) / "nonexistent.json"
            creds = HueCredentials(str(filepath))

            ip, username = creds.load()
            assert ip is None
            assert username is None

    def test_load_corrupted_file(self):
        """Test loading from corrupted file."""
        with tempfile.TemporaryDirectory() as temp_dir:
            filepath = Path(temp_dir) / "corrupted.json"
            creds = HueCredentials(str(filepath))

            # Create corrupted file
            with filepath.open("w") as f:
                f.write("invalid json content")

            ip, username = creds.load()
            assert ip is None
            assert username is None

    @pytest.mark.asyncio
    async def test_is_valid_async_success(self):
        """Test async credential validation success."""
        with tempfile.TemporaryDirectory() as temp_dir:
            filepath = Path(temp_dir) / "test_creds.json"
            creds = HueCredentials(str(filepath))

            # Save valid credentials
            creds.save("192.168.1.100", "abcdef1234567890abcdef1234567890abcdef12")

            with patch("hue_app_modern.HueBridgeV2Client") as mock_bridge_class:
                mock_bridge = AsyncMock()
                mock_bridge_class.return_value = mock_bridge
                mock_bridge.initialize.return_value = None

                with patch("httpx.AsyncClient"):
                    result = await creds.is_valid_async()

                assert result is True
                mock_bridge.initialize.assert_called_once()

    @pytest.mark.asyncio
    async def test_is_valid_async_failure(self):
        """Test async credential validation failure."""
        with tempfile.TemporaryDirectory() as temp_dir:
            filepath = Path(temp_dir) / "test_creds.json"
            creds = HueCredentials(str(filepath))

            # Save valid credentials
            creds.save("192.168.1.100", "abcdef1234567890abcdef1234567890abcdef12")

            with patch("hue_app_modern.HueBridgeV2Client") as mock_bridge_class:
                mock_bridge = AsyncMock()
                mock_bridge_class.return_value = mock_bridge
                mock_bridge.initialize.side_effect = Exception("Connection failed")

                with patch("httpx.AsyncClient"):
                    result = await creds.is_valid_async()

                assert result is False

    @pytest.mark.asyncio
    async def test_is_valid_async_no_credentials(self):
        """Test async validation with no credentials."""
        with tempfile.TemporaryDirectory() as temp_dir:
            filepath = Path(temp_dir) / "nonexistent.json"
            creds = HueCredentials(str(filepath))

            result = await creds.is_valid_async()
            assert result is False

    def test_is_valid_sync_wrapper(self):
        """Test synchronous validation wrapper."""
        with tempfile.TemporaryDirectory() as temp_dir:
            filepath = Path(temp_dir) / "nonexistent.json"
            creds = HueCredentials(str(filepath))

            result = creds.is_valid()
            assert result is False

    def test_save_invalid_credentials(self):
        """Test saving invalid credentials raises validation error."""
        with tempfile.TemporaryDirectory() as temp_dir:
            filepath = Path(temp_dir) / "test_creds.json"
            creds = HueCredentials(str(filepath))

            with pytest.raises(ValueError):
                creds.save("invalid.ip", "short_username")