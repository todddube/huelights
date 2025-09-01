# 🌈 Hue Front Room Startup Scripts

This enhanced Hue lighting system includes automated startup scripts that can randomly light up your front room with beautiful color effects.

## ✨ Features

### Enhanced Hue App
- **Latest aiohue 4.7.4** integration with improved async patterns
- **Advanced color generation** using proper color science and XY color space
- **Random lighting effects**: Rainbow, Random, Warm, Cool, and Party Mode
- **Room-specific controls** for targeted lighting effects
- **Enhanced color conversion** from RGB/Hex to Philips Hue XY coordinates
- **Batch lighting operations** for smooth synchronized effects

### Startup Script Features
- **Automatic front room detection** using common room name patterns
- **Multi-phase light show** with rainbow startup and color cycling
- **Customizable duration** and room targeting
- **Quick mode** for instant random lighting
- **Graceful interruption** handling with restore to warm white
- **Cross-platform support** (Windows/Linux/macOS)

## 🚀 Quick Start

### 1. Install Dependencies
Make sure you have the required packages:
```bash
uv sync
# OR if not using uv:
pip install aiohue==4.7.4 streamlit aiohttp requests
```

### 2. Set Up Bridge Connection
First run the main app to configure your bridge:
```bash
uv run streamlit run hue_app.py
# OR
streamlit run hue_app.py
```

### 3. Run Startup Effects

#### Windows
```batch
# Full light show (30 seconds)
startup_lights.bat

# Quick random lighting
startup_lights.bat --quick

# Target specific room
startup_lights.bat --room "Living Room" --duration 60

# List available rooms
startup_lights.bat --list-rooms
```

#### Linux/macOS
```bash
# Full light show (30 seconds)
./startup_lights.sh

# Quick random lighting  
./startup_lights.sh --quick

# Target specific room
./startup_lights.sh --room "Living Room" --duration 60

# List available rooms
./startup_lights.sh --list-rooms
```

#### Direct Python
```bash
# Full light show
python front_room_startup.py

# Quick mode
python front_room_startup.py --quick

# Custom duration
python front_room_startup.py --duration 45

# Specific room
python front_room_startup.py --room "Front Room"
```

## 🎨 Light Show Phases

### Phase 1: Rainbow Startup (8 seconds)
- All lights turn on with coordinated rainbow colors
- High brightness (90%) for dramatic effect
- Smooth 5-second transitions

### Phase 2: Color Cycling (Variable duration)
- Cycles through warm, cool, and random color patterns
- 6 seconds per pattern
- Medium brightness (80%) for comfortable viewing

### Phase 3: Warm White Settling (Final)
- Settles to comfortable warm white lighting
- Lower brightness (60%) for normal use
- 10-second smooth transition

## 🏠 Room Detection

The script automatically detects your front room using these keywords:
- `front`, `living`, `lounge`, `main`, `sitting`
- `family`, `reception`, `parlor`, `salon`

If no match is found, it uses the first available room/zone.

## ⚙️ Configuration Options

### Command Line Arguments
- `--room "Name"`: Target specific room
- `--duration 60`: Set light show duration in seconds
- `--quick`: Skip full show, apply instant random colors
- `--list-rooms`: List all available rooms and exit

### Customization
Edit `front_room_startup.py` to customize:
- Room detection keywords
- Color patterns and transitions
- Brightness levels
- Effect timing

## 🔧 Advanced Usage

### Startup Integration
You can integrate these scripts with your system startup:

#### Windows Startup Folder
1. Press `Win + R`, type `shell:startup`
2. Create a shortcut to `startup_lights.bat`
3. Lights will activate on every boot

#### Linux/macOS Cron
```bash
# Add to crontab for daily 7 AM activation
crontab -e
# Add: 0 7 * * * /path/to/huelights/startup_lights.sh --quick
```

#### Home Assistant Integration
```yaml
script:
  hue_startup:
    sequence:
      - service: shell_command.hue_startup
        
shell_command:
  hue_startup: "cd /path/to/huelights && ./startup_lights.sh --quick"
```

## 🌈 Color Science

The enhanced app uses proper color science for accurate Hue lighting:

- **Gamma correction** for natural color perception
- **XYZ color space** conversion for accurate hue reproduction
- **Color gamut clamping** to ensure valid Hue colors
- **HSV-based generation** for vibrant, appealing random colors

### Color Effect Types
- **Rainbow**: Evenly distributed hues across the spectrum
- **Random**: Fully random but vibrant colors (avoided pale/dim)
- **Warm**: Reds, oranges, yellows (cozy atmosphere)
- **Cool**: Blues, greens, purples (energizing atmosphere)
- **Party Mode**: High brightness random colors on all lights

## 📝 Logging

Check logs for troubleshooting:
- Main app logs: `logs/hue_app.log`
- Startup script logs: `logs/startup.log`

## 🔍 Troubleshooting

### "No valid credentials found"
Run the main Streamlit app first to configure your bridge connection.

### "Could not find front room"  
Use `--list-rooms` to see available rooms, then specify with `--room "Name"`.

### Script hangs or fails
Check your network connection and bridge status. Press Ctrl+C to interrupt and restore warm white lighting.

### Lights don't change colors
Ensure your lights support color (not just white/dimming). Check bridge API version compatibility.

## 🎯 Tips for Best Results

1. **First Run**: Always test with `--quick` mode first
2. **Room Names**: Use exact room names from `--list-rooms`
3. **Network**: Ensure stable WiFi connection to bridge
4. **Light Types**: Color effects work best with color-capable bulbs
5. **Timing**: Avoid running during bridge firmware updates

Enjoy your automated Hue lighting experience! 🌟