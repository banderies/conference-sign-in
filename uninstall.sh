#!/bin/bash
#
# Uninstall UCSF Conference Check-in automation
#

echo "Uninstalling UCSF Conference Check-in..."

# Unload launchd jobs
launchctl unload ~/Library/LaunchAgents/com.ucsf.checkin.8am.plist 2>/dev/null && echo "Unloaded 8AM job" || true
launchctl unload ~/Library/LaunchAgents/com.ucsf.checkin.12pm.plist 2>/dev/null && echo "Unloaded 12PM job" || true

# Remove plist files
rm -f ~/Library/LaunchAgents/com.ucsf.checkin.8am.plist
rm -f ~/Library/LaunchAgents/com.ucsf.checkin.12pm.plist

echo
echo "Automation uninstalled."
echo "The script files remain in this directory if you want to reinstall later."
echo "To fully remove, delete this directory."
