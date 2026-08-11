# Architecture

## Runtime data flow

`AppModel` is the main-actor UI boundary. It locates the Codex binary, asks `AppServerSupervisor` to launch one owned child, and runs an observer connection through `AppServerClient`. It observes `NSWorkspace` launch/termination notifications for Codex Desktop presence and polls `CodexDesktopRolloutScanner` once per second for active top-level Desktop task lifecycles.

`UnixWebSocketTransport` implements RFC 6455 client framing and the HTTP Upgrade handshake directly over `AF_UNIX`. It validates `Sec-WebSocket-Accept`, masks client frames, handles ping/pong/close, limits payloads to 16 MiB, and exposes no TCP listener.

`AppServerClient` performs `initialize` then `initialized`, allocates monotonically increasing request IDs, matches responses to continuations, times out pending calls, converts relevant notifications into typed events, routes command/file approval requests to the cockpit, rejects server requests it cannot serve, and survives malformed JSON.

The cockpit starts a conversation with `thread/start` using the installed runtime's protocol values `workspace-write` and `on-request`, sends user input with `turn/start`, renders `item/agentMessage/delta`, treats the final `item/completed` agent message as authoritative, interrupts with `turn/interrupt`, and answers command/file approval requests. Each turn uses the selected folder as its only explicit writable root. Enter submits, Shift-Enter inserts a newline, and rejected preconditions leave the draft intact while adding a visible system explanation.

`ThreadActivityTracker` is an actor and owns:

- `activeThreadIds: Set<String>`;
- `activeTurnKeys: Set<TurnKey>`;
- runtime statuses and loaded IDs;
- known versus unknown/reconnecting certainty.

Lifecycle events provide low latency. Chat-only item events do not mutate activity certainty or sleep state. Connection/reconnection/startup and a 10-second timer call `thread/loaded/list`, then `thread/read` for each loaded ID. Reconciliation replaces the active set from runtime `thread.status`; turn contents are never requested by the sleep tracker.

`CodexDesktopRolloutScanner` enumerates local JSONL rollouts, decodes only the first `session_meta` record, accepts only root records with `source = vscode` and `originator = Codex Desktop`, and searches backwards in bounded chunks for the latest exact `task_started` or `task_complete` marker. It does not parse message contents. Markers older than the current Desktop app launch are ignored so a crash cannot create permanent false activity.

`AwakeCoordinator` combines three inputs: exact managed-task activity from `ThreadActivityTracker`, detected active Codex Desktop sessions, and optional full-time Codex Desktop process presence. `PowerProtectionManager` routes that single aggregate decision to the unprivileged `PowerAssertionManager` and, when explicitly enabled, `ClosedLidLeaseManager`. The former owns zero or one `IOPMAssertionID` of type `PreventUserIdleSystemSleep`; the latter owns zero or one renewable helper lease. A one-second idle debounce avoids churn. Unknown managed connection state uses a 30-second grace limit. Confirmed server termination clears the managed input but retains protection when Desktop task activity or enabled presence still requires it; application termination releases both paths.

## Privileged Closed-Lid boundary

The main app never executes `pmset` and never runs as root. `CodexAwakeClosedLidHelper` is a small launch daemon installed into `/Library/PrivilegedHelperTools` with a matching `/Library/LaunchDaemons` plist after an explicit administrator prompt. Its Mach service uses a four-method XPC interface: status, acquire, renew, and release. The daemon's listener requirement is pinned at install time to the main app's exact CDHash; there is no arbitrary command, file, shell, or path parameter.

The client lease lasts at most 120 seconds and renews every 30 seconds only while the aggregate power protection is held. On the first lease, the daemon snapshots the prior `disablesleep` setting, persists the restoration data plus expiry timestamps in a root-only file, and invokes the fixed `/usr/bin/pmset -a disablesleep 1` command. Final release, graceful daemon termination, uninstall, or expiry restores the captured setting. Persisted expiries allow a relaunched daemon to recover after a crash without creating an indefinite system policy change.

## Supervisor state machine

```text
stopped → starting → running
   ↑          ↘       ↓ unexpected exit
   └ stopping ←   reconnecting → starting
                       ↓ repeated failure
                     failed
```

The supervisor stores the exact `Process` instance it launched. It drains both pipes, uses a termination handler, reaps requested exits, and restarts unexpected exits with capped exponential backoff. It never finds or signals another Codex process.

## Socket lifecycle

The socket lives in a short per-user temporary directory, usually under the system-provided temporary directory, with a short `/tmp/caw-<uid>` fallback if the Unix path would be too long. Directory mode is forced to `0700` and validated with `lstat`.

An existing path is removed only if all are true:

1. it is a Unix socket;
2. it is owned by the current uid;
3. a connection probe fails.

An accepting socket, foreign owner, directory, symlink target mismatch, or regular file causes a safe refusal. Normal stop removes only an owned socket.

## Privacy boundary

The activity path extracts method, request ID, thread ID, turn ID, status type, and active flags. The cockpit separately renders user text and streamed agent messages for its current conversation. These contents are not forwarded to Diagnostics or OSLog. Diffs, tool output, terminal output, and file contents are not rendered or logged. Diagnostics abbreviate identifiers and sanitize errors to one line/300 characters.

CodexAwake has no telemetry and creates no external network session. The supervised Codex process retains its ordinary responsibility for authenticated upstream Codex communication.

## Application packaging

SwiftPM builds the main executable, helper executable, and tests. `scripts/build_app.sh` assembles a standard bundle with `Info.plist`, `LSUIElement=true`, semantic/build versions, the `com.melnikoleg.CodexAwake` identifier, installer resources, a separately signed helper, and final ad-hoc app signing. `Package.swift` opens directly in Xcode; no project generator is required.

## Failure behavior

- Missing Codex: menu and Diagnostics show a recoverable error; binary selection remains available.
- Unsupported help surface: start is rejected before launch.
- Malformed JSON: logged as a content-free error; reconciliation is requested.
- Connection loss with prior activity: state becomes unknown, assertion is bounded by 30 seconds.
- Confirmed child exit: managed-task state is cleared; the assertion is released unless enabled Codex Desktop presence still requires it; restart uses backoff.
- Repeated/out-of-order events: set semantics and reconciliation converge without extra assertions.
- Application quit: termination is delayed until client, child, socket, and assertion shutdown complete.
- Missing/rejected Closed-Lid helper: the ordinary idle assertion remains held; the UI reports a helper-required/update state.
- Main-app crash: the root lease expires in at most 120 seconds and restores the saved power policy.
- Helper crash/restart: persisted lease expiries are reloaded; expired state is restored before new work is accepted.
