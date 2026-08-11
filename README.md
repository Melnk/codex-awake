# CodexAwake

CodexAwake is a native macOS menu bar utility and Codex cockpit. It launches its own local Codex App Server, provides a streamed chat UI for Codex, and prevents **idle system sleep** while that server reports active Codex work or while the Codex desktop app is running.

It uses the official App Server protocol for managed-task state and the desktop app's bundle identifier only for a separate ON/OFF presence signal. It does not infer individual desktop-task state from CPU usage, windows, or file timestamps. CodexAwake owns at most one `PreventUserIdleSystemSleep` assertion. The display may still turn off.

> [!IMPORTANT]
> CodexAwake tracks its own cockpit tasks and Codex CLI/TUI sessions connected with `--remote` to the App Server launched by CodexAwake. It also detects whether ChatGPT/Codex Desktop is running and can keep the Mac awake for that entire time. The desktop app does not publish an API that lets another local app enumerate its independent open chats or active turns, so those details are not shown as managed tasks. Ordinary CLI sessions, Codex Cloud, another user's processes, and remote hosts remain out of scope unless they connect to the managed server.

## Cockpit

Open **Open Cockpit…** from the menu bar. The dark graphite and silver native SwiftUI interface includes:

- a large illuminated **ON/OFF** control for automatic sleep protection;
- Codex Desktop presence, assertion, and active managed-task instruments;
- the IDs of all active tasks connected to the managed server;
- a project picker and streamed Codex conversation;
- **New task**, **Stop**, Enter-to-send, Shift-Enter newline, and arrow-button controls;
- approval cards for shell commands, network access, and file changes.

The cockpit uses the authenticated [Codex App Server](https://learn.chatgpt.com/docs/app-server), not a separately stored API key. Select a project folder before starting a task. Codex is given workspace-write access to that folder and uses the `unlessTrusted` approval policy; approval prompts remain visible while the task is active.

## How it works

```text
Cockpit / connected CLI ─→ managed App Server ─→ active-task state ─┐
                                                                   ├─→ ONE idle-sleep assertion
Codex Desktop bundle ID ───────────────────────→ ON/OFF presence ───┘
```

The runtime status returned by `thread/read` is the source of truth. Notifications (`turn/started`, `turn/completed`, `thread/status/changed`, and `thread/closed`) reduce latency; `thread/loaded/list` plus `thread/read` reconcile state at connection, reconnection, and every 10 seconds.

## Tracked and untracked activity

Tracked:

- tasks started in the CodexAwake cockpit;
- Codex CLI/TUI clients launched with the menu's **Open Codex** action;
- clients started manually with the command from **Copy Codex command**;
- multiple clients connected to the same CodexAwake-managed endpoint;
- active statuses including `waitingOnApproval`;
- whether ChatGPT/Codex Desktop is currently running.

Not tracked:

- `codex` started without `--remote`;
- individual conversations, prompts, and active-turn state inside the independent Codex Desktop app;
- Codex Cloud jobs;
- other users' processes;
- unrelated App Server processes;
- remote machines not using the displayed endpoint.

The first-run menu, cockpit, and Diagnostics window repeat this boundary. Desktop presence is shown as `CODEX APP ON/OFF`, never added to the managed-task count. With both power controls enabled, presence is intentionally sufficient to keep the Mac awake even though it is not presented as proof of an active turn.

## Requirements

- macOS 14 or later;
- Apple silicon or Intel Mac;
- full Xcode for source builds (tested with Xcode 26.6 / Swift 6.3.3);
- ChatGPT/Codex Desktop with a compatible bundled runtime, or a standalone Codex CLI whose help advertises both `codex --remote` and `codex app-server --listen unix://`.

No third-party packages are used. The application uses SwiftUI, Foundation, Swift Concurrency, OSLog, ServiceManagement, AppKit, CryptoKit, Darwin Unix sockets, and IOKit.

## Build and install

```bash
git clone <private-repository-url>
cd codex-awake
scripts/test.sh
scripts/build_app.sh
open dist/CodexAwake.app
```

The release build is assembled as `dist/CodexAwake.app` and ad-hoc signed for local development. Copy it to `/Applications` if desired. A paid Apple Developer account is not required for local use.

To build a debug bundle:

```bash
CONFIGURATION=debug scripts/build_app.sh
```

`Package.swift` can be opened directly in Xcode. The scripts redirect Swift/Clang caches to ignored `.build/` paths and use `--disable-sandbox` because some managed development environments prohibit SwiftPM's nested `sandbox-exec`.

## First launch

CodexAwake has no Dock icon (`LSUIElement=true`). The cockpit opens automatically at launch; after closing it, reopen it from the bolt menu with **Open Cockpit…** or launch the `.app` again. On first launch the menu shows these facts:

1. cockpit tasks and sessions connected to its managed `--remote` endpoint are tracked individually;
2. Codex Desktop process presence is detected, but its independent chats remain private;
3. the application prevents idle sleep and does not bypass lid-close sleep policy.

CodexAwake first tries the runtime bundled inside an installed ChatGPT/Codex app. If no compatible runtime can be found, the menu shows `Codex: Not found` and App Server state `Failed`; open **Diagnostics… → Choose Codex Binary…** to select an executable.

## Codex binary discovery

The locator checks, in order:

1. a user-selected path saved in `UserDefaults`;
2. the runtime bundled in `/Applications/ChatGPT.app` or `/Applications/Codex.app`, including per-user Applications equivalents;
3. `command -v codex` in a login zsh;
4. `/opt/homebrew/bin/codex`;
5. `/usr/local/bin/codex`;
6. `~/.local/bin/codex` and `~/.codex/bin/codex`.

It runs read-only `--version` and help probes. It does not modify shell startup files or global Codex configuration.

## Managed App Server and transport

CodexAwake launches exactly one owned child process with the current equivalent of:

```bash
codex app-server --listen unix:///private/runtime/path/app-server.sock
```

The endpoint is a WebSocket HTTP Upgrade over a Unix domain socket, as specified by the [official Codex App Server documentation](https://learn.chatgpt.com/docs/app-server). The runtime directory is short, per-user, mode `0700`, and outside the repository. CodexAwake removes a stale socket only when it is an owned Unix socket that does not accept connections. It refuses active, foreign-owned, or non-socket paths.

No TCP port is opened. The CodexAwake process makes no external network connection; it communicates locally with the Codex child. The Codex App Server itself performs the normal Codex service communication needed by connected CLI sessions.

## Launch Codex through CodexAwake

Use either menu command:

- **Open Codex** writes a credential-free `.command` helper in the user's Application Support directory with mode `0700`, then opens it in Terminal;
- **Copy Codex command** copies the exact local command, conceptually:

  ```bash
  codex --remote unix:///private/runtime/path/app-server.sock
  ```

The command contains no capability token or credential. The endpoint changes only if the runtime path changes. Do not launch plain `codex` if you expect CodexAwake to track that session.

## Auto Keep Awake

**Auto Keep Awake** defaults to on. With it enabled:

- if **Keep awake while Codex App is running** is enabled, Codex Desktop presence acquires the assertion even when no managed task is visible;
- `0 → 1+` active managed threads acquires one assertion;
- additional active threads reuse that assertion;
- desktop exit or `1+ → 0` managed threads releases after a one-second debounce when no other source still requires protection;
- `waitingOnApproval` remains active;
- `idle`, `notLoaded`, and `systemError` are inactive.

The large main power control overrides both sources and releases immediately when switched off. The separate desktop-presence toggle leaves precise managed-task protection enabled. CodexAwake does not expose a default-on manual or indefinite force-awake mode.

## Reconnect and fail-safe policy

If the observer connection drops while managed work may be active, state becomes **Activity unknown / reconnecting**. The assertion is retained for at most 30 seconds while the client reconnects and reconciles. A confirmed App Server exit clears managed-task protection; desktop-presence protection remains if enabled and Codex Desktop is still running. If neither source can be confirmed, CodexAwake releases rather than keeping the Mac awake forever.

The supervisor distinguishes requested stop from crash, drains child stdout/stderr without logging their contents, reaps the child, and restarts unexpected exits with capped exponential backoff. It never searches for or kills unrelated Codex processes.

## Launch at Login

The menu's **Launch at Login** toggle uses `SMAppService.mainApp`. CodexAwake does not create a manual LaunchAgent and does not edit `.zshrc`, `.bashrc`, or other shell files.

## Diagnostics

**Diagnostics…** shows and copies:

- app, macOS, architecture, Codex path/version;
- transport and local endpoint;
- App Server state, owned PID, and start time;
- loaded/active counts and abbreviated thread/turn IDs;
- assertion state, last event/reconciliation, reconnect count;
- the latest sanitized operational error.

It excludes prompts, model responses, diffs, tool output, terminal output, file contents, tokens, credentials, cookies, auth files, and complete environment variables. Cockpit messages are held in the current UI session and sent to the managed Codex server, but are never copied into Diagnostics or OSLog. Codex persists normal conversation history according to its own configuration. There is no CodexAwake telemetry.

## Verify the assertion

1. Launch CodexAwake and confirm `App Server: Running` and the expected `Codex Desktop` presence state.
2. Use **Copy Codex command** and run it in a terminal.
3. Start a safe test turn (this is the only step that can consume model quota).
4. Confirm the menu shows an active thread and `Keep Awake: ON`.
5. Inspect system assertions without changing settings:

   ```bash
   pmset -g assertions
   ```

6. Wait for the final turn to complete and the one-second debounce. Confirm `Keep Awake: OFF`.
7. Repeat with multiple TUI clients; CodexAwake should still own only one assertion.

Do not use `pmset` to change power settings for CodexAwake.

## Closed-lid limitation

CodexAwake prevents **idle system sleep** during active managed turns. It does not promise to cancel forced sleep when a MacBook lid is physically closed. Closed-lid behavior depends on Apple's supported clamshell mode, power, external displays, and system configuration. There are no kernel hacks, fake input events, `sudo pmset` changes, or lid-policy bypasses.

## Built-in Codex prevent-idle feature

Some Codex versions may expose their own experimental prevent-idle-sleep feature. CodexAwake never edits `~/.codex/config.toml` or toggles Codex feature flags. If the user enables both mechanisms, Codex may own another assertion. The guarantee here is that **CodexAwake owns at most one of its own assertions**, not that only one assertion exists system-wide.

## Privacy and security

- Unix socket runtime directory: `0700`;
- no listening TCP interface;
- no credentials in arguments, clipboard, logs, or helper script;
- no prompt, response, diff, tool, terminal, or file-content logging (cockpit text exists only in UI memory and normal Codex conversation storage);
- no telemetry or CodexAwake outbound network client;
- only the exact child process started by CodexAwake is terminated;
- OSLog contains lifecycle/state/counts and sanitized errors only.

## App Server compatibility

App Server is an evolving protocol. CodexAwake performs runtime capability checks instead of accepting a version number alone. The implementation uses stable non-experimental methods in the current official schema: `initialize`, `initialized`, `thread/loaded/list`, `thread/read`, and status/turn/thread notifications. It does not request `capabilities.experimentalApi`.

The ChatGPT-bundled Codex runtime `0.147.0-alpha.6.5` was discovered and used to validate a real local App Server launch and `initialize`/`initialized` handshake on 2026-08-11. No model prompt was sent during that check. Real multi-client notification fan-out still requires an explicit quota-consuming manual turn and is not claimed as verified. The fake-server suite validates the remaining wire/state logic. Run the read-only handshake after updating Codex:

```bash
scripts/real_app_server_test.sh
```

That script starts a temporary local server, performs `initialize`/`initialized` and read-only reconciliation, sends no model prompt, and consumes no model quota. See [app-server-compatibility.md](docs/app-server-compatibility.md).

## Development and tests

```bash
scripts/test.sh                 # unit + fake App Server integration suite
scripts/build_app.sh            # release .app + ad-hoc signing
scripts/verify.sh               # metadata, LSUIElement, signature, diff, secret-shaped files
scripts/real_app_server_test.sh # explicit, read-only real CLI handshake
```

The test suite wraps power management behind `PowerAssertionControlling`; tests never create a real sleep assertion. It includes mocked power, process, client, timer/clock behavior, a scripted transport, malformed payloads, disconnect/reconnect, request matching, stale socket policy, and 10+ concurrent thread scenarios.

## Troubleshooting

**Codex not found**

- Confirm ChatGPT/Codex is installed in `/Applications`, or:
- Run `command -v codex` and `codex --version` in a login shell.
- Choose the executable in Diagnostics.
- Confirm `codex --help` includes `--remote` and `codex app-server --help` includes Unix `--listen` syntax.

**App Server failed**

- Open Diagnostics and copy the sanitized error.
- Ensure no other process owns the displayed socket.
- Use **Restart App Server**. CodexAwake will not delete an active or foreign socket.

**Active turn is not detected**

- Confirm the TUI was started with the exact copied `--remote` command.
- Wait up to the 10-second reconciliation interval.
- A task from the independent Codex Desktop app is represented only by `CODEX APP ON`; its individual turn is not included in `ACTIVE TASKS`.
- Independent cloud and plain CLI activity is intentionally out of scope.

**Chat send fails**

- Confirm the header says `READY` and a project is selected.
- Enter sends, Shift-Enter inserts a newline, and the arrow button uses the same action.
- If the server is not ready, the composer preserves the draft and shows the exact readiness reason instead of silently doing nothing.

**Assertion seems duplicated**

- `pmset -g assertions` can show assertions from Codex itself and other apps.
- Disable any separately enabled experimental Codex prevent-idle feature if you want only CodexAwake's assertion.

## Architecture and release workflow

See [architecture.md](docs/architecture.md) and [architecture decisions](docs/decisions/README.md). For future Developer ID signing, hardened runtime, notarization, and releases, see [release.md](docs/release.md).

Recommended GitHub workflow:

1. create a `codex/<topic>` branch;
2. implement and run `scripts/test.sh`;
3. run `scripts/build_app.sh` and `scripts/verify.sh`;
4. review `git diff`, staged changes, and secret-shaped files;
5. push and open a private pull request;
6. add Developer ID signing/notarization only in a credential-protected release workflow.
