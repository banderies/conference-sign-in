# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Overview

This is a Python automation that fills out a UCSF radiology conference attendance Qualtrics survey. It fetches the conference Google Calendar ICS feed, checks if today is a conference day (by checking if the event name exactly matches a skip keyword like "admin" or "wellness"), submits the survey via Playwright browser automation, and sends a macOS notification with the result.

## Commands

```bash
# Setup (interactive - creates config and installs scheduled tasks)
./setup.sh

# Uninstall
./uninstall.sh

# Run with dry-run (shows browser, doesn't submit)
source venv/bin/activate
python checkin.py --time 8AM --dry-run --force

# Run for real
python checkin.py --time 8AM
python checkin.py --time 12PM

# Force submission even if calendar says no conference
python checkin.py --time 8AM --force
```

## Architecture

Single-file script (`checkin.py`) with main sections:

1. **Configuration**: Loaded from `config.json` (user-specific settings like name and Likert responses). Calendar URL is hardcoded since it's shared.
2. **Calendar functions**: Fetch ICS feed, parse today's events filtered by time slot (8AM or 12PM), determine if it's a conference day (skip if event name exactly matches a skip keyword, case-insensitive)
3. **Form submission** (`submit_survey`): Playwright automation that navigates a 2-page Qualtrics form - page 1 collects name and conference type, page 2 collects date, time slot, three Likert questions, and optional comment
4. **Notifications** (`notify`): Sends macOS notifications via `osascript` for success, skip, or failure

## Scheduling

- `setup.sh` installs launchd jobs automatically
- Schedule: 8:45 AM and 12:45 PM daily
- Plist files are copied to `~/Library/LaunchAgents/`
- Logs written to `/tmp/checkin-8am.log` and `/tmp/checkin-12pm.log`

## Key Implementation Details

- Form selectors in `submit_survey()` are Qualtrics-specific and may break if form structure changes
- Uses `--dry-run` with visible browser (`headless=False`) and Playwright Inspector pauses for debugging
- Calendar events are filtered by time window: 8AM checks 7-10 AM events, 12PM checks 11 AM-2 PM events
- Notifications are skipped during `--dry-run` mode
