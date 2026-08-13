# Architecture

## Runtime data flow

`AppModel` is the main-actor composition and UI boundary. It coordinates feature components but no longer owns their internal state machines. `CodexChatSession` owns conversation/approval state, `CodexDesktopMonitor` owns `NSWorkspace` observation and rollout polling, and `UserDefaultsAppPreferences` owns typed preference persistence. The model locates the Codex binary, asks `AppServerSupervisor` to launch one owned child, and runs an observer connection through `AppServerClient`.

`UnixWebSocketTransport` implements RFC 6455 client framing and the HTTP Upgrade handshake directly over `AF_UNIX`. It validates `Sec-WebSocket-Accept`, masks client frames, handles ping/pong/close, limits payloads to 16 MiB, and exposes no TCP listener.

`AppServerClient` performs `initialize` then `initialized`, allocates monotonically increasing request IDs, matches responses to continuations, times out pending calls, converts relevant notifications into typed events, routes command/file/permission approval requests to the cockpit, rejects server requests it cannot serve, and survives malformed JSON. Chat configuration is discovered with `model/list`; new and stored conversations use `thread/start` and `thread/resume` respectively.

`CodexChatSession` is the main-actor chat state machine. It gives every user message a delivery state (`queued`, `sending`, `sent`, or `failed`), serializes queued turns, preserves the client message UUID across retries, resumes its own saved thread after reconnect or restart, and consumes streamed agent/item events. A failed message stays visible with a plain-language reason and retry action. Enter submits or queues, Shift-Enter inserts a newline, and `turn/interrupt` stops the active turn.

`FileCodexChatRepository` is the only chat persistence component. It stores at most 30 cockpit-created conversations under Application Support, limits each conversation to 500 messages and 200 tool records, writes the directory/file with modes `0700`/`0600`, and converts an interrupted `sending` message back to `queued` during restore. It never imports global Codex history. The selected project, model, reasoning effort, permission mode, own thread ID, messages, changed-file paths, and generic tool lifecycle are persisted; approval continuations and tool output are not.

The cockpit requests `on-request` approval and lets the user select read-only, project-write, or explicitly confirmed full-access sandboxing. Project-write supplies only the selected folder as an explicit writable root. Model and reasoning values come from `model/list`, avoiding hard-coded catalog assumptions. Command, file-change, and permission requests block on an in-app approval card. Permission responses grant only the subset requested by App Server.

`ThreadActivityTracker` is an actor and owns:

- `activeThreadIds: Set<String>`;
- `activeTurnKeys: Set<TurnKey>`;
- runtime statuses and loaded IDs;
- known versus unknown/reconnecting certainty.

Lifecycle events provide low latency. Chat-only item events do not mutate activity certainty or sleep state. Connection/reconnection/startup and a 10-second timer call `thread/loaded/list`, then `thread/read` for each loaded ID. Reconciliation replaces the active set from runtime `thread.status`; turn contents are never requested by the sleep tracker.

`CodexTaskRegistry` is a separate actor for the user-facing 1.7 task center. It combines managed App Server metadata with Desktop rollout metadata, normalizes lifecycle events into waiting/thinking/tool/approval/completed/error, keeps a bounded 20-item recent history, and supplies the Dock/menu counters. Managed reconciliation requests `thread/read(includeTurns: false)` only for IDs returned by this server's `thread/loaded/list`; it does not query the global Codex history. The decoder retains only ID, cwd, timestamps, and runtime status. The server's `name`, `preview`, and thread turns are intentionally ignored; project names are derived locally from cwd. Desktop records contain only root session ID, cwd, timestamp, modification time, and the final lifecycle marker. Transition notifications are produced outside the registry so the state machine remains independent from AppKit and UserNotifications.

Selecting a task in the activity center opens the installed Codex/ChatGPT app with its registered local `codex://threads/<id>` deep link. This remains separate from the cockpit history: CodexAwake resumes only thread IDs created and saved by its own chat. The cockpit uses native `HSplitView` and `VSplitView`, so the control column, conversation, and tool activity can be resized without custom pointer handling.

`CodexDesktopRolloutScanner` enumerates local JSONL rollouts, decodes only the first `session_meta` record, accepts only root records with `source = vscode` and `originator = Codex Desktop`, and searches backwards in bounded chunks for the latest exact `task_started` or `task_complete` marker. It does not parse message contents. Markers older than the current Desktop app launch are ignored so a crash cannot create permanent false activity.

`AwakeCoordinator` combines three inputs: exact managed-task activity from `ThreadActivityTracker`, detected active Codex Desktop sessions, and optional full-time Codex Desktop process presence. `PowerProtectionManager` routes that single aggregate decision to the unprivileged `PowerAssertionManager` and, when explicitly enabled, `ClosedLidLeaseManager`. The former independently owns zero or one `PreventUserIdleSystemSleep` assertion and zero or one `PreventUserIdleDisplaySleep` assertion according to saved user policy; the latter owns zero or one renewable helper lease. Configuration changes reconcile live assertions transactionally. A one-second idle debounce avoids churn. Unknown managed connection state uses a 30-second grace limit. Confirmed server termination clears the managed input but retains protection when Desktop task activity or enabled presence still requires it; application termination releases every assertion and lease.

## Privileged Closed-Lid boundary

The main app never executes `pmset` and never runs as root. `CodexAwakeClosedLidHelper` is a small launch daemon installed into `/Library/PrivilegedHelperTools` with a matching `/Library/LaunchDaemons` plist after an explicit administrator prompt. Its bootstrap, XPC adapter, lease store, validator, and fixed `pmset` adapter are separate components. The Mach service uses a four-method XPC interface: status, acquire, renew, and release. At install time the daemon's listener requirement is pinned to the signed app identifier plus Apple Team ID, or to the exact CDHash when a local ad-hoc build has no Team ID; there is no arbitrary command, file, shell, or path parameter.

The client lease lasts at most 120 seconds and renews every 30 seconds only while the aggregate power protection is held. Failed XPC operations are retried with capped exponential backoff. On the first lease, the daemon snapshots the prior `disablesleep` setting, persists the restoration data plus expiry timestamps in a root-only file, and invokes the fixed `/usr/bin/pmset -a disablesleep 1` command. Final release, graceful daemon termination, uninstall, or expiry restores the captured setting. Persisted expiries allow a relaunched daemon to recover after a crash without creating an indefinite system policy change. Developer ID builds authorize a stable Apple Team ID plus the fixed app identifier; unsigned local development falls back to an exact CDHash requirement.

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

The activity path extracts method, request ID, thread ID, turn ID, item ID/type, status type, active flags, working folder, and timestamps. The `thread.name` and `thread.preview` fields are not decoded. The cockpit separately renders and locally persists user text and streamed agent messages only for conversations created in that cockpit. These contents are not forwarded to Diagnostics or OSLog. Diffs, tool output, terminal output, command text, and file contents are not retained or logged; the activity pane retains only tool names and changed-file paths. An active approval card can show the bounded command or reason that App Server explicitly asks the user to review. Diagnostics abbreviate identifiers and sanitize errors to one line/300 characters.

CodexAwake has no telemetry and creates no external network session. The supervised Codex process retains its ordinary responsibility for authenticated upstream Codex communication.

## Application packaging

SwiftPM builds the main executable, helper executable, and tests. `scripts/build_app.sh` assembles a standard foreground app bundle with `Info.plist`, `LSUIElement=false`, semantic/build versions, the `com.melnikoleg.CodexAwake` identifier, installer resources, a separately signed helper, and final ad-hoc app signing. `Package.swift` opens directly in Xcode; no project generator is required.

## Failure behavior

- Missing Codex: menu and Diagnostics show a recoverable error; binary selection remains available.
- Unsupported help surface: start is rejected before launch.
- Malformed JSON: logged as a content-free error; reconciliation is requested.
- Connection loss with prior activity: state becomes unknown, assertion is bounded by 30 seconds.
- Confirmed child exit: managed-task state is cleared; the assertion is released unless enabled Codex Desktop presence still requires it; restart uses backoff.
- Repeated/out-of-order events: set semantics and reconciliation converge without extra assertions.
- Application quit: termination is delayed until client, child, socket, and assertion shutdown complete.
- Missing/rejected Closed-Lid helper: the ordinary idle assertion remains held; the UI reports a helper-required/update state.
- Chat request rejected: the user message remains visible as failed with a localized reason and Retry action.
- Disconnect during a turn: that message becomes failed, later queued messages remain recoverable, and the saved thread is resumed after reconnect.
- Restart during queued delivery: a persisted `sending` state is restored as `queued`; no draft silently disappears.
- Main-app crash: the root lease expires in at most 120 seconds and restores the saved power policy.
- Helper crash/restart: persisted lease expiries are reloaded; expired state is restored before new work is accepted.
