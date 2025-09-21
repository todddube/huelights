"""Tests for HueController class."""

from unittest.mock import AsyncMock, MagicMock, patch

import pytest

from hue_app_modern import AppSettings, ColorXY, EffectType, HueController


class MockLight:
    """Mock light object for testing."""

    def __init__(self, light_id="test_light", name="Test Light", on=True, brightness=50):
        self.id = light_id
        self.metadata = MagicMock()
        self.metadata.name = name

        self.on = MagicMock()
        self.on.on = on

        self.dimming = MagicMock()
        self.dimming.brightness = brightness

        self.color = MagicMock()
        self.color.xy = MagicMock()
        self.color.xy.x = 0.3
        self.color.xy.y = 0.3

        self.color_temperature = MagicMock()
        self.color_temperature.mirek = 300


class MockRoom:
    """Mock room object for testing."""

    def __init__(self, room_id="test_room", name="Test Room"):
        self.id = room_id
        self.metadata = MagicMock()
        self.metadata.name = name
        self.children = ["light1", "light2"]

        self.on = MagicMock()
        self.on.on = True


class TestColorXY:
    """Test the ColorXY dataclass."""

    def test_default_white_point(self):
        """Test default white point values."""
        color = ColorXY()
        assert color.x == 0.3127
        assert color.y == 0.3290

    def test_custom_coordinates(self):
        """Test custom coordinates."""
        color = ColorXY(x=0.5, y=0.6)
        assert color.x == 0.5
        assert color.y == 0.6

    def test_coordinate_clamping(self):
        """Test that coordinates are clamped to valid range."""
        color = ColorXY(x=-0.1, y=1.5)
        assert color.x == 0.0
        assert color.y == 1.0

    def test_to_tuple(self):
        """Test conversion to tuple."""
        color = ColorXY(x=0.3, y=0.4)
        assert color.to_tuple() == (0.3, 0.4)


class TestHueController:
    """Test the HueController class."""

    def test_init(self):
        """Test controller initialization."""
        controller = HueController("192.168.1.100", "test_username")
        assert controller.bridge_ip == "192.168.1.100"
        assert controller.username == "test_username"
        assert isinstance(controller.settings, AppSettings)
        assert controller.bridge is None
        assert controller.client is None
        assert not controller._initialized

    def test_init_with_custom_settings(self):
        """Test initialization with custom settings."""
        settings = AppSettings(cache_duration=5, auto_refresh=False)
        controller = HueController("192.168.1.100", "test_username", settings)
        assert controller.settings.cache_duration == 5
        assert controller.settings.auto_refresh is False

    def test_cache_validation(self):
        """Test cache validation logic."""
        controller = HueController("192.168.1.100", "test_username")

        # No cache entry
        assert not controller._is_cache_valid("nonexistent")

        # Set cache entry
        controller._set_cache("test_key", "test_value")
        assert controller._is_cache_valid("test_key")
        assert controller._cache["test_key"] == "test_value"

    def test_clear_cache(self):
        """Test cache clearing."""
        controller = HueController("192.168.1.100", "test_username")

        controller._set_cache("test_key", "test_value")
        assert "test_key" in controller._cache

        controller.clear_cache()
        assert len(controller._cache) == 0
        assert len(controller._cache_expiry) == 0

    @pytest.mark.asyncio
    async def test_initialize_bridge_success(self):
        """Test successful bridge initialization."""
        controller = HueController("192.168.1.100", "test_username")

        with patch("httpx.AsyncClient") as mock_client_class:
            mock_client = AsyncMock()
            mock_client_class.return_value = mock_client

            with patch("hue_app_modern.HueBridgeV2Client") as mock_bridge_class:
                mock_bridge = AsyncMock()
                mock_bridge_class.return_value = mock_bridge

                await controller._initialize_bridge()

                assert controller._initialized is True
                assert controller.client is mock_client
                assert controller.bridge is mock_bridge
                mock_bridge.initialize.assert_called_once()

    @pytest.mark.asyncio
    async def test_initialize_bridge_failure(self):
        """Test bridge initialization failure."""
        controller = HueController("192.168.1.100", "test_username")

        with patch("httpx.AsyncClient") as mock_client_class:
            mock_client = AsyncMock()
            mock_client_class.return_value = mock_client

            with patch("hue_app_modern.HueBridgeV2Client") as mock_bridge_class:
                mock_bridge = AsyncMock()
                mock_bridge_class.return_value = mock_bridge
                mock_bridge.initialize.side_effect = Exception("Init failed")

                with pytest.raises(Exception):
                    await controller._initialize_bridge()

                assert controller._initialized is False
                mock_client.aclose.assert_called_once()

    @pytest.mark.asyncio
    async def test_get_lights_async_with_cache(self):
        """Test getting lights with cache hit."""
        controller = HueController("192.168.1.100", "test_username")

        # Set up cache
        mock_lights = [MockLight("light1"), MockLight("light2")]
        controller._set_cache("lights", mock_lights)

        lights = await controller.get_lights_async()
        assert lights == mock_lights

    @pytest.mark.asyncio
    async def test_get_lights_async_without_cache(self):
        """Test getting lights without cache."""
        controller = HueController("192.168.1.100", "test_username")

        mock_bridge = AsyncMock()
        mock_lights = [MockLight("light1"), MockLight("light2")]
        mock_bridge.lights.values.return_value = mock_lights

        with patch.object(controller, "_ensure_connection") as mock_connection:
            mock_connection.return_value.__aenter__.return_value = mock_bridge

            lights = await controller.get_lights_async(use_cache=False)

            assert lights == mock_lights
            assert controller._cache["lights"] == mock_lights

    def test_get_lights_sync_wrapper(self):
        """Test synchronous wrapper for get_lights."""
        controller = HueController("192.168.1.100", "test_username")

        mock_lights = [MockLight("light1")]

        with patch.object(controller, "get_lights_async") as mock_async:
            mock_async.return_value = mock_lights

            with patch("asyncio.run") as mock_run:
                mock_run.return_value = mock_lights

                lights = controller.get_lights()

                assert lights == mock_lights

    def test_get_lights_sync_wrapper_exception(self):
        """Test sync wrapper handling exceptions."""
        controller = HueController("192.168.1.100", "test_username")

        with patch("asyncio.run") as mock_run:
            mock_run.side_effect = Exception("Async error")

            lights = controller.get_lights()

            assert lights == []

    def test_get_light_state(self):
        """Test getting light state safely."""
        # Light that is on
        light_on = MockLight(on=True)
        assert HueController.get_light_state(light_on) is True

        # Light that is off
        light_off = MockLight(on=False)
        assert HueController.get_light_state(light_off) is False

        # Light with no state attribute
        light_broken = MagicMock()
        delattr(light_broken, 'on')
        assert HueController.get_light_state(light_broken) is False

    def test_get_light_brightness(self):
        """Test getting light brightness safely."""
        # Normal light
        light = MockLight(brightness=75)
        assert HueController.get_light_brightness(light) == 75

        # Light with no dimming
        light_no_dimming = MagicMock()
        delattr(light_no_dimming, 'dimming')
        assert HueController.get_light_brightness(light_no_dimming) == 0

        # Light with None brightness
        light_none_brightness = MockLight(brightness=None)
        assert HueController.get_light_brightness(light_none_brightness) == 0

    def test_get_light_name(self):
        """Test getting light name safely."""
        # Normal light
        light = MockLight(name="Test Light")
        assert HueController.get_light_name(light) == "Test Light"

        # Light with no metadata
        light_no_metadata = MagicMock()
        delattr(light_no_metadata, 'metadata')
        assert HueController.get_light_name(light_no_metadata) == "Unknown Light"

    def test_get_light_color_info(self):
        """Test getting light color information."""
        light = MockLight()
        color_info = HueController.get_light_color_info(light)

        assert "xy" in color_info
        assert "ct" in color_info
        assert "kelvin" in color_info
        assert "supports_color" in color_info
        assert "supports_temperature" in color_info

        # Test with light that has no color support
        light_no_color = MagicMock()
        delattr(light_no_color, 'color')
        delattr(light_no_color, 'color_temperature')
        color_info = HueController.get_light_color_info(light_no_color)

        assert color_info["supports_color"] is False
        assert color_info["supports_temperature"] is False

    def test_rgb_to_xy_conversion(self):
        """Test RGB to XY color conversion."""
        # Test pure red
        red_xy = HueController.rgb_to_xy(1.0, 0.0, 0.0)
        assert isinstance(red_xy, ColorXY)
        assert red_xy.x > 0.6  # Red should have high x value

        # Test pure white
        white_xy = HueController.rgb_to_xy(1.0, 1.0, 1.0)
        assert 0.3 < white_xy.x < 0.35  # White should be near white point
        assert 0.3 < white_xy.y < 0.35

        # Test black (edge case)
        black_xy = HueController.rgb_to_xy(0.0, 0.0, 0.0)
        assert black_xy.x == 0.3127  # Should default to white point
        assert black_xy.y == 0.3290

        # Test clamping
        clamped_xy = HueController.rgb_to_xy(-0.1, 1.5, 0.5)
        assert isinstance(clamped_xy, ColorXY)

    def test_generate_color_by_effect(self):
        """Test color generation by effect type."""
        # Test random effect
        random_color = HueController.generate_color_by_effect(EffectType.RANDOM, 0, 1)
        assert isinstance(random_color, ColorXY)

        # Test rainbow effect
        rainbow_color = HueController.generate_color_by_effect(EffectType.RAINBOW, 0, 4)
        assert isinstance(rainbow_color, ColorXY)

        # Test warm colors
        warm_color = HueController.generate_color_by_effect(EffectType.WARM, 0, 1)
        assert isinstance(warm_color, ColorXY)

        # Test cool colors
        cool_color = HueController.generate_color_by_effect(EffectType.COOL, 0, 1)
        assert isinstance(cool_color, ColorXY)

        # Test party colors
        party_color = HueController.generate_color_by_effect(EffectType.PARTY, 0, 1)
        assert isinstance(party_color, ColorXY)

        # Test invalid effect (should default to white)
        default_color = HueController.generate_color_by_effect("invalid", 0, 1)
        assert default_color.x == 0.3127
        assert default_color.y == 0.3290

    def test_generate_colors_for_lights(self):
        """Test generating colors for multiple lights."""
        lights = [MockLight("light1"), MockLight("light2"), MockLight("light3")]

        colors = HueController.generate_colors_for_lights(lights, EffectType.RAINBOW)

        assert len(colors) == 3
        assert "light1" in colors
        assert "light2" in colors
        assert "light3" in colors

        for light_id, color in colors.items():
            assert isinstance(color, ColorXY)

    @pytest.mark.asyncio
    async def test_control_light_async_success(self):
        """Test successful light control."""
        controller = HueController("192.168.1.100", "test_username")
        light = MockLight()

        mock_bridge = AsyncMock()

        with patch.object(controller, "_ensure_connection") as mock_connection:
            mock_connection.return_value.__aenter__.return_value = mock_bridge

            result = await controller.control_light_async(light, True, 5)

            assert result is True
            mock_bridge.lights.set_state.assert_called_once()

    @pytest.mark.asyncio
    async def test_control_light_async_failure(self):
        """Test failed light control."""
        controller = HueController("192.168.1.100", "test_username")
        light = MockLight()

        with patch.object(controller, "_ensure_connection") as mock_connection:
            mock_connection.return_value.__aenter__.return_value = None

            result = await controller.control_light_async(light, True, 5)

            assert result is False

    def test_control_light_sync_wrapper(self):
        """Test synchronous wrapper for light control."""
        controller = HueController("192.168.1.100", "test_username")
        light = MockLight()

        with patch.object(controller, "control_light_async") as mock_async:
            mock_async.return_value = True

            with patch("asyncio.run") as mock_run:
                mock_run.return_value = True

                result = controller.control_light(light, True, 5)

                assert result is True

    @pytest.mark.asyncio
    async def test_cleanup(self):
        """Test resource cleanup."""
        controller = HueController("192.168.1.100", "test_username")

        mock_client = AsyncMock()
        controller.client = mock_client
        controller._initialized = True

        await controller.cleanup()

        mock_client.aclose.assert_called_once()
        assert controller.client is None
        assert controller.bridge is None
        assert controller._initialized is False

    def test_destructor(self):
        """Test destructor cleanup."""
        controller = HueController("192.168.1.100", "test_username")

        mock_client = MagicMock()
        mock_client.is_closed = False
        controller.client = mock_client

        with patch("asyncio.run") as mock_run:
            controller.__del__()
            mock_run.assert_called_once()

    def test_destructor_with_closed_client(self):
        """Test destructor with already closed client."""
        controller = HueController("192.168.1.100", "test_username")

        mock_client = MagicMock()
        mock_client.is_closed = True
        controller.client = mock_client

        with patch("asyncio.run") as mock_run:
            controller.__del__()
            mock_run.assert_not_called()