# Facebook Group Poster

Script to publish a text (and optional image) post to multiple Facebook groups using your own logged-in Chrome browser session via Playwright.

> **Why browser automation?** Meta deprecated the official Facebook Groups API in 2024, so third-party apps can no longer publish posts to groups via the Graph API.

## Setup

1. Activate the virtual environment (or create it if needed):
   ```bash
   python3 -m venv .venv
   source .venv/bin/activate
   pip install -r requirements.txt
   ```

2. Copy the example configuration and customize it:
   ```bash
   cp config.example.json config.json
   ```
   Edit `config.json`:
   - `groups`: list of Facebook group URLs (`https://www.facebook.com/groups/.../`).
   - `anonymous`: set to `true` to post as an anonymous group member (groups where anonymous posting is disabled are recorded as `"skipped"` and the script moves on to the next group).
   - `message` (or `message_file`): the text to post.
   - `images`: optional list of local image paths to attach.
   - `delay_seconds`: random delay range (`min` / `max`) waited between groups.

## Usage

### 1. Sign in to Facebook (choose one option)

- **Option A — Interactive login (recommended, supports 2FA):**
  ```bash
  .venv/bin/python fb_poster.py --login
  ```
  Chrome will open to Facebook. Sign in manually (including any 2FA or security prompts), then press **ENTER** in the terminal to save your session in `./fb_profile`.

- **Option B — Configure email and password:**
  Set `"email"` and `"password"` in `config.json`, or copy `.env.example` to `.env` and fill in `FB_EMAIL` and `FB_PASSWORD` (both files are in `.gitignore`). If Facebook asks for 2FA or a security checkpoint, use Option A (`--login`) to complete it once.

### 2. Test safely with `--dry-run`
```bash
.venv/bin/python fb_poster.py --dry-run
```
This opens each group, fills in the post composer, and closes it without clicking **Post**.

### 3. Publish to your groups
```bash
.venv/bin/python fb_poster.py
```

If Facebook shows a login prompt or security checkpoint, the script stops immediately so you can resolve it manually. Execution reports are saved in `./logs/`.

## Flutter Mobile Application (`mobile_app/`)

The Flutter mobile application in `mobile_app/` provides:
- **Start / Stop** controls on the main dashboard with live progress, countdowns, and logs.
- **Side Menu** navigation:
  - **FB Account**: Configure Facebook email and password (plus interactive 2FA login).
  - **Default Post**: Create, edit, delete, and select the default post template (text & images).
  - **Script History**: View past execution runs, per-group statuses, and JSON reports.

### Running the Mobile App
```bash
cd mobile_app
flutter pub get
flutter run
```

### Optional: Python Bridge Server Mode
To execute the desktop Playwright script (`fb_poster.py`) remotely from the mobile app or from Linux desktop:
```bash
.venv/bin/python bridge_server.py --host 0.0.0.0 --port 8765
```
Then set the Bridge Server URL in the app's **FB Account** screen (e.g. `http://<YOUR_PC_IP>:8765`) and select **Python Script Bridge** under Script Options.
