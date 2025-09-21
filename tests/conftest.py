"""Pytest configuration and fixtures for Hue app tests."""

import asyncio
from pathlib import Path
from unittest.mock import MagicMock

import pytest


@pytest.fixture(scope="session")
def event_loop():
    """Create an instance of the default event loop for the test session."""
    loop = asyncio.get_event_loop_policy().new_event_loop()
    yield loop
    loop.close()


@pytest.fixture
def mock_light():
    """Create a mock light object for testing."""
    light = MagicMock()
    light.id = "test_light_id"
    light.metadata.name = "Test Light"
    light.on.on = True
    light.dimming.brightness = 50
    light.color.xy.x = 0.3
    light.color.xy.y = 0.3
    light.color_temperature.mirek = 300
    return light


@pytest.fixture
def mock_room():
    """Create a mock room object for testing."""
    room = MagicMock()
    room.id = "test_room_id"
    room.metadata.name = "Test Room"
    room.children = ["light1", "light2"]
    room.on.on = True
    return room


@pytest.fixture
def mock_bridge():
    """Create a mock bridge object for testing."""
    bridge = MagicMock()
    bridge.lights.values.return_value = []
    bridge.rooms.values.return_value = []
    bridge.zones.values.return_value = []
    bridge.bridge.name = "Test Bridge"
    bridge.bridge.id = "test_bridge_id"
    bridge.bridge.bridge_id = "test_bridge_id"
    bridge.bridge.software_version = "1.0.0"
    bridge.bridge.model_id = "BSB002"
    return bridge


@pytest.fixture
def temp_creds_file(tmp_path):
    """Create a temporary credentials file for testing."""
    creds_dir = tmp_path / "creds"
    creds_dir.mkdir()
    return str(creds_dir / "test_credentials.json")


@pytest.fixture
def sample_bridge_data():
    """Sample bridge data for testing discovery."""
    return {
        "internalipaddress": "192.168.1.100",
        "id": "test_bridge_id",
        "bridgeid": "test_bridge_id",
        "name": "Test Bridge",
        "modelid": "BSB002"
    }


@pytest.fixture(autouse=True)
def setup_logging():
    """Setup logging for tests."""
    # Disable loguru during tests to reduce noise
    from loguru import logger
    logger.disable("hue_app_modern")
    yield
    logger.enable("hue_app_modern")


@pytest.fixture
def mock_streamlit():
    """Mock Streamlit for testing UI components."""
    with pytest.MonkeyPatch.context() as m:
        # Mock streamlit module
        st_mock = MagicMock()
        m.setattr("streamlit", st_mock)

        # Mock session state
        st_mock.session_state = {}

        # Mock common streamlit functions
        st_mock.set_page_config.return_value = None
        st_mock.title.return_value = None
        st_mock.sidebar.return_value = MagicMock()
        st_mock.button.return_value = False
        st_mock.checkbox.return_value = False
        st_mock.slider.return_value = 50
        st_mock.columns.return_value = [MagicMock(), MagicMock()]
        st_mock.tabs.return_value = [MagicMock(), MagicMock(), MagicMock()]

        yield st_mock