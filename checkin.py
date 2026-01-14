#!/usr/bin/env python3
"""
UCSF Conference Check-in Automation
Fetches calendar, checks for conference days, and submits Qualtrics survey.

Usage:
    python checkin.py --time 8AM
    python checkin.py --time 12PM
    python checkin.py --time 8AM --dry-run  # Test without submitting
"""

import argparse
import json
import re
from datetime import datetime, timedelta
from pathlib import Path
from zoneinfo import ZoneInfo

import requests
from icalendar import Calendar
from playwright.sync_api import sync_playwright

# =============================================================================
# CONFIGURATION
# =============================================================================

# Default config (used if config.json doesn't exist)
DEFAULT_CONFIG = {
    "name": "Your Name",
    "calendar_url": "https://calendar.google.com/calendar/ical/ucsfrad%40gmail.com/public/basic.ics",
    "survey_url": "https://ucsf.co1.qualtrics.com/jfe/form/SV_8kUOSKMVlxBzCp8",
    "timezone": "America/Los_Angeles",
    "skip_keywords": ["admin", "wellness"],
    "default_responses": [5, 5, 5],
    "comment": "",
}

def load_config() -> dict:
    """Load configuration from config.json or use defaults."""
    config_path = Path(__file__).parent / "config.json"
    if config_path.exists():
        with open(config_path) as f:
            return {**DEFAULT_CONFIG, **json.load(f)}
    return DEFAULT_CONFIG

CONFIG = load_config()

# =============================================================================
# CALENDAR FUNCTIONS
# =============================================================================

def fetch_calendar(url: str) -> Calendar:
    """Fetch and parse the ICS calendar."""
    response = requests.get(url, timeout=30)
    response.raise_for_status()
    return Calendar.from_ical(response.content)


def get_todays_events(cal: Calendar, tz: ZoneInfo, lecture_time: str = None) -> list[dict]:
    """
    Extract today's events from the calendar.

    Args:
        cal: Parsed calendar object
        tz: Timezone to use
        lecture_time: If "8AM" or "12PM", filter to events in that time window
    """
    today = datetime.now(tz).date()
    events = []

    # Define time windows for each lecture slot (in local hours)
    time_windows = {
        "8AM": (7, 10),   # 7 AM - 10 AM
        "12PM": (11, 14), # 11 AM - 2 PM
    }

    for component in cal.walk():
        if component.name != "VEVENT":
            continue

        dtstart = component.get("DTSTART")
        if dtstart is None:
            continue

        # Handle both date and datetime objects
        event_dt = dtstart.dt
        event_date = event_dt.date() if hasattr(event_dt, "date") else event_dt

        if event_date != today:
            continue

        # Filter by time window if lecture_time is specified
        if lecture_time and hasattr(event_dt, "hour"):
            # Convert to local timezone
            if event_dt.tzinfo is not None:
                local_dt = event_dt.astimezone(tz)
            else:
                local_dt = event_dt.replace(tzinfo=tz)

            start_hour, end_hour = time_windows.get(lecture_time, (0, 24))
            if not (start_hour <= local_dt.hour < end_hour):
                continue

        summary = str(component.get("SUMMARY", ""))
        events.append({
            "summary": summary,
            "start": event_dt,
        })

    return events


def is_conference_day(events: list[dict], skip_keywords: list[str]) -> tuple[bool, str]:
    """
    Determine if today is a conference day.
    Returns (is_conference, reason).
    """
    if not events:
        return False, "No events found for today"
    
    for event in events:
        summary = event["summary"].lower()
        for keyword in skip_keywords:
            if keyword.lower() in summary:
                return False, f"Found skip keyword '{keyword}' in event: {event['summary']}"
    
    # If we get here, there are events and none contain skip keywords
    event_names = ", ".join(e["summary"] for e in events)
    return True, f"Conference day detected. Events: {event_names}"


# =============================================================================
# FORM SUBMISSION
# =============================================================================

def submit_survey(
    name: str,
    lecture_time: str,
    responses: list[int],
    comment: str,
    survey_url: str,
    dry_run: bool = False,
) -> bool:
    """
    Fill out and submit the Qualtrics survey using Playwright.
    
    Args:
        name: Your name for the form
        lecture_time: "8AM" or "12PM"
        responses: List of 3 integers (1-5) for Likert questions
        comment: Optional comment text
        survey_url: The Qualtrics form URL
        dry_run: If True, fill form but don't submit
    
    Returns:
        True if successful, False otherwise
    """
    # Format today's date as MM/DD/YYYY (with leading zeros)
    today = datetime.now().strftime("%m/%d/%Y")
    
    with sync_playwright() as p:
        browser = p.chromium.launch(headless=not dry_run)  # Show browser in dry-run
        page = browser.new_page()
        
        try:
            # Navigate to survey
            print(f"Loading survey: {survey_url}")
            page.goto(survey_url, wait_until="networkidle")
            page.wait_for_timeout(1000)  # Extra wait for JS
            
            # =================================================================
            # PAGE 1: Name and Conference Type
            # =================================================================
            print("Filling Page 1...")
            
            # Fill name (textarea)
            name_field = page.locator("textarea").first
            name_field.fill(name)
            
            # Select "General Conference" (first option in the choice list)
            # Qualtrics uses divs with role="radio" or similar
            general_conf = page.locator("text=General Conference").first
            general_conf.click()
            
            if dry_run:
                print("\n[DRY RUN] Page 1 filled. Check the browser, then click 'Resume' in the Playwright Inspector.")
                page.pause()

            # Click next arrow
            page.locator("button[aria-label='Next']").or_(
                page.locator("button:has-text('→')")
            ).or_(
                page.locator(".NextButton")
            ).or_(
                page.locator("button >> nth=-1")  # Last button on page
            ).click()

            page.wait_for_timeout(1000)
            
            # =================================================================
            # PAGE 2: Date, Time, Questions
            # =================================================================
            print("Filling Page 2...")
            
            # Fix the date field (clear and re-enter with correct format)
            date_field = page.locator("input[type='text']").first
            date_field.click()
            date_field.fill("")  # Clear
            date_field.fill(today)
            print(f"  Date: {today}")
            
            # Select lecture time (8AM or 12PM)
            time_option = page.locator(f"text={lecture_time}").first
            time_option.click()
            print(f"  Time: {lecture_time}")
            
            # Answer the 3 Likert questions
            # Map response number to text
            likert_map = {
                1: "Strongly disagree",
                2: "Disagree",
                3: "Neutral",
                4: "Agree",
                5: "Strongly Agree",
            }
            
            # Find all question containers and answer each
            # Qualtrics typically has each question in a container
            questions = [
                "The content of the lecture was relevant and helpful",
                "The lecture format was effective for my learning",
                "The lecturer was competent and taught effectively",
            ]
            
            for i, (question_text, response) in enumerate(zip(questions, responses)):
                response_text = likert_map[response]
                print(f"  Q{i+1}: {response_text}")
                
                # Find the question container, then click the appropriate response
                # We look for the response text that's near the question
                question_container = page.locator(f"text={question_text}").locator("..").locator("..")
                
                # Try to find and click the response within that container
                # If that fails, fall back to finding any matching response
                try:
                    question_container.locator(f"text=/{response_text}/i").first.click()
                except:
                    # Fallback: click the nth occurrence of the response
                    page.locator(f"text=/{response_text}/i").nth(i).click()
            
            # Optional comment
            if comment:
                comment_field = page.locator("textarea").last
                comment_field.fill(comment)
                print(f"  Comment: {comment[:50]}...")

            # Submit or pause for dry run
            if dry_run:
                print("\n[DRY RUN] Page 2 filled. Check the browser, then click 'Resume' to submit (or close browser to cancel).")
                page.pause()
            else:
                # Click submit/next
                page.locator("button[aria-label='Next']").or_(
                    page.locator("button:has-text('→')")
                ).or_(
                    page.locator(".NextButton")
                ).click()
                
                page.wait_for_timeout(2000)
                print("Survey submitted successfully!")
            
            return True
            
        except Exception as e:
            print(f"Error during form submission: {e}")
            if dry_run:
                print("Browser will stay open for debugging. Click 'Resume' in Playwright Inspector to close.")
                page.pause()
            return False
            
        finally:
            browser.close()


# =============================================================================
# MAIN
# =============================================================================

def main():
    parser = argparse.ArgumentParser(description="UCSF Conference Check-in Automation")
    parser.add_argument(
        "--time",
        choices=["8AM", "12PM"],
        required=True,
        help="Lecture time to check in for",
    )
    parser.add_argument(
        "--dry-run",
        action="store_true",
        help="Fill form but don't submit (shows browser)",
    )
    parser.add_argument(
        "--force",
        action="store_true",
        help="Submit even if calendar says no conference",
    )
    args = parser.parse_args()
    
    tz = ZoneInfo(CONFIG["timezone"])
    print(f"=== UCSF Conference Check-in ({args.time}) ===")
    print(f"Date: {datetime.now(tz).strftime('%A, %B %d, %Y')}")
    print()
    
    # Step 1: Fetch and check calendar
    print("Checking calendar...")
    try:
        cal = fetch_calendar(CONFIG["calendar_url"])
        events = get_todays_events(cal, tz, lecture_time=args.time)
        is_conf, reason = is_conference_day(events, CONFIG["skip_keywords"])
        print(f"  {reason}")
    except Exception as e:
        print(f"  Warning: Could not fetch calendar: {e}")
        if not args.force:
            print("  Use --force to submit anyway.")
            return 1
        is_conf = True
        print("  Proceeding anyway due to --force flag.")
    
    print()
    
    # Step 2: Decide whether to submit
    if not is_conf and not args.force:
        print("No conference today. Skipping submission.")
        return 0
    
    # Step 3: Submit the survey
    print("Submitting survey...")
    success = submit_survey(
        name=CONFIG["name"],
        lecture_time=args.time,
        responses=CONFIG["default_responses"],
        comment=CONFIG["comment"],
        survey_url=CONFIG["survey_url"],
        dry_run=args.dry_run,
    )
    
    return 0 if success else 1


if __name__ == "__main__":
    exit(main())
