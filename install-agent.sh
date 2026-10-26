#!/bin/bash
# Installs the launch agent that starts the app at login and keeps it running.
# Run after build.sh. Run with --remove to uninstall the agent.
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
# shellcheck disable=SC1090
source "$HERE/config.env"
PLIST="$HOME/Library/LaunchAgents/$AGENT_LABEL.plist"
DOMAIN="gui/$(id -u)"
EXEC="/Applications/$APP_NAME.app/Contents/MacOS/$APP_NAME"

unload() {
  launchctl bootout "$DOMAIN/$AGENT_LABEL" 2>/dev/null || true
  for _ in $(seq 40); do launchctl print "$DOMAIN/$AGENT_LABEL" >/dev/null 2>&1 || break; sleep 0.25; done
}

if [ "${1:-}" = "--remove" ]; then
  unload
  launchctl enable "$DOMAIN/$AGENT_LABEL"
  rm -f "$PLIST"
  echo "Removed $PLIST. Nothing is left running."
  exit 0
fi

[ -x "$EXEC" ] || { echo "$EXEC not found. Run ./build.sh first."; exit 1; }
mkdir -p "$HOME/Library/LaunchAgents"
cat > "$PLIST" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key><string>$AGENT_LABEL</string>
  <key>ProgramArguments</key><array><string>$EXEC</string></array>
  <key>AssociatedBundleIdentifiers</key><string>$BUNDLE_ID</string>
  <key>ProcessType</key><string>Interactive</string>
  <key>RunAtLoad</key><true/>
  <key>KeepAlive</key><true/>
  <key>ThrottleInterval</key><integer>30</integer>
  <key>AbandonProcessGroup</key><true/>
</dict>
</plist>
PLIST
unload
launchctl enable "$DOMAIN/$AGENT_LABEL"
launchctl bootstrap "$DOMAIN" "$PLIST"
echo "Agent $AGENT_LABEL installed and running."
