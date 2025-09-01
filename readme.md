# Hue Lights Control Panel

A modern Streamlit-based control panel for Philips Hue smart lights with auto-discovery, real-time controls, and advanced features.

## Features

- 🔍 **Auto-discovery** of Hue bridges on your network
- 💡 **Individual light control** with brightness and color settings
- 🏠 **Room/Zone management** for controlling groups of lights
- 🎨 **Color controls** with hex color picker and temperature adjustment
- ⚡ **Real-time updates** with configurable refresh intervals
- 🔒 **Secure credential storage** with base64 encoding
- 📊 **Bridge diagnostics** and connection testing

## Installation

This project uses [uv](https://docs.astral.sh/uv/) for fast Python package management.

### Prerequisites

1. Install uv:
   ```bash
   # On Windows (PowerShell)
   powershell -ExecutionPolicy ByPass -c "irm https://astral.sh/uv/install.ps1 | iex"
   
   # On macOS/Linux
   curl -LsSf https://astral.sh/uv/install.sh | sh
   ```

2. Make sure you have Python 3.8+ installed

### Setup

1. Clone this repository:
   ```bash
   git clone <repository-url>
   cd huelights
   ```

2. Install dependencies using uv:
   ```bash
   uv sync
   ```

3. Run the application:
   ```bash
   # Option 1: Using uv (recommended)
   uv run streamlit run hue_app.py
   
   # Option 2: Using the provided scripts
   # On Windows:
   start.bat
   
   # On macOS/Linux:
   ./start.sh
   
   # Option 3: Using the installed script
   uv run huelights
   ```

## Usage

1. **Bridge Setup**: On first run, the app will discover Hue bridges on your network
2. **Authentication**: Press the physical button on your Hue bridge when prompted
3. **Control**: Use the web interface to control individual lights or room groups
4. **Settings**: Adjust refresh intervals, transition times, and enable advanced controls in the sidebar

## Development

To add new dependencies:
```bash
uv add <package-name>
```

To add development dependencies:
```bash
uv add --dev <package-name>
```

To update dependencies:
```bash
uv lock --upgrade
```

## Project Structure

```
huelights/
├── hue_app.py          # Main Streamlit application
├── pyproject.toml      # Project configuration and dependencies
├── uv.lock            # Lockfile for reproducible installs
├── creds/             # Encrypted bridge credentials
├── logs/              # Application logs
└── confetti/          # Additional features (light shows, etc.)
```

## Requirements

- Python 3.8+
- Philips Hue Bridge (v2 recommended)
- Network connectivity to bridge
- Modern web browser for Streamlit interface

## Original Reference

- Hue Bridge Discovery: https://discovery.meethue.com/
- Example bridge response:
  ```json
  [
      {
          "id": "ecb5fafffea43228",
          "internalipaddress": "192.168.7.213",
          "port": 443
      }
  ]
  ```