#!/bin/bash
# Hue Lights Control Panel - Start Script
# This script starts the Streamlit application using uv

echo "Starting Hue Lights Control Panel..."
echo ""
echo "Opening in your default browser..."
echo "Press Ctrl+C to stop the application"
echo ""

cd "$(dirname "$0")"
uv run streamlit run hue_app.py
