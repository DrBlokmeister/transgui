#!/usr/bin/env python3
"""Measure Transmission JSON-RPC latency without starting TransGUI."""

from __future__ import annotations

import argparse
import base64
import csv
import json
import os
import statistics
import time
import urllib.error
import urllib.request
from pathlib import Path
from typing import Any

DEFAULT_SAMPLES = 5
DEFAULT_RPC_URL = ""
DEFAULT_RPC_USERNAME = ""
DEFAULT_RPC_PASSWORD = ""

# Kept in sync with TRpcThread.GetTorrents. Configured visible fields are added
# by TransGUI at runtime, so this captures its fixed baseline request only.
TORRENT_FIELDS = [
    "id", "name", "status", "errorString", "announceResponse",
    "recheckProgress", "sizeWhenDone", "leftUntilDone", "rateDownload",
    "rateUpload", "trackerStats", "metadataPercentComplete",
]


def load_env_file(path: Path) -> None:
    if not path.is_file():
        return
    for line in path.read_text(encoding="utf-8").splitlines():
        line = line.strip()
        if not line or line.startswith("#") or "=" not in line:
            continue
        key, value = line.split("=", 1)
        os.environ.setdefault(key.strip(), value.strip().strip('"').strip("'"))


def percentile(values: list[float], fraction: float) -> float:
    ordered = sorted(values)
    if len(ordered) == 1:
        return ordered[0]
    position = (len(ordered) - 1) * fraction
    lower = int(position)
    upper = min(lower + 1, len(ordered) - 1)
    return ordered[lower] + (ordered[upper] - ordered[lower]) * (position - lower)


class TransmissionRpc:
    def __init__(self, url: str, username: str, password: str) -> None:
        self.url = url
        self.session_id = ""
        self.auth = ""
        if username or password:
            token = base64.b64encode(f"{username}:{password}".encode()).decode()
            self.auth = f"Basic {token}"

    def request(self, method: str, arguments: dict[str, Any] | None = None) -> tuple[dict[str, Any], dict[str, float]]:
        payload = json.dumps({"method": method, "arguments": arguments or {}}).encode()
        headers = {"Content-Type": "application/json"}
        if self.session_id:
            headers["X-Transmission-Session-Id"] = self.session_id
        if self.auth:
            headers["Authorization"] = self.auth
        started = time.perf_counter()
        request = urllib.request.Request(self.url, data=payload, headers=headers, method="POST")
        try:
            response = urllib.request.urlopen(request, timeout=60)
        except urllib.error.HTTPError as error:
            if error.code != 409:
                raise
            self.session_id = error.headers.get("X-Transmission-Session-Id", "")
            if not self.session_id:
                raise RuntimeError("RPC session ID was not supplied by Transmission") from error
            return self.request(method, arguments)
        connected = time.perf_counter()
        with response:
            body = response.read()
        finished = time.perf_counter()
        return json.loads(body), {
            "connect_ms": (connected - started) * 1000,
            "ttfb_ms": (connected - started) * 1000,
            "total_ms": (finished - started) * 1000,
            "response_bytes": len(body),
        }


def summarize(name: str, samples: list[dict[str, Any]]) -> None:
    print(f"{name}: {len(samples)} samples")
    for metric in ("connect_ms", "ttfb_ms", "total_ms", "response_bytes", "torrent_count"):
        values = [float(sample[metric]) for sample in samples]
        print(
            f"  {metric}: min={min(values):.1f} median={statistics.median(values):.1f} "
            f"mean={statistics.mean(values):.1f} p95={percentile(values, 0.95):.1f} max={max(values):.1f}"
        )


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--samples", type=int, default=DEFAULT_SAMPLES)
    parser.add_argument("--json", type=Path, help="write raw samples as JSON")
    parser.add_argument("--csv", type=Path, help="write raw samples as CSV")
    args = parser.parse_args()
    if args.samples < 1:
        parser.error("--samples must be at least 1")

    root = Path(__file__).resolve().parents[1]
    load_env_file(root / ".env.local")
    load_env_file(Path(__file__).with_name(".env.local"))
    url = os.getenv("TRANSGUI_RPC_URL", DEFAULT_RPC_URL)
    username = os.getenv("TRANSGUI_RPC_USERNAME", DEFAULT_RPC_USERNAME)
    password = os.getenv("TRANSGUI_RPC_PASSWORD", DEFAULT_RPC_PASSWORD)
    if not url:
        parser.error("set TRANSGUI_RPC_URL in the environment or .env.local")

    rpc = TransmissionRpc(url, username, password)
    results: list[dict[str, Any]] = []
    for sample_number in range(1, args.samples + 1):
        rpc.request("session-stats")
        response, timings = rpc.request("torrent-get", {"fields": TORRENT_FIELDS})
        item = {
            "sample": sample_number,
            **timings,
            "torrent_count": len(response.get("arguments", {}).get("torrents", [])),
        }
        results.append(item)
        print(f"sample {sample_number}: {item['total_ms']:.1f} ms, {item['response_bytes']} bytes, {item['torrent_count']} torrents")
    summarize("torrent-get", results)
    if args.json:
        args.json.write_text(json.dumps(results, indent=2) + "\n", encoding="utf-8")
    if args.csv:
        with args.csv.open("w", newline="", encoding="utf-8") as output:
            writer = csv.DictWriter(output, fieldnames=results[0].keys())
            writer.writeheader()
            writer.writerows(results)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
