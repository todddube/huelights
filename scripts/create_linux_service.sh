#!/bin/bash
# Create systemd service for Modern Hue Control Panel

set -e

# Get current directory and user
CURRENT_DIR="$(pwd)"
CURRENT_USER="$(whoami)"
PYTHON_PATH="$(which python)"

# Check if we're in a virtual environment
if [[ -n "$VIRTUAL_ENV" ]]; then
    PYTHON_PATH="$VIRTUAL_ENV/bin/python"
elif [[ -f ".venv/bin/python" ]]; then
    PYTHON_PATH="$CURRENT_DIR/.venv/bin/python"
fi

echo "🐧 Creating systemd service for Modern Hue Control Panel..."
echo "   User: $CURRENT_USER"
echo "   Directory: $CURRENT_DIR"
echo "   Python: $PYTHON_PATH"

# Create the service file
sudo tee /etc/systemd/system/hue-control.service > /dev/null <<EOF
[Unit]
Description=Modern Hue Control Panel
After=network.target
Wants=network.target

[Service]
Type=simple
User=$CURRENT_USER
Group=$CURRENT_USER
WorkingDirectory=$CURRENT_DIR
Environment=PATH=$CURRENT_DIR/.venv/bin:/usr/local/bin:/usr/bin:/bin
ExecStart=$PYTHON_PATH start_modern.py run --host 0.0.0.0 --port 8501
Restart=always
RestartSec=10
StandardOutput=journal
StandardError=journal
SyslogIdentifier=hue-control

# Security settings
NoNewPrivileges=true
PrivateTmp=true
ProtectSystem=strict
ProtectHome=read-only
ReadWritePaths=$CURRENT_DIR/logs $CURRENT_DIR/creds

[Install]
WantedBy=multi-user.target
EOF

# Reload systemd and enable the service
sudo systemctl daemon-reload
sudo systemctl enable hue-control.service

echo "✅ Service created and enabled!"
echo ""
echo "🚀 To start the service:"
echo "   sudo systemctl start hue-control"
echo ""
echo "📊 To check status:"
echo "   sudo systemctl status hue-control"
echo ""
echo "📝 To view logs:"
echo "   sudo journalctl -u hue-control -f"
echo ""
echo "🛑 To stop the service:"
echo "   sudo systemctl stop hue-control"