#!/bin/bash
# Hue Front Room Startup Script for Unix/Linux/macOS
# This script runs the front room lighting startup script

echo "🌈 Starting Hue Front Room Lighting..."
echo "======================================"

# Change to script directory
cd "$(dirname "$0")"

# Check if uv is available, otherwise use python directly
if command -v uv &> /dev/null; then
    echo "Using uv to run startup script..."
    uv run python front_room_startup.py "$@"
elif command -v python3 &> /dev/null; then
    echo "Using python3 to run startup script..."
    python3 front_room_startup.py "$@"
elif command -v python &> /dev/null; then
    echo "Using python to run startup script..."
    python front_room_startup.py "$@"
else
    echo "❌ Error: Python not found!"
    echo "Please install Python or uv to run this script."
    exit 1
fi

if [ $? -ne 0 ]; then
    echo ""
    echo "❌ Error occurred! Check the logs for details."
    read -p "Press Enter to exit..." -r
else
    echo ""
    echo "✅ Startup complete! Lights should now be active."
    sleep 3
fi