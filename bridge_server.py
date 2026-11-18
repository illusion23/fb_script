#!/usr/bin/env python3
"""Lightweight HTTP bridge server wrapping fb_poster.py for the Flutter mobile app."""

from __future__ import annotations

import argparse
import base64
import json
import logging
import tempfile
import threading
from datetime import datetime, timezone
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from typing import Any

from fb_poster import (
    PosterConfig,
    normalize_group_url,
    run_login_flow,
    run_posting,
    write_run_report,
)

BASE_DIR = Path(__file__).resolve().parent
LOGS_DIR = BASE_DIR / "logs"
DEFAULT_PROFILE_DIR = BASE_DIR / "fb_profile"


class _LogCaptureHandler(logging.Handler):
    """Captures fb_poster log records into an in-memory ring buffer."""

    def __init__(self, state: BridgeState) -> None:
        super().__init__()
        self._state = state

    def emit(self, record: logging.LogRecord) -> None:
        msg = self.format(record)
        self._state.append_log(msg)


class BridgeState:
    """Thread-safe execution state for the poster bridge server."""

    def __init__(self) -> None:
        self._lock = threading.Lock()
        self.running: bool = False
        self.stopping: bool = False
        self.stop_event: threading.Event | None = None
        self.current_index: int = 0
        self.total_groups: int = 0
        self.current_group: str = ""
        self.logs: list[str] = []
        self.results: list[dict[str, Any]] = []
        self.started_at: str | None = None
        self.ended_at: str | None = None
        self.last_status: str = "idle"
        self.last_error: str | None = None

    def append_log(self, line: str) -> None:
        with self._lock:
            self.logs.append(line)
            if len(self.logs) > 250:
                self.logs = self.logs[-250:]

    def snapshot(self) -> dict[str, Any]:
        with self._lock:
            return {
                "running": self.running,
                "stopping": self.stopping,
                "current_index": self.current_index,
                "total_groups": self.total_groups,
                "current_group": self.current_group,
                "logs": list(self.logs),
                "results": list(self.results),
                "started_at": self.started_at,
                "ended_at": self.ended_at,
                "last_status": self.last_status,
                "last_error": self.last_error,
            }

    def start_run(self, payload: dict[str, Any]) -> None:
        with self._lock:
            if self.running:
                raise RuntimeError("A posting run is already in progress.")

            raw_groups = payload.get("groups", [])
            if not isinstance(raw_groups, list) or not raw_groups:
                raise ValueError("At least one Facebook group URL is required.")

            groups: list[str] = []
            seen: set[str] = set()
            for g in raw_groups:
                norm = normalize_group_url(str(g))
                if norm not in seen:
                    seen.add(norm)
                    groups.append(norm)

            message = str(payload.get("message", "")).strip()
            images_b64 = payload.get("images_base64", [])
            if not message and not images_b64:
                raise ValueError("Post must contain a message or at least one image.")

            delay_min = float(payload.get("delay_min", 5))
            delay_max = float(payload.get("delay_max", 12))
            if delay_min < 0 or delay_max < delay_min:
                raise ValueError("Invalid delay range.")

            anonymous = bool(payload.get("anonymous", True))
            prefer_anonymous = bool(payload.get("prefer_anonymous", False))
            require_anonymous_if_available = bool(payload.get("require_anonymous_if_available", False))
            dry_run = bool(payload.get("dry_run", False))
            headless = bool(payload.get("headless", False))
            email = str(payload.get("email", "")).strip()
            password = str(payload.get("password", ""))

            self.running = True
            self.stopping = False
            self.stop_event = threading.Event()
            self.current_index = 0
            self.total_groups = len(groups)
            self.current_group = ""
            self.logs = []
            self.results = []
            self.started_at = datetime.now(timezone.utc).isoformat()
            self.ended_at = None
            self.last_status = "running"
            self.last_error = None

        thread = threading.Thread(
            target=self._execute_run,
            args=(
                email,
                password,
                message,
                images_b64,
                groups,
                anonymous,
                prefer_anonymous,
                require_anonymous_if_available,
                dry_run,
                headless,
                delay_min,
                delay_max,
            ),
            daemon=True,
        )
        thread.start()

    def _execute_run(
        self,
        email: str,
        password: str,
        message: str,
        images_b64: list[dict[str, str]],
        groups: list[str],
        anonymous: bool,
        prefer_anonymous: bool,
        require_anonymous_if_available: bool,
        dry_run: bool,
        headless: bool,
        delay_min: float,
        delay_max: float,
    ) -> None:
        temp_dir = tempfile.TemporaryDirectory(prefix="fb_poster_imgs_")
        try:
            image_paths: list[Path] = []
            for idx, item in enumerate(images_b64):
                if isinstance(item, dict) and item.get("data"):
                    name = Path(str(item.get("name", f"image_{idx}.jpg"))).name
                    out_path = Path(temp_dir.name) / f"{idx}_{name}"
                    out_path.write_bytes(base64.b64decode(item["data"]))
                    image_paths.append(out_path)

            cfg = PosterConfig(
                profile_dir=DEFAULT_PROFILE_DIR,
                headless=headless,
                anonymous=anonymous,
                delay_min=delay_min,
                delay_max=delay_max,
                message=message,
                images=image_paths,
                groups=groups,
                email=email,
                password=password,
                require_anonymous_if_available=require_anonymous_if_available,
                prefer_anonymous=prefer_anonymous,
            )

            def on_progress(index: int, total: int, group_url: str, result: dict[str, Any] | None) -> None:
                with self._lock:
                    self.current_index = index + (1 if result is not None else 0)
                    self.total_groups = total
                    self.current_group = group_url
                    if result is not None:
                        self.results.append(result)

            results = run_posting(
                cfg,
                dry_run=dry_run,
                browser_channel="chrome",
                stop_event=self.stop_event,
                on_progress=on_progress,
            )
            write_run_report(results, LOGS_DIR)

            with self._lock:
                self.results = results
                if self.stopping or (self.stop_event and self.stop_event.is_set()):
                    self.last_status = "stopped"
                elif any(r.get("status") == "blocked" for r in results):
                    self.last_status = "blocked"
                elif any(r.get("status") == "failed" for r in results):
                    self.last_status = "failed"
                elif dry_run:
                    self.last_status = "dry_run"
                else:
                    self.last_status = "completed"
        except Exception as exc:
            self.append_log(f"[ERROR] {exc}")
            with self._lock:
                self.last_status = "failed"
                self.last_error = str(exc)
        finally:
            temp_dir.cleanup()
            with self._lock:
                self.running = False
                self.stopping = False
                self.ended_at = datetime.now(timezone.utc).isoformat()

    def request_stop(self) -> bool:
        with self._lock:
            if not self.running:
                return False
            self.stopping = True
            if self.stop_event is not None:
                self.stop_event.set()
            self.logs.append("[INFO] Stop requested by user...")
            return True


STATE = BridgeState()


def list_history_reports() -> list[dict[str, Any]]:
    """Load saved run_*.json history files from logs/ newest first."""
    if not LOGS_DIR.is_dir():
        return []
    items: list[dict[str, Any]] = []
    for path in sorted(LOGS_DIR.glob("run_*.json"), reverse=True):
        try:
            results = json.loads(path.read_text(encoding="utf-8"))
            items.append({"filename": path.name, "results": results})
        except Exception:
            continue
    return items


class BridgeHandler(BaseHTTPRequestHandler):
    """HTTP request handler for mobile app <-> fb_poster.py bridge."""

    def _send_json(self, code: int, payload: Any) -> None:
        body = json.dumps(payload).encode("utf-8")
        self.send_response(code)
        self.send_header("Content-Type", "application/json; charset=utf-8")
        self.send_header("Access-Control-Allow-Origin", "*")
        self.send_header("Access-Control-Allow-Methods", "GET, POST, OPTIONS")
        self.send_header("Access-Control-Allow-Headers", "Content-Type")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def _read_json(self) -> dict[str, Any]:
        length = int(self.headers.get("Content-Length", "0"))
        if length <= 0:
            return {}
        raw = self.rfile.read(length)
        return json.loads(raw.decode("utf-8"))

    def do_OPTIONS(self) -> None:
        self._send_json(200, {"ok": True})

    def do_GET(self) -> None:
        if self.path == "/health":
            self._send_json(200, {"ok": True})
            return
        if self.path == "/status":
            self._send_json(200, STATE.snapshot())
            return
        if self.path == "/history":
            self._send_json(200, {"reports": list_history_reports()})
            return
        self._send_json(404, {"error": "Not found"})

    def do_POST(self) -> None:
        if self.path == "/start":
            try:
                payload = self._read_json()
                STATE.start_run(payload)
                self._send_json(202, {"started": True})
            except RuntimeError as exc:
                self._send_json(409, {"error": str(exc)})
            except ValueError as exc:
                self._send_json(400, {"error": str(exc)})
            except Exception as exc:
                self._send_json(500, {"error": str(exc)})
            return

        if self.path == "/stop":
            stopped = STATE.request_stop()
            self._send_json(200, {"stopping": stopped})
            return

        if self.path == "/login":
            threading.Thread(
                target=lambda: run_login_flow(profile_dir=DEFAULT_PROFILE_DIR, browser_channel="chrome"),
                daemon=True,
            ).start()
            self._send_json(202, {"launched": True})
            return

        self._send_json(404, {"error": "Not found"})

    def log_message(self, format: str, *args: Any) -> None:
        return


def main() -> None:
    parser = argparse.ArgumentParser(description="HTTP bridge server for FB Group Poster mobile app.")
    parser.add_argument("--host", default="0.0.0.0", help="Host interface to bind (default: 0.0.0.0).")
    parser.add_argument("--port", type=int, default=8765, help="Port to listen on (default: 8765).")
    args = parser.parse_args()

    fb_logger = logging.getLogger("fb_poster")
    fb_logger.setLevel(logging.INFO)
    handler = _LogCaptureHandler(STATE)
    handler.setFormatter(logging.Formatter("%(asctime)s [%(levelname)s] %(message)s"))
    fb_logger.addHandler(handler)

    server = ThreadingHTTPServer((args.host, args.port), BridgeHandler)
    print(f"FB Poster Bridge Server listening on http://{args.host}:{args.port}")
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        print("\nShutting down bridge server.")
        server.shutdown()


if __name__ == "__main__":
    main()
