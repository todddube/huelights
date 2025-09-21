#!/bin/bash
# Create LaunchAgent for Modern Hue Control Panel on macOS

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

# LaunchAgents directory
LAUNCH_AGENTS_DIR="$HOME/Library/LaunchAgents"
PLIST_FILE="$LAUNCH_AGENTS_DIR/com.hue.control.plist"

echo "🍎 Creating macOS LaunchAgent for Modern Hue Control Panel..."
echo "   User: $CURRENT_USER"
echo "   Directory: $CURRENT_DIR"
echo "   Python: $PYTHON_PATH"

# Create LaunchAgents directory if it doesn't exist
mkdir -p "$LAUNCH_AGENTS_DIR"

# Create the plist file
cat > "$PLIST_FILE" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>com.hue.control</string>

    <key>ProgramArguments</key>
    <array>
        <string>$PYTHON_PATH</string>
        <string>start_modern.py</string>
        <string>run</string>
        <string>--host</string>
        <string>0.0.0.0</string>
        <string>--port</string>
        <string>8501</string>
    </array>

    <key>WorkingDirectory</key>
    <string>$CURRENT_DIR</string>

    <key>EnvironmentVariables</key>
    <dict>
        <key>PATH</key>
        <string>$CURRENT_DIR/.venv/bin:/usr/local/bin:/usr/bin:/bin</string>
    </dict>

    <key>RunAtLoad</key>
    <true/>

    <key>KeepAlive</key>
    <dict>
        <key>SuccessfulExit</key>
        <false/>
    </dict>

    <key>StandardOutPath</key>
    <string>$CURRENT_DIR/logs/hue-control.out.log</string>

    <key>StandardErrorPath</key>
    <string>$CURRENT_DIR/logs/hue-control.err.log</string>

    <key>ThrottleInterval</key>
    <integer>10</integer>
</dict>
</plist>
EOF

# Set proper permissions
chmod 644 "$PLIST_FILE"

# Create logs directory if it doesn't exist
mkdir -p "$CURRENT_DIR/logs"

echo "✅ LaunchAgent created!"
echo ""
echo "🚀 To start the service:"
echo "   launchctl load $PLIST_FILE"
echo ""
echo "🛑 To stop the service:"
echo "   launchctl unload $PLIST_FILE"
echo ""
echo "📊 To check if running:"
echo "   launchctl list | grep com.hue.control"
echo ""
echo "📝 To view logs:"
echo "   tail -f $CURRENT_DIR/logs/hue-control.out.log"
echo "   tail -f $CURRENT_DIR/logs/hue-control.err.log"
echo ""
echo "🔄 The service will automatically start on login and restart if it crashes."