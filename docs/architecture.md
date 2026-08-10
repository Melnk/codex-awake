# Architecture

## Runtime data flow

`AppModel` is the main-actor UI boundary. It locates the Codex binary, asks `AppServerSupervisor` to launch one owned child, and runs an observer connection through `AppServerClient`.

`UnixWebSocketTransport` implements RFC 6455 client framing and the HTTP Upgrade handshake directly over `AF_UNIX`. It validates `Sec-WebSocket-Accept`, masks client frames, handles ping/pong/close, limits payloads to 16 MiB, and exposes no TCP listener.

`AppServerClient` performs `initialize` then `initialized`, allocates monotonically increasing request IDs, matches responses to continuations, times out pending calls, converts relevant notifications into privacy-safe typed events, rejects unsolicited server requests it cannot serve, and survives malformed JSON.

`ThreadActivityTracker` is an actor and owns:

- `activeThreadIds: Set<String>`;
- `activeTurnKeys: Set<TurnKey>`;
- runtime statuses and loaded IDs;
- known versus unknown/reconnecting certainty.

Events provide low latency. Connection/reconnection/startup and a 10-second timer call `thread/loaded/list`, then `thread/read` for each loaded ID. Reconciliation replaces the active set from runtime `thread.status`; prompt/turn contents are never requested.

`AwakeCoordinator` maps activity to the `PowerAssertionControlling` protocol. The production `PowerAssertionManager` owns zero or one `IOPMAssertionID` of type `PreventUserIdleSystemSleep`. A one-second idle debounce avoids churn. Unknown connection state uses a 30-second grace limit. Confirmed server termination and application termination release immediately.

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

The protocol decoder extracts method, request ID, thread ID, turn ID, status type, and active flags. UI and logs never consume prompt previews, turn item content, responses, diffs, tool output, or terminal output. Diagnostics abbreviate identifiers and sanitize errors to one line/300 characters.

CodexAwake has no telemetry and creates no external network session. The supervised Codex process retains its ordinary responsibility for authenticated upstream Codex communication.

## Application packaging

SwiftPM builds the executable and tests. `scripts/build_app.sh` assembles a standard bundle with `Info.plist`, `LSUIElement=true`, semantic/build versions, the `com.melnikoleg.CodexAwake` identifier, and ad-hoc signing. `Package.swift` opens directly in Xcode; no project generator is required.

## Failure behavior

- Missing Codex: menu and Diagnostics show a recoverable error; binary selection remains available.
- Unsupported help surface: start is rejected before launch.
- Malformed JSON: logged as a content-free error; reconciliation is requested.
- Connection loss with prior activity: state becomes unknown, assertion is bounded by 30 seconds.
- Confirmed child exit: assertion is released immediately; restart uses backoff.
- Repeated/out-of-order events: set semantics and reconciliation converge without extra assertions.
- Application quit: termination is delayed until client, child, socket, and assertion shutdown complete.
