# Responsiveness analysis

## Scope

This first pass adds measurement only. It does not change polling, JSON ownership,
or grid-update behaviour.

Build with `-dTRANSGUI_TIMING` (for example, add it temporarily to Lazarus custom
options) to emit timing output through Lazarus's debug logger. Normal builds do
not log timing data.

## Build and test context

- Project: `transgui.lpi`, entry point `transgui.lpr`.
- Main build: `lazbuild -B transgui.lpi --lazarusdir=<lazarus_dir>`; the tracked
  CI workflow builds with Lazarus on Debian Buster.
- The repository documentation states Free Pascal 2.6.2+ and Lazarus 1.6 as the
  historical minimum versions.
- No automated Pascal test suite exists yet.

## Current torrent refresh flow

```text
TRpcThread.Execute
  -> refresh interval elapsed / RefreshNow contains rtTorrents
  -> TRpcThread.GetTorrents
     -> TRpc.RequestInfo
        -> TRpc.SendRequest
           -> HttpLock.Enter
           -> HTTP POST / JSON parse
     -> ResultData := arguments.torrents
     -> Synchronize(DoFillTorrentsList) [worker waits]
        -> TMainForm.FillTorrentsList [GUI thread]
           -> update FTorrents
           -> rebuild visible gTorrents rows
           -> sort grid
           -> rebuild filters and groups
```

`ResultData` is a borrowed reference to `args.Arrays['torrents']`. `args` remains
alive until `Synchronize` returns, then is freed in `GetTorrents`; replacing the
synchronous call with `Queue` would therefore require explicit JSON ownership
transfer or cloning.

`RefreshNow` is a shared set updated by the worker and GUI code. `RequestFullInfo`
causes selected configured fields (notably `downloadDir`, and legacy `trackers`) to
be included in the next request. The worker resets `RequestFullInfo` after a valid
torrent response. The current interval timer is advanced at request start and then
again after `GetTorrents` completes.

## UI and direct-RPC observations

- `FillTorrentsList` currently rewrites all model and visible-grid cells, calls
  `gTorrents.Sort`, and recreates filter/group counts on every successful refresh.
- `TRpc.SendRequest` serializes all calls through a single `THTTPSend` protected by
  `HttpLock`; contention is now timed.
- `TAddTorrentForm.DiskSpaceTimerTimer` calls `RpcObj.SendRequest` synchronously
  for `free-space` on the GUI thread. This is timed but intentionally not changed
  in this pass.
- Further direct GUI-thread calls to `RpcObj.SendRequest` exist in `main.pas` and
  `daemonoptions.pas`; they require operation-by-operation classification before
  moving any of them to workers.
- The add-torrent workflow also synchronously issues `session-get` while opening
  the dialog. It is a likely contributor to delayed dialog presentation.

The add-torrent form invokes `DiskSpaceTimerTimer(nil)` from `FormShow`, then
enables the timer again when the destination changes. The timer disables itself
before issuing `free-space`, so each lookup blocks the form until the shared HTTP
transport becomes available and the daemon answers.

The direct `RpcObj.SendRequest` call sites found in application code are:

- `addtorrent.pas`: `free-space` from the destination-space timer.
- `daemonoptions.pas`: daemon-options update.
- `main.pas`: connection/session actions, torrent add/remove/start/stop/verify,
  tracker/label updates, rename, file-priority actions, and selected-torrent
  detail requests (22 call sites in this revision).

They remain unchanged for this measurement pass. Their individual operation and
UI-lifecycle classifications belong to the Phase 6 audit.

## Instrumentation added

With `TRANSGUI_TIMING` defined, the debug log records:

- every `HttpLock` acquisition wait;
- JSON parsing time;
- complete `torrent-get` time and returned torrent count;
- the worker's `Synchronize(DoFillTorrentsList)` wait;
- total `FillTorrentsList` time;
- grid sorting, grid update, grouping/filtering, and rows added/removed;
- add-dialog `free-space` request time.

The current implementation has no independent changed-cell representation, so it
does not claim a `Rows changed` value. That requires the snapshot-comparison work
reserved for Phase 3.

## Baseline measurement procedure

The standalone benchmark was run on 2026-07-11 against the configured endpoint.
It used the fixed `GetTorrents` fields, `session-stats` before each sample, and 10
samples. It does not include TransGUI's configured extra fields or any GUI work.

| Metric | Result |
| --- | ---: |
| Torrent count | 1,765 |
| Response size | 3,685,138–3,685,879 bytes |
| Connect/first-byte median | 138.2 ms |
| `torrent-get` total median | 272.7 ms |
| `torrent-get` total p95 | 792.9 ms |
| `torrent-get` total maximum | 985.5 ms |

The high tail latency and multi-megabyte response confirm that asynchronous RPC is
necessary but will not by itself solve GUI freezes: the current GUI also processes
and repaints every row after each response. The remaining baseline scenarios need
a diagnostics build with `TRANSGUI_TIMING` enabled: idle versus active download,
all versus active filter, static versus dynamic sort, and opening the add dialog
idle versus during refresh.

## Standalone RPC benchmark

`tools/rpc_benchmark.py` sends `session-stats` and the fixed fields from
`TRpcThread.GetTorrents`. It handles Transmission's 409 session-ID exchange and
reports connect/first-byte proxy, total time, response bytes, and torrent count
across configurable samples.

Create an ignored `.env.local` in the repository root:

```text
TRANSGUI_RPC_URL=http://server:9091/transmission/rpc
TRANSGUI_RPC_USERNAME=
TRANSGUI_RPC_PASSWORD=
```

Then run `python tools/rpc_benchmark.py --samples 10`. The script prints no
password and can write raw results using `--json results.json` or `--csv results.csv`.
