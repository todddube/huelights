# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

This is a Philips Hue Control Panel built with Streamlit, providing a modern web interface for controlling Hue smart lights. The application features auto-discovery, real-time controls, room/zone management, and advanced color controls.

## Architecture

The codebase follows a single-file architecture with modular classes:

- **HueCredentials** (`hue_app.py:45-103`): Manages secure credential storage with base64 encoding
- **HueBridgeDiscovery** (`hue_app.py:105-187`): Auto-discovery using aiohue and network scanning fallback
- **HueController** (`hue_app.py:189-485`): Core API interface with caching and async operations using aiohue v4.7+
- **HueApp** (`hue_app.py:487-1042`): Main Streamlit application with UI components

## Key Commands

### Development
```bash
# Install dependencies
uv sync

# Run application
uv run streamlit run hue_app.py
# OR use provided scripts:
start.bat          # Windows
./start.sh         # Unix/macOS

# Add new dependencies
uv add <package-name>

# Update dependencies
uv lock --upgrade
```

### Testing
No formal test suite is implemented. Testing is done through:
- Bridge connection diagnostics in the UI
- Manual testing of light controls
- Connection validation in HueCredentials.is_valid()

## Important Implementation Details

### Async Operations
The codebase uses asyncio extensively through aiohue library:
- All bridge operations are wrapped in `asyncio.run()` calls
- Session management handled automatically in HueController
- Proper cleanup in `__del__` method (`hue_app.py:479-485`)

### Caching Strategy
HueController implements time-based caching (2-second TTL):
- Light states cached to reduce API calls
- Cache invalidation on state changes
- Manual cache clearing available in UI

### Bridge Discovery
Two-tier discovery approach:
1. aiohue automatic discovery (primary)
2. Network scanning fallback (192.168.x.x range)

### Credential Security
- Base64 encoding for stored credentials (not encryption)
- Credentials stored in `creds/hue_credentials.json`
- 30-second bridge button timeout for initial setup

## Dependencies

Core dependencies (managed via uv):
- streamlit>=1.28.0 (UI framework)
- aiohue>=4.7.0 (Hue API v2 client)
- aiohttp>=3.8.0 (async HTTP client)
- requests>=2.31.0 (fallback HTTP client)

## Directory Structure

```
├── hue_app.py              # Main application (single file)
├── pyproject.toml          # uv project configuration
├── start.bat/start.sh      # Launch scripts
├── creds/                  # Bridge credentials (gitignored)
├── logs/                   # Application logs
└── venv/                   # uv virtual environment
```

## Common Development Patterns

### Adding New Light Controls
1. Extend HueController with new control method
2. Add UI component in render_light_controls()
3. Use transition time from session state
4. Invalidate relevant cache entries

### Bridge Communication
Always use async patterns:
```python
async def operation_async():
    await self.bridge.lights.set_state(light.id, **update_data)
result = asyncio.run(operation_async())
```

### State Management
Streamlit session state is used for:
- Polling intervals and auto-refresh settings
- UI state (advanced controls, discovered bridges)
- Transition timing preferences