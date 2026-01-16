#!/bin/bash
#
# UCSF Conference Check-in Setup Script
# Run this to configure or update the automation on your Mac
#

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PLIST_8AM="com.ucsf.checkin.8am.plist"
PLIST_12PM="com.ucsf.checkin.12pm.plist"
CONFIG_FILE="$SCRIPT_DIR/config.json"

echo "========================================"
echo "UCSF Conference Check-in Setup"
echo "========================================"
echo

# =============================================================================
# Check if already installed
# =============================================================================

ALREADY_INSTALLED=0
CURRENT_NAME=""
CURRENT_LIKERT=""
CURRENT_CONFIRM=""

if [[ -f "$CONFIG_FILE" ]] && [[ -d "$SCRIPT_DIR/venv" ]]; then
    ALREADY_INSTALLED=1
    # Read current settings
    CURRENT_NAME=$(python3 -c "import json; print(json.load(open('$CONFIG_FILE')).get('name', ''))" 2>/dev/null || echo "")
    CURRENT_LIKERT=$(python3 -c "import json; print(json.load(open('$CONFIG_FILE')).get('default_responses', [5])[0])" 2>/dev/null || echo "5")
    CURRENT_CONFIRM=$(python3 -c "import json; print('yes' if json.load(open('$CONFIG_FILE')).get('confirm_before_submit', True) else 'no')" 2>/dev/null || echo "yes")

    echo "Existing installation detected!"
    echo "  Current name: $CURRENT_NAME"
    echo "  Current Likert response: $CURRENT_LIKERT"
    echo "  Confirmation prompt: $CURRENT_CONFIRM"
    echo
    read -p "Update settings? (y/n) [y]: " UPDATE_SETTINGS
    UPDATE_SETTINGS=${UPDATE_SETTINGS:-y}

    if [[ "$UPDATE_SETTINGS" != "y" && "$UPDATE_SETTINGS" != "Y" ]]; then
        echo "No changes made."
        exit 0
    fi
    echo
fi

# =============================================================================
# Prerequisites check (only for fresh install)
# =============================================================================

if [[ $ALREADY_INSTALLED -eq 0 ]]; then
    echo "Checking prerequisites..."
    echo

    MISSING_PREREQS=0

    # Check for macOS
    if [[ "$(uname)" != "Darwin" ]]; then
        echo "ERROR: This automation only works on macOS (uses launchd for scheduling)."
        exit 1
    fi
    echo "  [OK] macOS detected"

    # Check for Python 3
    if ! command -v python3 &> /dev/null; then
        echo "  [MISSING] Python 3"
        MISSING_PREREQS=1
    else
        PYTHON_VERSION=$(python3 --version 2>&1 | cut -d' ' -f2)
        echo "  [OK] Python $PYTHON_VERSION"
    fi

    # Check for pip
    if ! python3 -m pip --version &> /dev/null 2>&1; then
        echo "  [MISSING] pip"
        MISSING_PREREQS=1
    else
        echo "  [OK] pip"
    fi

    # Check for venv module
    if ! python3 -c "import venv" &> /dev/null 2>&1; then
        echo "  [MISSING] venv module"
        MISSING_PREREQS=1
    else
        echo "  [OK] venv module"
    fi

    # Check LaunchAgents directory exists
    if [[ ! -d ~/Library/LaunchAgents ]]; then
        echo "  [INFO] Creating ~/Library/LaunchAgents directory"
        mkdir -p ~/Library/LaunchAgents
    fi
    echo "  [OK] LaunchAgents directory"

    echo

    # If missing prerequisites, show installation instructions and exit
    if [[ $MISSING_PREREQS -eq 1 ]]; then
        echo "========================================"
        echo "Missing prerequisites!"
        echo "========================================"
        echo
        echo "Please install Python 3 by running:"
        echo
        echo "  xcode-select --install"
        echo
        echo "This installs the Xcode Command Line Tools, which includes Python 3."
        echo "After installation completes, run this setup script again."
        echo
        echo "Alternatively, install Python from https://www.python.org/downloads/"
        echo
        exit 1
    fi

    echo "All prerequisites satisfied!"
    echo
fi

# =============================================================================
# Configuration
# =============================================================================

# Conference calendar URL (shared by all users)
CALENDAR_URL="https://calendar.google.com/calendar/ical/ucsfrad%40gmail.com/public/basic.ics"

# Gather user information (use current values as defaults if updating)
if [[ -n "$CURRENT_NAME" ]]; then
    read -p "Enter your full name [$CURRENT_NAME]: " USER_NAME
    USER_NAME=${USER_NAME:-$CURRENT_NAME}
else
    read -p "Enter your full name (as it appears on the survey): " USER_NAME
fi

echo
echo "Default Likert response (1-5 scale):"
echo "  1 = Strongly Disagree"
echo "  2 = Disagree"
echo "  3 = Neutral"
echo "  4 = Agree"
echo "  5 = Strongly Agree"
DEFAULT_LIKERT=${CURRENT_LIKERT:-5}
read -p "Enter default response [$DEFAULT_LIKERT]: " LIKERT_RESPONSE
LIKERT_RESPONSE=${LIKERT_RESPONSE:-$DEFAULT_LIKERT}

echo
echo "Sign-in mode:"
echo "  1 = Automatic (signs in without prompting)"
echo "  2 = Prompt (shows confirmation dialog before signing in)"
if [[ "$CURRENT_CONFIRM" == "no" ]]; then
    DEFAULT_MODE=1
else
    DEFAULT_MODE=2
fi
read -p "Select mode [$DEFAULT_MODE]: " SIGNIN_MODE
SIGNIN_MODE=${SIGNIN_MODE:-$DEFAULT_MODE}

if [[ "$SIGNIN_MODE" == "1" ]]; then
    CONFIRM_BEFORE_SUBMIT="false"
else
    CONFIRM_BEFORE_SUBMIT="true"
fi

# =============================================================================
# Python environment (only for fresh install)
# =============================================================================

if [[ $ALREADY_INSTALLED -eq 0 ]]; then
    echo
    echo "----------------------------------------"
    echo "Setting up Python environment..."
    echo "----------------------------------------"

    # Create virtual environment
    python3 -m venv "$SCRIPT_DIR/venv"
    source "$SCRIPT_DIR/venv/bin/activate"

    # Install dependencies
    pip install -q -r "$SCRIPT_DIR/requirements.txt"

    # Install Playwright browser
    playwright install chromium
fi

echo
echo "----------------------------------------"
echo "Saving configuration..."
echo "----------------------------------------"

# Create config.json
cat > "$CONFIG_FILE" << EOF
{
    "name": "$USER_NAME",
    "calendar_url": "$CALENDAR_URL",
    "survey_url": "https://ucsf.co1.qualtrics.com/jfe/form/SV_8kUOSKMVlxBzCp8",
    "timezone": "America/Los_Angeles",
    "skip_keywords": ["admin", "wellness", "holiday", "rsna", "town hall", "orientation", "graduation", "core exam", "in service exam"],
    "default_responses": [$LIKERT_RESPONSE, $LIKERT_RESPONSE, $LIKERT_RESPONSE],
    "comment": "",
    "confirm_before_submit": $CONFIRM_BEFORE_SUBMIT,
    "confirm_timeout": 30
}
EOF

echo "Saved config.json"

# =============================================================================
# Scheduled tasks (only for fresh install)
# =============================================================================

if [[ $ALREADY_INSTALLED -eq 0 ]]; then
    echo
    echo "----------------------------------------"
    echo "Creating launchd configurations..."
    echo "----------------------------------------"

    # Create 8AM plist
    cat > "$SCRIPT_DIR/$PLIST_8AM" << EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>com.ucsf.checkin.8am</string>
    <key>ProgramArguments</key>
    <array>
        <string>$SCRIPT_DIR/venv/bin/python</string>
        <string>$SCRIPT_DIR/checkin.py</string>
        <string>--time</string>
        <string>8AM</string>
    </array>
    <key>WorkingDirectory</key>
    <string>$SCRIPT_DIR</string>
    <key>StartCalendarInterval</key>
    <dict>
        <key>Hour</key>
        <integer>8</integer>
        <key>Minute</key>
        <integer>45</integer>
    </dict>
    <key>StandardOutPath</key>
    <string>/tmp/checkin-8am.log</string>
    <key>StandardErrorPath</key>
    <string>/tmp/checkin-8am.log</string>
</dict>
</plist>
EOF

    # Create 12PM plist
    cat > "$SCRIPT_DIR/$PLIST_12PM" << EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>com.ucsf.checkin.12pm</string>
    <key>ProgramArguments</key>
    <array>
        <string>$SCRIPT_DIR/venv/bin/python</string>
        <string>$SCRIPT_DIR/checkin.py</string>
        <string>--time</string>
        <string>12PM</string>
    </array>
    <key>WorkingDirectory</key>
    <string>$SCRIPT_DIR</string>
    <key>StartCalendarInterval</key>
    <dict>
        <key>Hour</key>
        <integer>12</integer>
        <key>Minute</key>
        <integer>45</integer>
    </dict>
    <key>StandardOutPath</key>
    <string>/tmp/checkin-12pm.log</string>
    <key>StandardErrorPath</key>
    <string>/tmp/checkin-12pm.log</string>
</dict>
</plist>
EOF

    echo "Created plist files"

    echo
    echo "----------------------------------------"
    echo "Installing scheduled tasks..."
    echo "----------------------------------------"

    # Unload existing jobs if present (ignore errors)
    launchctl unload ~/Library/LaunchAgents/$PLIST_8AM 2>/dev/null || true
    launchctl unload ~/Library/LaunchAgents/$PLIST_12PM 2>/dev/null || true

    # Copy to LaunchAgents
    cp "$SCRIPT_DIR/$PLIST_8AM" ~/Library/LaunchAgents/
    cp "$SCRIPT_DIR/$PLIST_12PM" ~/Library/LaunchAgents/

    # Load the jobs
    launchctl load ~/Library/LaunchAgents/$PLIST_8AM
    launchctl load ~/Library/LaunchAgents/$PLIST_12PM

    echo "Installed and activated scheduled tasks"
fi

echo
echo "========================================"
if [[ $ALREADY_INSTALLED -eq 1 ]]; then
    echo "Settings updated!"
else
    echo "Setup complete!"
fi
echo "========================================"
echo
echo "Your settings:"
echo "  Name: $USER_NAME"
echo "  Likert response: $LIKERT_RESPONSE (Strongly Agree)"
if [[ "$CONFIRM_BEFORE_SUBMIT" == "true" ]]; then
    echo "  Mode: Prompt before signing in"
else
    echo "  Mode: Automatic (no prompt)"
fi
echo
echo "Schedule:"
echo "  - 8AM check-in:  Daily at 8:45 AM"
echo "  - 12PM check-in: Daily at 12:45 PM"
echo
echo "To test now (dry run):"
echo "  source venv/bin/activate"
echo "  python checkin.py --time 8AM --dry-run --force"
echo
echo "To change settings, run this script again:"
echo "  ./setup.sh"
echo
echo "To uninstall:"
echo "  ./uninstall.sh"
echo
