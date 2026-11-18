"""Unit tests for bridge_server state management and HTTP endpoints."""

from __future__ import annotations

import json
import threading
import time
from pathlib import Path
from unittest.mock import patch

import bridge_server


def test_bridge_state_start_and_stop(tmp_path: Path) -> None:
    state = bridge_server.BridgeState()

    def fake_run_posting(cfg, dry_run, browser_channel="chrome", stop_event=None, on_progress=None):
        if on_progress:
            on_progress(0, len(cfg.groups), cfg.groups[0], None)
        assert stop_event is not None
        stop_event.wait(timeout=5.0)
        res = [{"group": cfg.groups[0], "status": "posted", "anonymous": cfg.anonymous}]
        if on_progress:
            on_progress(0, len(cfg.groups), cfg.groups[0], res[0])
        return res

    with patch.object(bridge_server, "run_posting", side_effect=fake_run_posting), \
         patch.object(bridge_server, "LOGS_DIR", tmp_path):
        state.start_run(
            {
                "email": "user@example.com",
                "password": "pw",
                "message": "Hello group",
                "groups": ["https://www.facebook.com/groups/111/"],
                "anonymous": True,
                "dry_run": False,
            }
        )
        time.sleep(0.1)
        snap = state.snapshot()
        assert snap["running"] is True
        assert state.request_stop() is True

        deadline = time.monotonic() + 3.0
        while time.monotonic() < deadline and state.snapshot()["running"]:
            time.sleep(0.05)

        final = state.snapshot()
        assert final["running"] is False
        assert final["last_status"] == "stopped"
        assert len(list(tmp_path.glob("run_*.json"))) == 1


def test_list_history_reports(tmp_path: Path) -> None:
    report = tmp_path / "run_20261118T142749Z.json"
    report.write_text(
        json.dumps([{"group": "https://www.facebook.com/groups/111/", "status": "posted"}]),
        encoding="utf-8",
    )
    with patch.object(bridge_server, "LOGS_DIR", tmp_path):
        reports = bridge_server.list_history_reports()
        assert len(reports) == 1
        assert reports[0]["filename"] == "run_20261118T142749Z.json"
