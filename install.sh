#!/bin/bash
set -euo pipefail

BINARY_NAME="FlyBy"
BUNDLE_ID="com.$(whoami).flyby"
PLIST_PATH="$HOME/Library/LaunchAgents/$BUNDLE_ID.plist"
INSTALL_DIR="$HOME/.local/bin"
BINARY_PATH="$INSTALL_DIR/$BINARY_NAME"

echo "Building release binary..."
swift build -c release

echo "Installing binary to $INSTALL_DIR..."
mkdir -p "$INSTALL_DIR"
cp ".build/arm64-apple-macosx/release/$BINARY_NAME" "$BINARY_PATH"

echo "Writing LaunchAgent plist to $PLIST_PATH..."
mkdir -p "$HOME/Library/LaunchAgents"
cat > "$PLIST_PATH" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>$BUNDLE_ID</string>
    <key>ProgramArguments</key>
    <array>
        <string>$BINARY_PATH</string>
    </array>
    <key>EnvironmentVariables</key>
    <dict>
        <key>PATH</key>
        <string>/usr/local/bin:/usr/bin:/bin:$HOME/.local/bin</string>
    </dict>
    <key>RunAtLoad</key>
    <true/>
    <key>KeepAlive</key>
    <false/>
    <key>StandardOutPath</key>
    <string>/tmp/flyby.log</string>
    <key>StandardErrorPath</key>
    <string>/tmp/flyby.log</string>
</dict>
</plist>
EOF

echo "Loading LaunchAgent..."
launchctl unload "$PLIST_PATH" 2>/dev/null || true
launchctl load "$PLIST_PATH"

echo "Done! FlyBy is now running. Logs: /tmp/flyby.log"
