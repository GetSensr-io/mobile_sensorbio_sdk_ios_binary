from pathlib import Path
from playwright.sync_api import sync_playwright

base = Path(__file__).resolve().parent
html = base / "index.html"
out = base / "screenshots"
out.mkdir(exist_ok=True)
url = html.as_uri()

names = [
    "screen-01-today-weight-care.png",
    "screen-02-noom-band-setup.png",
    "screen-03-glp1-check-in.png",
    "screen-04-sleep-recovery.png",
    "screen-05-progress-signals.png",
    "screen-06-coach-plan.png",
]

with sync_playwright() as p:
    browser = p.chromium.launch(headless=True)
    page = browser.new_page(viewport={"width": 1500, "height": 2400}, device_scale_factor=1)
    messages = []
    page_errors = []
    page.on("console", lambda msg: messages.append(f"{msg.type}: {msg.text}"))
    page.on("pageerror", lambda exc: page_errors.append(str(exc)))
    page.goto(url, wait_until="load")
    page.wait_for_timeout(300)
    page.screenshot(path=str(out / "contact-sheet.png"), full_page=True)
    cards = page.locator(".mock-card")
    count = cards.count()
    for i in range(min(count, len(names))):
        phone = cards.nth(i).locator(".phone")
        phone.screenshot(path=str(out / names[i]))
    browser.close()

serious = [m for m in messages if m.startswith("error:")]
if serious:
    print("Console errors:")
    for m in serious:
        print(m)
else:
    print("No console errors")

if page_errors:
    print("Page errors:")
    for e in page_errors:
        print(e)
else:
    print("No page errors")

print(f"Exported {1 + min(count, len(names))} screenshot(s) to {out}")
