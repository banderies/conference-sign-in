# UCSF Conference Check-in Automation

Automatically fills out the daily UCSF radiology conference attendance survey based on your calendar.

## How It Works

1. Fetches your Google Calendar ICS feed
2. Checks if today's events contain "Admin" or "Wellness" (skip keywords)
3. If it's a conference day, uses Playwright to fill out the Qualtrics survey
4. Submits with your name, the correct date format, and default responses

## Setup

### 1. Install Dependencies

```bash
cd conference_checkin
python3 -m venv venv
source venv/bin/activate
pip install -r requirements.txt
playwright install chromium
```

### 2. Configure

Edit the `CONFIG` section at the top of `checkin.py`:

```python
CONFIG = {
    "name": "Barrett Anderies",  # Your name
    "calendar_url": "https://...",  # Your calendar ICS URL
    "skip_keywords": ["admin", "wellness"],  # Days to skip
    "default_responses": [4, 4, 4],  # 1-5 scale (4 = Agree)
    ...
}
```

### 3. Test with Dry Run

```bash
# This will fill the form but NOT submit, and show the browser
python checkin.py --time 8AM --dry-run
```

Watch the browser to verify it's filling fields correctly. Press Enter to close.

### 4. Run for Real

```bash
python checkin.py --time 8AM
python checkin.py --time 12PM
```

## Scheduling (macOS)

### Option A: launchd (Recommended)

Copy the plist files to your LaunchAgents folder:

```bash
cp com.ucsf.checkin.8am.plist ~/Library/LaunchAgents/
cp com.ucsf.checkin.12pm.plist ~/Library/LaunchAgents/
```

Edit both files to update the path to your Python environment.

Load them:

```bash
launchctl load ~/Library/LaunchAgents/com.ucsf.checkin.8am.plist
launchctl load ~/Library/LaunchAgents/com.ucsf.checkin.12pm.plist
```

To unload:

```bash
launchctl unload ~/Library/LaunchAgents/com.ucsf.checkin.8am.plist
```

### Option B: cron

```bash
crontab -e
```

Add:

```
0 8 * * 1-5 cd /path/to/conference_checkin && ./venv/bin/python checkin.py --time 8AM >> ~/checkin.log 2>&1
0 12 * * 1-5 cd /path/to/conference_checkin && ./venv/bin/python checkin.py --time 12PM >> ~/checkin.log 2>&1
```

## Command Line Options

| Flag | Description |
|------|-------------|
| `--time 8AM` or `--time 12PM` | Required. Which session to check in for |
| `--dry-run` | Fill form but don't submit (shows browser for debugging) |
| `--force` | Submit even if calendar check fails or says no conference |

## Troubleshooting

### Form structure changed
Run with `--dry-run` to see what's happening. You may need to update the Playwright selectors in `submit_survey()`.

### Calendar not loading
Test the URL directly: `curl "YOUR_CALENDAR_URL"`. Make sure it's a public ICS feed.

### Qualtrics blocking automation
Try adding random delays between actions, or run with `headless=False` to use a visible browser.

## Files

```
conference_checkin/
├── checkin.py              # Main script
├── requirements.txt        # Python dependencies
├── README.md               # This file
├── com.ucsf.checkin.8am.plist   # macOS launchd config (8 AM)
└── com.ucsf.checkin.12pm.plist  # macOS launchd config (12 PM)
```
