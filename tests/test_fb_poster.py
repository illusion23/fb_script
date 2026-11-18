"""Unit tests for fb_poster configuration, validation, and checkpoint detection."""

from __future__ import annotations

import json
from pathlib import Path
from unittest.mock import MagicMock

import pytest

from fb_poster import (
    AnonymousNotAvailableError,
    PosterConfig,
    _ensure_anonymous_in_dialog,
    detect_auth_or_checkpoint,
    load_config,
    normalize_group_url,
    parse_args,
    run_posting,
    write_run_report,
)


def test_normalize_group_url_handles_variants() -> None:
    assert normalize_group_url("https://www.facebook.com/groups/123456789/about") == (
        "https://www.facebook.com/groups/123456789/"
    )
    assert normalize_group_url("https://m.facebook.com/groups/my-group?ref=share") == (
        "https://www.facebook.com/groups/my-group/"
    )


def test_normalize_group_url_rejects_invalid() -> None:
    with pytest.raises(ValueError):
        normalize_group_url("https://www.facebook.com/pages/something")
    with pytest.raises(ValueError):
        normalize_group_url("https://example.com/groups/123")
    with pytest.raises(ValueError, match="Placeholder"):
        normalize_group_url("https://www.facebook.com/groups/YOUR_GROUP_ID_1/")


def test_load_config_valid_with_message_file_and_images(tmp_path: Path) -> None:
    msg_file = tmp_path / "post.txt"
    msg_file.write_text("Line 1\nLine 2", encoding="utf-8")

    img_file = tmp_path / "photo.png"
    img_file.write_bytes(b"fake-png")

    cfg_path = tmp_path / "config.json"
    cfg_path.write_text(
        json.dumps(
            {
                "profile_dir": "./profile",
                "headless": True,
                "anonymous": True,
                "delay_seconds": {"min": 10, "max": 20},
                "message_file": "post.txt",
                "images": ["photo.png"],
                "groups": [
                    "https://www.facebook.com/groups/111/",
                    "https://m.facebook.com/groups/111",
                    "https://www.facebook.com/groups/222",
                ],
            }
        ),
        encoding="utf-8",
    )

    cfg = load_config(cfg_path)
    assert cfg.profile_dir == (tmp_path / "profile").resolve()
    assert cfg.headless is True
    assert cfg.anonymous is True
    assert cfg.delay_min == 10.0
    assert cfg.delay_max == 20.0
    assert cfg.message == "Line 1\nLine 2"
    assert cfg.images == [img_file.resolve()]
    assert cfg.groups == [
        "https://www.facebook.com/groups/111/",
        "https://www.facebook.com/groups/222/",
    ]


def test_load_config_rejects_missing_content_and_bad_delays(tmp_path: Path) -> None:
    cfg_path = tmp_path / "config.json"
    cfg_path.write_text(
        json.dumps({"message": "", "images": [], "groups": ["https://www.facebook.com/groups/111/"]}),
        encoding="utf-8",
    )
    with pytest.raises(ValueError, match="message"):
        load_config(cfg_path)

    cfg_path.write_text(
        json.dumps(
            {
                "message": "hello",
                "delay_seconds": {"min": 50, "max": 10},
                "groups": ["https://www.facebook.com/groups/111/"],
            }
        ),
        encoding="utf-8",
    )
    with pytest.raises(ValueError, match="delay_seconds"):
        load_config(cfg_path)


def test_detect_auth_or_checkpoint() -> None:
    login_page = MagicMock()
    login_page.url = "https://www.facebook.com/login/?next=..."
    assert detect_auth_or_checkpoint(login_page) == "Facebook login required"

    checkpoint_page = MagicMock()
    checkpoint_page.url = "https://www.facebook.com/checkpoint/12345/"
    assert "checkpoint" in (detect_auth_or_checkpoint(checkpoint_page) or "").lower()

    ok_page = MagicMock()
    ok_page.url = "https://www.facebook.com/groups/12345/"
    ok_page.locator.return_value.count.return_value = 0
    assert detect_auth_or_checkpoint(ok_page) is None


def test_write_run_report(tmp_path: Path) -> None:
    results = [{"group": "https://www.facebook.com/groups/111/", "status": "posted"}]
    report = write_run_report(results, tmp_path / "logs")
    assert report.exists()
    assert json.loads(report.read_text(encoding="utf-8")) == results


def test_parse_args_anonymous_flag() -> None:
    assert parse_args([]).anonymous is None
    assert parse_args(["--anonymous"]).anonymous is True
    assert parse_args(["--no-anonymous"]).anonymous is False
    parsed_delays = parse_args(["--delay-min", "2", "--delay-max", "5"])
    assert parsed_delays.delay_min == 2.0
    assert parsed_delays.delay_max == 5.0


def test_ensure_anonymous_in_dialog_aborts_when_unavailable() -> None:
    page = MagicMock()
    dialog = MagicMock()
    empty_loc = MagicMock()
    empty_loc.count.return_value = 0
    dialog.get_by_text.return_value = empty_loc
    dialog.get_by_role.return_value = empty_loc
    dialog.locator.return_value = empty_loc
    page.get_by_role.return_value = empty_loc

    with pytest.raises(AnonymousNotAvailableError, match="Anonymous posting is not available"):
        _ensure_anonymous_in_dialog(page, dialog)


def test_run_posting_skips_group_without_anonymous_and_continues(tmp_path: Path, monkeypatch: pytest.MonkeyPatch) -> None:
    cfg = PosterConfig(
        profile_dir=tmp_path / "profile",
        headless=True,
        anonymous=True,
        delay_min=0.0,
        delay_max=0.0,
        message="hello",
        images=[],
        groups=[
            "https://www.facebook.com/groups/111/",
            "https://www.facebook.com/groups/222/",
        ],
    )

    mock_ctx = MagicMock()
    mock_ctx.pages = [MagicMock()]
    mock_pw = MagicMock()
    mock_pw.__enter__.return_value = mock_pw

    monkeypatch.setattr("fb_poster.sync_playwright", lambda: mock_pw)
    monkeypatch.setattr("fb_poster.launch_browser_context", lambda *args, **kwargs: mock_ctx)
    monkeypatch.setattr("fb_poster.time.sleep", lambda _s: None)

    def fake_post(page, group_url, config, dry_run):
        if "111" in group_url:
            raise AnonymousNotAvailableError("Anonymous posting is not available in this group; skipped.")
        return {"group": group_url, "status": "posted", "anonymous": True}

    monkeypatch.setattr("fb_poster.post_to_group", fake_post)

    results = run_posting(cfg, dry_run=False)
    assert results == [
        {
            "group": "https://www.facebook.com/groups/111/",
            "status": "skipped",
            "reason": "Anonymous posting is not available in this group; skipped.",
        },
        {
            "group": "https://www.facebook.com/groups/222/",
            "status": "posted",
            "anonymous": True,
        },
    ]


def test_load_config_reads_credentials_from_dotenv_and_redacts_repr(tmp_path: Path, monkeypatch: pytest.MonkeyPatch) -> None:
    monkeypatch.delenv("FB_EMAIL", raising=False)
    monkeypatch.delenv("FB_PASSWORD", raising=False)

    (tmp_path / ".env").write_text('FB_EMAIL="user@example.com"\nFB_PASSWORD="secret-pw"\n', encoding="utf-8")
    cfg_path = tmp_path / "config.json"
    cfg_path.write_text(
        json.dumps(
            {
                "email": "fallback@example.com",
                "password": "fallback-pw",
                "message": "hello",
                "groups": ["https://www.facebook.com/groups/111/"],
            }
        ),
        encoding="utf-8",
    )

    cfg = load_config(cfg_path)
    assert cfg.email == "user@example.com"
    assert cfg.password == "secret-pw"
    assert "secret-pw" not in repr(cfg)


def test_open_group_composer_blocks_non_anonymous_when_anonymous_active(monkeypatch: pytest.MonkeyPatch) -> None:
    from fb_poster import _open_group_composer

    page = MagicMock()
    anon_trigger = MagicMock()
    monkeypatch.setattr("fb_poster._find_first_visible", lambda candidates, timeout_ms=4000: anon_trigger)

    with pytest.raises(AnonymousNotAvailableError, match="anonymous"):
        _open_group_composer(page, anonymous=False, require_anonymous_if_available=True)



