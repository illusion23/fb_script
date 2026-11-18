#!/usr/bin/env python3
"""Publish a post to multiple Facebook groups using a persistent Chrome session.

Note: Meta deprecated the official Groups API in 2024, so posting to groups
requires interactive browser automation. You must log in manually via `--login`
before posting; this script never stores credentials or bypasses checkpoints.
"""

from __future__ import annotations

import argparse
import json
import logging
import os
import random
import re
import sys
import threading
import time
from collections.abc import Callable
from dataclasses import dataclass, field, replace
from datetime import datetime, timezone
from pathlib import Path
from typing import Any
from urllib.parse import urlparse

from playwright.sync_api import BrowserContext, Locator, Page, TimeoutError as PlaywrightTimeoutError, sync_playwright

LOGGER = logging.getLogger("fb_poster")

GROUP_URL_PATTERN = re.compile(r"^https?://(www\.|m\.|mbasic\.)?facebook\.com/groups/[^/?#]+/?")

COMPOSER_TRIGGER_LABELS = (
    "Write something...",
    "Create a public post...",
    "Start a discussion...",
    "Exprimez-vous...",
    "Créer une publication publique...",
    "Écrire quelque chose...",
    "اكتب شيئًا...",
    "بم تفكر؟",
    "إنشاء منشور عام...",
)

SUBMIT_BUTTON_NAMES = ("Post", "Publier", "نشر", "Submit", "Envoyer", "إرسال", "Publicar", "Posten")

PHOTO_BUTTON_LABELS = ("Photo/video", "Photo/Video", "Photo / Vidéo", "Photo/vidéo", "صورة/فيديو")

ANONYMOUS_TRIGGER_LABELS = (
    "Anonymous post",
    "Publication anonyme",
    "منشور مجهول الهوية",
    "نشر كمجهول",
)

ANONYMOUS_SWITCH_LABELS = (
    "Post anonymously",
    "Publier anonymement",
    "النشر كمجهول الهوية",
    "النشر كمجهول",
    "نشر مجهول الهوية",
)

ANONYMOUS_CONFIRM_LABELS = (
    "Create Anonymous Post",
    "Create anonymous post",
    "Continue",
    "Got it",
    "Publier anonymement",
    "Continuer",
    "Compris",
    "إنشاء منشور مجهول الهوية",
    "متابعة",
    "موافق",
)

ANONYMOUS_AUTHOR_LABELS = (
    "Anonymous member",
    "Anonymous participant",
    "Membre anonyme",
    "Participant anonyme",
    "عضو مجهول الهوية",
    "مشارك مجهول الهوية",
)


class AnonymousNotAvailableError(Exception):
    """Raised when anonymous posting is requested but disabled in a group."""


@dataclass(frozen=True)
class PosterConfig:
    """Validated runtime configuration for Facebook group posting."""

    profile_dir: Path
    headless: bool
    anonymous: bool
    delay_min: float
    delay_max: float
    message: str
    images: list[Path]
    groups: list[str]
    email: str = ""
    password: str = field(default="", repr=False)
    require_anonymous_if_available: bool = False
    prefer_anonymous: bool = False


def _read_dotenv(dotenv_path: Path) -> dict[str, str]:
    """Parse simple KEY=VALUE pairs from a .env file if it exists."""
    values: dict[str, str] = {}
    if not dotenv_path.is_file():
        return values
    for raw_line in dotenv_path.read_text(encoding="utf-8").splitlines():
        line = raw_line.strip()
        if not line or line.startswith("#") or "=" not in line:
            continue
        key, val = line.split("=", 1)
        key = key.strip()
        val = val.strip().strip('"').strip("'")
        if key:
            values[key] = val
    return values


def normalize_group_url(raw_url: str) -> str:
    """Validate and normalize a Facebook group URL to the desktop canonical form."""
    url = raw_url.strip()
    if not GROUP_URL_PATTERN.match(url):
        raise ValueError(
            f"Invalid Facebook group URL: {raw_url!r}. "
            "Expected format: https://www.facebook.com/groups/<group_id_or_slug>/"
        )
    parsed = urlparse(url)
    path_parts = [part for part in parsed.path.split("/") if part]
    if len(path_parts) < 2 or path_parts[0] != "groups":
        raise ValueError(f"Invalid Facebook group path in URL: {raw_url!r}")
    if path_parts[1].startswith("YOUR_GROUP_ID"):
        raise ValueError(f"Placeholder group URL must be replaced with a real group URL: {raw_url!r}")
    return f"https://www.facebook.com/groups/{path_parts[1]}/"


def load_config(config_path: Path) -> PosterConfig:
    """Load, resolve, and validate configuration from a JSON file."""
    if not config_path.exists():
        raise FileNotFoundError(
            f"Config file not found: {config_path}. "
            "Copy config.example.json to config.json and customize it first."
        )

    raw: dict[str, Any] = json.loads(config_path.read_text(encoding="utf-8"))
    base_dir = config_path.parent.resolve()

    profile_dir = Path(raw.get("profile_dir", "./fb_profile"))
    if not profile_dir.is_absolute():
        profile_dir = (base_dir / profile_dir).resolve()

    headless = bool(raw.get("headless", False))
    anonymous = bool(raw.get("anonymous", False))
    require_anonymous_if_available = bool(raw.get("require_anonymous_if_available", False))
    prefer_anonymous = bool(raw.get("prefer_anonymous", False))

    dotenv_vals = _read_dotenv(base_dir / ".env")
    email = os.environ.get("FB_EMAIL") or dotenv_vals.get("FB_EMAIL") or str(raw.get("email", ""))
    password = os.environ.get("FB_PASSWORD") or dotenv_vals.get("FB_PASSWORD") or str(raw.get("password", ""))
    email = email.strip()

    delay_cfg = raw.get("delay_seconds", {})
    delay_min = float(delay_cfg.get("min", 30))
    delay_max = float(delay_cfg.get("max", 75))
    if delay_min < 0 or delay_max < delay_min:
        raise ValueError(f"Invalid delay_seconds range: min={delay_min}, max={delay_max}")

    message = str(raw.get("message", "")).strip()
    message_file_raw = str(raw.get("message_file", "")).strip()
    if message_file_raw:
        message_file = Path(message_file_raw)
        if not message_file.is_absolute():
            message_file = (base_dir / message_file).resolve()
        if not message_file.is_file():
            raise FileNotFoundError(f"message_file does not exist: {message_file}")
        message = message_file.read_text(encoding="utf-8").strip()

    images: list[Path] = []
    for item in raw.get("images", []):
        img_path = Path(str(item))
        if not img_path.is_absolute():
            img_path = (base_dir / img_path).resolve()
        if not img_path.is_file():
            raise FileNotFoundError(f"Image file not found: {img_path}")
        images.append(img_path)

    if not message and not images:
        raise ValueError("Configuration must specify a non-empty 'message'/'message_file' or at least one image.")

    raw_groups = raw.get("groups", [])
    if not isinstance(raw_groups, list) or not raw_groups:
        raise ValueError("Configuration must include a non-empty 'groups' list.")

    groups: list[str] = []
    seen: set[str] = set()
    for entry in raw_groups:
        normalized = normalize_group_url(str(entry))
        if normalized not in seen:
            seen.add(normalized)
            groups.append(normalized)

    return PosterConfig(
        profile_dir=profile_dir,
        headless=headless,
        anonymous=anonymous,
        delay_min=delay_min,
        delay_max=delay_max,
        message=message,
        images=images,
        groups=groups,
        email=email,
        password=password,
        require_anonymous_if_available=require_anonymous_if_available,
        prefer_anonymous=prefer_anonymous,
    )


def detect_auth_or_checkpoint(page: Page) -> str | None:
    """Return a reason string if Facebook requires login, 2FA, or a security check."""
    current_url = page.url.lower()
    if "/login" in current_url or "login.php" in current_url:
        return "Facebook login required"
    if "/checkpoint" in current_url or "two_step_verification" in current_url:
        return "Facebook security checkpoint or 2FA verification required"

    login_form = page.locator("form[action*='login'], input[name='email'][type='text']")
    if login_form.count() > 0 and login_form.first.is_visible():
        return "Facebook login prompt visible on page"

    return None


def launch_browser_context(
    playwright_instance: Any,
    profile_dir: Path,
    headless: bool,
    browser_channel: str | None = "chrome",
) -> BrowserContext:
    """Launch a persistent Chromium/Chrome context using the saved user profile."""
    profile_dir.mkdir(parents=True, exist_ok=True)
    launch_kwargs: dict[str, Any] = {
        "user_data_dir": str(profile_dir),
        "headless": headless,
        "viewport": {"width": 1280, "height": 900},
        "args": ["--disable-notifications"],
    }
    if browser_channel:
        launch_kwargs["channel"] = browser_channel

    try:
        return playwright_instance.chromium.launch_persistent_context(**launch_kwargs)
    except Exception:
        if browser_channel:
            LOGGER.info("Chrome channel unavailable; falling back to bundled Chromium.")
            launch_kwargs.pop("channel", None)
            return playwright_instance.chromium.launch_persistent_context(**launch_kwargs)
        raise


def run_login_flow(profile_dir: Path, browser_channel: str | None = "chrome") -> int:
    """Open Facebook in a visible browser so the user can sign in manually."""
    with sync_playwright() as p:
        context = launch_browser_context(p, profile_dir, headless=False, browser_channel=browser_channel)
        try:
            page = context.pages[0] if context.pages else context.new_page()
            page.goto("https://www.facebook.com/", wait_until="domcontentloaded")
            print(
                "\nBrowser opened to Facebook.\n"
                "1. Log into your account (and complete any 2FA/checkpoint prompts).\n"
                "2. Once you see your Facebook feed, return here and press ENTER to save the session.\n"
            )
            input("Press ENTER after you are logged in...")
            issue = detect_auth_or_checkpoint(page)
            if issue:
                LOGGER.warning("Session still shows: %s", issue)
                return 1
            LOGGER.info("Login session saved to %s", profile_dir)
            return 0
        finally:
            context.close()


def _find_first_visible(candidates: list[Locator], timeout_ms: int = 8000) -> Locator | None:
    """Return the first locator from candidates that becomes visible within timeout_ms."""
    deadline = time.monotonic() + (timeout_ms / 1000.0)
    while time.monotonic() < deadline:
        for locator in candidates:
            try:
                if locator.count() > 0 and locator.first.is_visible():
                    return locator.first
            except Exception:
                continue
        time.sleep(0.25)
    return None


def _close_composer_dialog(page: Page) -> None:
    """Close an open composer dialog and discard unsaved changes if prompted."""
    page.keyboard.press("Escape")
    time.sleep(0.5)
    discard_btn = page.get_by_role("button", name=re.compile(r"^(Discard|Leave|Abandonner|Quitter|تجاهل|مغادرة)$", re.I))
    if discard_btn.count() > 0 and discard_btn.first.is_visible():
        discard_btn.first.click()


def _get_composer_dialog(page: Page, timeout_ms: int = 10000) -> Locator:
    """Return the visible dialog containing the post composer textbox."""
    deadline = time.monotonic() + (timeout_ms / 1000.0)
    while time.monotonic() < deadline:
        dialogs = page.locator("[role='dialog']")
        for idx in range(dialogs.count()):
            dlg = dialogs.nth(idx)
            try:
                if dlg.is_visible():
                    tb = dlg.locator("[role='textbox'][contenteditable='true']")
                    if tb.count() > 0 and tb.first.is_visible():
                        return dlg
            except Exception:
                continue
        time.sleep(0.25)
    raise RuntimeError("Post composer dialog did not open with an editable textbox.")


def _dismiss_anonymous_intro_if_present(page: Page) -> None:
    """Click through Facebook's anonymous-posting info modal if it appears."""
    deadline = time.monotonic() + 2.5
    while time.monotonic() < deadline:
        dialogs = page.locator("[role='dialog']")
        for idx in range(dialogs.count()):
            dlg = dialogs.nth(idx)
            try:
                if not dlg.is_visible():
                    continue
                # Skip actual composer dialogs that already have a textbox.
                if dlg.locator("[role='textbox'][contenteditable='true']").count() > 0:
                    continue
                for label in ANONYMOUS_CONFIRM_LABELS:
                    btn = dlg.get_by_role("button", name=label, exact=False)
                    if btn.count() > 0 and btn.first.is_visible():
                        btn.first.click()
                        time.sleep(0.8)
                        return
            except Exception:
                continue
        time.sleep(0.25)


def _has_anonymous_switch_text(dialog: Locator) -> bool:
    """Return True if the dialog displays a 'Post anonymously' label."""
    for label in ANONYMOUS_SWITCH_LABELS:
        loc = dialog.get_by_text(label, exact=False)
        if loc.count() > 0 and loc.first.is_visible():
            return True
    return False


def _is_anonymous_active(dialog: Locator) -> bool:
    """Return True if the composer dialog shows active anonymous posting state."""
    for label in ANONYMOUS_AUTHOR_LABELS:
        author_loc = dialog.get_by_text(label, exact=False)
        if author_loc.count() > 0 and author_loc.first.is_visible():
            return True

    for label in ANONYMOUS_SWITCH_LABELS:
        for role in ("switch", "checkbox"):
            ctrl = dialog.get_by_role(role, name=label, exact=False)
            if ctrl.count() > 0 and ctrl.first.is_visible():
                if ctrl.first.get_attribute("aria-checked") == "true":
                    return True

    if _has_anonymous_switch_text(dialog):
        checked_switch = dialog.locator("[role='switch'][aria-checked='true'], [role='checkbox'][aria-checked='true']")
        if checked_switch.count() > 0 and checked_switch.first.is_visible():
            return True
    return False


def _ensure_anonymous_in_dialog(page: Page, dialog: Locator) -> None:
    """Enable anonymous mode in the open composer dialog or abort safely."""
    if _is_anonymous_active(dialog):
        return

    switch_candidates: list[Locator] = []
    for label in ANONYMOUS_SWITCH_LABELS:
        switch_candidates.append(dialog.get_by_role("switch", name=label, exact=False))
        switch_candidates.append(dialog.get_by_role("checkbox", name=label, exact=False))
        switch_candidates.append(dialog.locator(f"input[type='checkbox'][aria-label*='{label}']"))
        switch_candidates.append(dialog.locator(f"[role='button']:has-text('{label}')"))

    if _has_anonymous_switch_text(dialog):
        switch_candidates.append(dialog.locator("[role='switch'], [role='checkbox']"))

    toggle = _find_first_visible(switch_candidates, timeout_ms=4000)
    if toggle is not None:
        if toggle.get_attribute("aria-checked") != "true":
            toggle.click()
            time.sleep(0.5)
            _dismiss_anonymous_intro_if_present(page)
        if _is_anonymous_active(dialog):
            return
        if toggle.get_attribute("aria-checked") == "true":
            return

    _close_composer_dialog(page)
    raise AnonymousNotAvailableError(
        "Anonymous posting is not available in this group; skipped."
    )


def _has_anonymous_option_in_dialog(dialog: Locator) -> bool:
    """Return True if the open composer dialog exposes anonymous posting."""
    if _is_anonymous_active(dialog) or _has_anonymous_switch_text(dialog):
        return True
    for label in ANONYMOUS_SWITCH_LABELS:
        for role in ("switch", "checkbox", "button"):
            ctrl = dialog.get_by_role(role, name=label, exact=False)
            if ctrl.count() > 0 and ctrl.first.is_visible():
                return True
    return False


def _open_group_composer(
    page: Page,
    anonymous: bool = False,
    require_anonymous_if_available: bool = False,
    prefer_anonymous: bool = False,
) -> Locator:
    """Open the group's post composer dialog, enforcing anonymous posting rules."""
    main = page.locator("[role='main']")

    anon_candidates: list[Locator] = []
    for label in ANONYMOUS_TRIGGER_LABELS:
        anon_candidates.append(main.get_by_role("button", name=label, exact=False))
        anon_candidates.append(main.locator(f"[role='button']:has-text('{label}')"))

    if anonymous or prefer_anonymous:
        anon_trigger = _find_first_visible(anon_candidates, timeout_ms=4000)
        if anon_trigger is not None:
            anon_trigger.click()
            time.sleep(0.8)
            _dismiss_anonymous_intro_if_present(page)
            dialog = _get_composer_dialog(page, timeout_ms=10000)
            try:
                _ensure_anonymous_in_dialog(page, dialog)
                return dialog
            except AnonymousNotAvailableError:
                if anonymous:
                    raise
                return _open_group_composer(page, anonymous=False, require_anonymous_if_available=False, prefer_anonymous=False)
    elif require_anonymous_if_available:
        anon_trigger = _find_first_visible(anon_candidates, timeout_ms=2000)
        if anon_trigger is not None:
            raise AnonymousNotAvailableError(
                "Group has anonymous posting active; skipped because anonymous option is disabled."
            )

    trigger_candidates: list[Locator] = []
    for label in COMPOSER_TRIGGER_LABELS:
        trigger_candidates.append(main.get_by_role("button", name=label, exact=False))
        trigger_candidates.append(main.locator(f"[role='button']:has-text('{label}')"))

    trigger = _find_first_visible(trigger_candidates, timeout_ms=12000)
    if trigger is None:
        raise RuntimeError(
            "Could not find the group post composer button. "
            "Verify that you are a member of this group and allowed to post."
        )

    trigger.click()
    dialog = _get_composer_dialog(page, timeout_ms=10000)
    if anonymous:
        _ensure_anonymous_in_dialog(page, dialog)
    elif prefer_anonymous:
        if _has_anonymous_option_in_dialog(dialog):
            _ensure_anonymous_in_dialog(page, dialog)
    elif require_anonymous_if_available and _has_anonymous_option_in_dialog(dialog):
        _close_composer_dialog(page)
        raise AnonymousNotAvailableError(
            "Group has anonymous posting active; skipped because anonymous option is disabled."
        )
    return dialog


def _type_post_message(page: Page, dialog: Locator, message: str) -> None:
    """Focus the composer textbox and enter multi-line post text."""
    textbox = dialog.locator("[role='textbox'][contenteditable='true']").first
    textbox.wait_for(state="visible", timeout=10000)
    textbox.click()

    lines = message.splitlines()
    for idx, line in enumerate(lines):
        if line:
            page.keyboard.insert_text(line)
        if idx < len(lines) - 1:
            page.keyboard.press("Shift+Enter")


def _attach_images(dialog: Locator, images: list[Path]) -> None:
    """Attach image files to the open composer dialog."""
    if not images:
        return

    file_input = dialog.locator("input[type='file'][accept*='image' i]").first
    if file_input.count() == 0:
        photo_candidates = [dialog.get_by_role("button", name=label, exact=False) for label in PHOTO_BUTTON_LABELS]
        photo_btn = _find_first_visible(photo_candidates, timeout_ms=5000)
        if photo_btn is not None:
            photo_btn.click()
            time.sleep(0.5)
        file_input = dialog.locator("input[type='file']").first

    if file_input.count() == 0:
        raise RuntimeError("Could not locate image upload input inside the post composer.")

    file_input.set_input_files([str(p) for p in images])
    # Allow preview thumbnails / upload request to settle before submitting.
    time.sleep(3.0)


def _submit_composer(dialog: Locator) -> None:
    """Click the Post/Publier submit button and wait for the dialog to close."""
    submit_candidates = [dialog.get_by_role("button", name=name, exact=True) for name in SUBMIT_BUTTON_NAMES]
    submit_btn = _find_first_visible(submit_candidates, timeout_ms=10000)
    if submit_btn is None:
        raise RuntimeError("Could not locate the Post/Publier submit button in composer.")

    if submit_btn.get_attribute("aria-disabled") == "true" or submit_btn.is_disabled():
        raise RuntimeError("Submit button is disabled; post content or upload may not be ready.")

    submit_btn.click()
    try:
        dialog.wait_for(state="hidden", timeout=20000)
    except PlaywrightTimeoutError as exc:
        raise RuntimeError(
            "Composer dialog remained open after clicking Post; "
            "the post may require manual review or encountered an error."
        ) from exc


def _login_with_credentials(page: Page, email: str, password: str, target_url: str) -> None:
    """Sign into Facebook using configured credentials and return to target_url."""
    LOGGER.info("Attempting Facebook sign-in with configured email...")
    email_input = page.locator("input[name='email']").first
    if email_input.count() == 0 or not email_input.is_visible():
        page.goto("https://www.facebook.com/", wait_until="domcontentloaded", timeout=30000)
        time.sleep(1.5)
        email_input = page.locator("input[name='email']").first

    email_input.wait_for(state="visible", timeout=10000)
    pass_input = page.locator("input[name='pass']").first
    pass_input.wait_for(state="visible", timeout=10000)

    email_input.fill(email)
    pass_input.fill(password)

    login_btn = page.locator("button[name='login'], [data-testid='royal-login-button'], input[type='submit']").first
    if login_btn.count() > 0 and login_btn.is_visible():
        login_btn.click()
    else:
        pass_input.press("Enter")

    page.wait_for_load_state("domcontentloaded", timeout=30000)
    time.sleep(4.0)

    post_login_issue = detect_auth_or_checkpoint(page)
    if post_login_issue:
        raise PermissionError(
            f"{post_login_issue} after credential login. "
            "Run `.venv/bin/python fb_poster.py --login` to complete any 2FA or verification manually."
        )

    page.goto(target_url, wait_until="domcontentloaded", timeout=30000)
    time.sleep(2.0)


def post_to_group(page: Page, group_url: str, config: PosterConfig, dry_run: bool) -> dict[str, Any]:
    """Navigate to one Facebook group and publish (or dry-run) the configured post."""
    LOGGER.info("Opening group: %s", group_url)
    page.goto(group_url, wait_until="domcontentloaded", timeout=30000)
    time.sleep(2.0)

    auth_issue = detect_auth_or_checkpoint(page)
    if auth_issue:
        if "login" in auth_issue.lower() and config.email and config.password:
            _login_with_credentials(page, config.email, config.password, target_url=group_url)
            auth_issue = detect_auth_or_checkpoint(page)
        if auth_issue:
            raise PermissionError(
                f"{auth_issue}. Run `.venv/bin/python fb_poster.py --login` or set email/password in config.json or .env."
            )

    dialog = _open_group_composer(
        page,
        anonymous=config.anonymous,
        require_anonymous_if_available=config.require_anonymous_if_available,
        prefer_anonymous=config.prefer_anonymous,
    )
    if config.message:
        _type_post_message(page, dialog, config.message)
    if config.images:
        _attach_images(dialog, config.images)

    if dry_run:
        LOGGER.info("[DRY RUN] Composer filled for %s (anonymous=%s); closing without posting.", group_url, config.anonymous)
        _close_composer_dialog(page)
        return {"group": group_url, "status": "dry_run_ok", "anonymous": config.anonymous}

    if config.anonymous and not _is_anonymous_active(dialog):
        _close_composer_dialog(page)
        raise AnonymousNotAvailableError(
            "Anonymous mode could not be confirmed before posting; skipped."
        )

    _submit_composer(dialog)
    LOGGER.info("Successfully posted to %s (anonymous=%s)", group_url, config.anonymous)
    return {"group": group_url, "status": "posted", "anonymous": config.anonymous}


def run_posting(
    config: PosterConfig,
    dry_run: bool,
    browser_channel: str | None = "chrome",
    stop_event: threading.Event | None = None,
    on_progress: Callable[[int, int, str, dict[str, Any] | None], None] | None = None,
) -> list[dict[str, Any]]:
    """Run the posting workflow across all configured groups and return per-group results."""
    results: list[dict[str, Any]] = []
    total = len(config.groups)
    with sync_playwright() as p:
        context = launch_browser_context(p, config.profile_dir, headless=config.headless, browser_channel=browser_channel)
        try:
            page = context.pages[0] if context.pages else context.new_page()
            for index, group_url in enumerate(config.groups):
                if stop_event is not None and stop_event.is_set():
                    LOGGER.info("Stop requested; halting before %s", group_url)
                    break

                if on_progress is not None:
                    on_progress(index, total, group_url, None)

                skipped = False
                try:
                    result = post_to_group(page, group_url, config, dry_run=dry_run)
                    results.append(result)
                except AnonymousNotAvailableError as skip_err:
                    LOGGER.warning("Skipping %s: %s", group_url, skip_err)
                    results.append({"group": group_url, "status": "skipped", "reason": str(skip_err)})
                    skipped = True
                except PermissionError as auth_err:
                    LOGGER.error("Stopping immediately: %s", auth_err)
                    results.append({"group": group_url, "status": "blocked", "error": str(auth_err)})
                    if on_progress is not None:
                        on_progress(index, total, group_url, results[-1])
                    break
                except Exception as exc:
                    LOGGER.error("Failed for %s: %s", group_url, exc)
                    results.append({"group": group_url, "status": "failed", "error": str(exc)})

                if on_progress is not None:
                    on_progress(index, total, group_url, results[-1])

                if stop_event is not None and stop_event.is_set():
                    LOGGER.info("Stop requested; halting after %s", group_url)
                    break

                if index < total - 1:
                    delay = min(2.0, config.delay_max) if skipped else random.uniform(config.delay_min, config.delay_max)
                    LOGGER.info("Waiting %.1f seconds before next group...", delay)
                    if stop_event is not None:
                        if stop_event.wait(delay):
                            LOGGER.info("Stop requested during inter-group delay.")
                            break
                    else:
                        time.sleep(delay)
        finally:
            context.close()
    return results


def write_run_report(results: list[dict[str, Any]], logs_dir: Path) -> Path:
    """Persist a timestamped JSON execution report inside logs_dir."""
    logs_dir.mkdir(parents=True, exist_ok=True)
    stamp = datetime.now(timezone.utc).strftime("%Y%m%dT%H%M%SZ")
    report_path = logs_dir / f"run_{stamp}.json"
    report_path.write_text(json.dumps(results, indent=2), encoding="utf-8")
    return report_path


def parse_args(argv: list[str] | None = None) -> argparse.Namespace:
    """Parse command-line arguments."""
    parser = argparse.ArgumentParser(description="Post a message (and optional images) to Facebook groups.")
    parser.add_argument("--config", type=Path, default=Path("config.json"), help="Path to JSON configuration file.")
    parser.add_argument("--login", action="store_true", help="Open Facebook to sign in manually and save the session.")
    parser.add_argument(
        "--profile-dir",
        type=Path,
        default=Path("./fb_profile"),
        help="Browser profile directory used with --login when config.json is not present.",
    )
    parser.add_argument("--dry-run", action="store_true", help="Fill the composer in each group without clicking Post.")
    parser.add_argument(
        "--anonymous",
        action=argparse.BooleanOptionalAction,
        default=None,
        help="Post anonymously in groups (overrides config 'anonymous' setting).",
    )
    parser.add_argument(
        "--require-anonymous-if-available",
        action=argparse.BooleanOptionalAction,
        default=None,
        help="Do not post without anonymous in groups that have anonymous posting active.",
    )
    parser.add_argument("--delay-min", type=float, default=None, help="Minimum delay in seconds between posts.")
    parser.add_argument("--delay-max", type=float, default=None, help="Maximum delay in seconds between posts.")
    parser.add_argument("--headless", action="store_true", help="Override config to run browser headlessly.")
    parser.add_argument("--chromium", action="store_true", help="Use bundled Playwright Chromium instead of Google Chrome.")
    return parser.parse_args(argv)


def main(argv: list[str] | None = None) -> int:
    """CLI entry point."""
    logging.basicConfig(level=logging.INFO, format="%(asctime)s [%(levelname)s] %(message)s")
    args = parse_args(argv)
    channel = None if args.chromium else "chrome"

    if args.login:
        profile_dir = args.profile_dir.resolve()
        if args.config.exists():
            raw = json.loads(args.config.read_text(encoding="utf-8"))
            cfg_profile = Path(raw.get("profile_dir", "./fb_profile"))
            profile_dir = cfg_profile if cfg_profile.is_absolute() else (args.config.parent.resolve() / cfg_profile)
        return run_login_flow(profile_dir=profile_dir, browser_channel=channel)

    config = load_config(args.config)
    if args.headless:
        config = replace(config, headless=True)
    if args.anonymous is not None:
        config = replace(config, anonymous=args.anonymous)
    if args.require_anonymous_if_available is not None:
        config = replace(config, require_anonymous_if_available=args.require_anonymous_if_available)
    if args.delay_min is not None or args.delay_max is not None:
        delay_min = config.delay_min if args.delay_min is None else args.delay_min
        delay_max = config.delay_max if args.delay_max is None else args.delay_max
        if delay_min < 0 or delay_max < delay_min:
            raise ValueError(f"Invalid delay range: min={delay_min}, max={delay_max}")
        config = replace(config, delay_min=delay_min, delay_max=delay_max)

    results = run_posting(config, dry_run=args.dry_run, browser_channel=channel)
    report_path = write_run_report(results, args.config.parent.resolve() / "logs")
    LOGGER.info("Saved run report to %s", report_path)

    failed_or_blocked = [r for r in results if r["status"] in ("failed", "blocked")]
    return 1 if failed_or_blocked else 0


if __name__ == "__main__":
    sys.exit(main())
