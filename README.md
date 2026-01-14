# UCSF Conference Check-in Automation

Automatically fills out the daily UCSF radiology conference attendance survey based on your calendar.

## How It Works

1. Fetches your Google Calendar ICS feed
2. Checks if today's event contains "Admin" or "Wellness" (skip keywords)
3. If it's a conference day, uses Playwright to fill out the Qualtrics survey
4. Submits with your name, the correct date format, and default responses

The 8AM and 12PM conferences are checked independently based on the event times.

## Quick Start

```bash
git clone https://github.com/banderies/conference-sign-in.git
cd conference-sign-in
./setup.sh
```

The setup script will:
- Ask for your name and Google Calendar ICS URL
- Install Python dependencies and Playwright browser
- Create your personal config file
- Install and activate the scheduled tasks

That's it! The automation will run daily at 8:45 AM and 12:45 PM.

## Managing the Automation

```bash
# View logs
cat /tmp/checkin-8am.log
cat /tmp/checkin-12pm.log

# Check if jobs are running
launchctl list | grep ucsf

# Manually trigger a check-in
source venv/bin/activate
python checkin.py --time 8AM

# Test without submitting (opens browser)
python checkin.py --time 8AM --dry-run --force

# Uninstall
./uninstall.sh
```

## Command Line Options

| Flag | Description |
|------|-------------|
| `--time 8AM` or `--time 12PM` | Required. Which session to check in for |
| `--dry-run` | Fill form but don't submit (shows browser for debugging) |
| `--force` | Submit even if calendar check fails or says no conference |

## Configuration

After running `setup.sh`, your settings are stored in `config.json`:

```json
{
    "name": "Your Name",
    "calendar_url": "https://calendar.google.com/calendar/ical/.../basic.ics",
    "skip_keywords": ["admin", "wellness"],
    "default_responses": [5, 5, 5]
}
```

Edit this file to change your settings. The `default_responses` are on a 1-5 scale (5 = Strongly Agree).

## Troubleshooting

### Form structure changed
Run with `--dry-run --force` to see what's happening. You may need to update the Playwright selectors in `checkin.py`.

### Calendar not loading
Test the URL directly: `curl "YOUR_CALENDAR_URL"`. Make sure it's a public ICS feed.

### Jobs not running
Your Mac must be awake at the scheduled time. If it's asleep, the job runs when it wakes (same day only).

## Files

```
conference-sign-in/
├── setup.sh                # Run this to install
├── uninstall.sh            # Run this to remove
├── checkin.py              # Main script
├── config.json             # Your settings (created by setup.sh)
├── config.example.json     # Template for manual setup
├── requirements.txt        # Python dependencies
├── com.ucsf.checkin.8am.plist    # macOS launchd config
└── com.ucsf.checkin.12pm.plist   # macOS launchd config
```
