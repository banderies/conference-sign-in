#!/bin/bash
#
# UCSF Conference Check-in Setup Script
# Run this once to configure the automation on your Mac
#

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PLIST_8AM="com.ucsf.checkin.8am.plist"
PLIST_12PM="com.ucsf.checkin.12pm.plist"

echo "========================================"
echo "UCSF Conference Check-in Setup"
echo "========================================"
echo

# =============================================================================
# Prerequisites check
# =============================================================================

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

# =============================================================================
# Configuration
# =============================================================================

# Conference calendar URL (shared by all users)
CALENDAR_URL="https://calendar.google.com/calendar/ical/ucsfrad%40gmail.com/public/basic.ics"

# Gather user information
read -p "Enter your full name (as it appears on the survey): " USER_NAME

echo
echo "Default Likert response (1-5 scale):"
echo "  1 = Strongly Disagree"
echo "  2 = Disagree"
echo "  3 = Neutral"
echo "  4 = Agree"
echo "  5 = Strongly Agree"
read -p "Enter default response [5]: " LIKERT_RESPONSE
LIKERT_RESPONSE=${LIKERT_RESPONSE:-5}

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

echo
echo "----------------------------------------"
echo "Creating configuration..."
echo "----------------------------------------"

# Create config.json
cat > "$SCRIPT_DIR/config.json" << EOF
{
    "name": "$USER_NAME",
    "calendar_url": "$CALENDAR_URL",
    "survey_url": "https://ucsf.co1.qualtrics.com/jfe/form/SV_8kUOSKMVlxBzCp8",
    "timezone": "America/Los_Angeles",
    "skip_keywords": ["admin", "wellness"],
    "default_responses": [$LIKERT_RESPONSE, $LIKERT_RESPONSE, $LIKERT_RESPONSE],
    "comment": ""
}
EOF

echo "Created config.json"

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

echo
echo "========================================"
echo "Setup complete!"
echo "========================================"
echo
echo "Schedule:"
echo "  - 8AM check-in:  Daily at 8:45 AM"
echo "  - 12PM check-in: Daily at 12:45 PM"
echo
echo "To test now (dry run):"
echo "  source venv/bin/activate"
echo "  python checkin.py --time 8AM --dry-run --force"
echo
echo "To view logs:"
echo "  cat /tmp/checkin-8am.log"
echo "  cat /tmp/checkin-12pm.log"
echo
echo "To uninstall:"
echo "  ./uninstall.sh"
echo
