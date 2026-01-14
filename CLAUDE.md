# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Overview

This is a Python automation that fills out a UCSF radiology conference attendance Qualtrics survey. It fetches a Google Calendar ICS feed, checks if today is a conference day (by looking for skip keywords like "admin" or "wellness"), and submits the survey via Playwright browser automation.

## Commands

```bash
# Setup (first time)
python3 -m venv venv
source venv/bin/activate
pip install -r requirements.txt
playwright install chromium

# Run with dry-run (shows browser, doesn't submit)
python checkin.py --time 8AM --dry-run
python checkin.py --time 12PM --dry-run

# Run for real
python checkin.py --time 8AM
python checkin.py --time 12PM

# Force submission even if calendar says no conference
python checkin.py --time 8AM --force
```

## Architecture

Single-file script (`checkin.py`) with three main sections:

1. **Configuration** (`CONFIG` dict at top): User-editable settings for name, calendar URL, survey URL, skip keywords, and default Likert responses
2. **Calendar functions**: Fetch ICS feed, parse today's events, determine if it's a conference day based on skip keywords
3. **Form submission** (`submit_survey`): Playwright automation that navigates a 2-page Qualtrics form - page 1 collects name and conference type, page 2 collects date, time slot, three Likert questions, and optional comment

## Scheduling

The `.plist` files are macOS launchd configs for running at 8:05 AM and 12:05 PM. Copy to `~/Library/LaunchAgents/` and load with `launchctl load`.

## Key Implementation Details

- Form selectors in `submit_survey()` are Qualtrics-specific and may break if form structure changes
- Uses `--dry-run` with visible browser (`headless=False`) for debugging selector issues
- Calendar check runs first; if it fails without `--force`, script exits without submitting
