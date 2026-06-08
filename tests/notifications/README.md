# Tests for hardening/notification-suite

Target branch: `hardening/notification-suite`
Commit under test: `28bbc5e2` — "hardening(notifications): per-screen popups, IPC, dynamic radius, DankBar guardrails"

These tests validate the **code structure** of the hardening patch against the
seven concerns it claims to address. They are intentionally **static** — they
parse the QML files, look for the new APIs and guardrails, and assert they
exist where the commit message says they do. No live `qs` process is required,
no display server, no daemon.

## Why static only

The hardening touches the Quickshell/QML runtime, which only fully resolves
inside a live compositor session. Running a real `quickshell` instance from CI
would be heavy, fragile, and out of scope for a pre-merge regression gate.
Static structure checks catch the failure modes that actually matter here:

* the new functions/properties were not accidentally removed by a rebase
* the IPC handler is wired to the documented target name
* the memory watchdog trim is bounded by the documented caps
* the safe-model null guard is in all three bar sections
* the dynamic radius branches handle connected-frame mode and the collapsed pill
* nothing introduced a parse-level syntax regression

## Files under test

| Concern                      | File                                                                      |
| ---------------------------- | ------------------------------------------------------------------------- |
| Per-screen popup suppression | `quickshell/Services/NotificationService.qml`                             |
| IPC handler `notifications`  | `quickshell/Services/NotificationService.qml`                             |
| Read state map + FIFO cap    | `quickshell/Services/NotificationService.qml`                             |
| Memory watchdog (30 s)       | `quickshell/Services/NotificationService.qml`                             |
| Dynamic card radius          | `quickshell/Modules/Notifications/Popup/NotificationPopup.qml`            |
| DankBar safe-model guard     | `quickshell/Modules/DankBar/{Left,Center,Right}Section.qml`               |
| DankBar WidgetHost guard     | `quickshell/Modules/DankBar/WidgetHost.qml`                               |
| DankBar debounce             | `quickshell/Modules/DankBar/DankBarContent.qml`                           |

## How to run

```sh
cd /path/to/DankMaterialShell-hardening-notification-suite
./tests/notifications/tests.sh
```

Or invoke any single test directly, e.g.:

```sh
./tests/notifications/test_read_state.sh
```

Each script exits `0` on PASS, non-zero on FAIL, and prints `PASS` or `FAIL`
on its own line as the last output. The aggregator `tests.sh` runs them all
and reports a summary at the end.

## Conventions

* `set -euo pipefail` everywhere
* `bash` only (no `sh` / `dash` / `zsh`-only features)
* Each test is one `*.sh` file in this directory, runnable on its own
* The aggregator does **not** `set -e` between children so one failure does
  not abort the rest; it tracks per-file status and exits non-zero if any
  child failed
* All output is plain text; no ANSI in PASS/FAIL lines so it greps cleanly

## Adding a new test

1. Create `test_<concern>.sh` next to this README.
2. Source nothing from the project — only the file paths under
   `quickshell/` are read with `awk` / `grep -E`.
3. Use the helpers `assert_file_contains` and `assert_file_contains_count`
   from `lib.sh` (sourced automatically when present, otherwise inline).
4. End with a single `echo PASS` on success or `echo FAIL: <msg>` and
   `exit 1` on failure.
5. Add the filename to the `tests` array in `tests.sh`.
