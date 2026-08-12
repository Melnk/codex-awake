# Architecture decisions

## ADR-001 — App Server protocol, not heuristics

**Decision:** observe the official Codex App Server protocol. Process/CPU/window/file polling cannot distinguish an active turn from an idle client and would create false assertions.

## ADR-002 — Unix-domain WebSocket transport

**Decision:** use WebSocket HTTP Upgrade over a per-user Unix socket. It is supported by current official docs, exposes no TCP port, relies on `0700` filesystem isolation, and needs no bearer token in local arguments. A small native RFC 6455 transport avoids a third-party dependency.

## ADR-003 — Runtime thread status is authoritative

**Decision:** `thread.status.type == active` is the assertion source of truth. `activeFlags`, including `waitingOnApproval`, remain active. `idle`, `notLoaded`, and `systemError` are inactive.

## ADR-004 — Events plus reconciliation

**Decision:** consume events for latency but reconcile at startup, connect, reconnect, suspicious input, and every 10 seconds. Multi-client notification fan-out may change; polling runtime status repairs missed/out-of-order events.

## ADR-005 — One assertion per application

**Decision:** aggregate all active IDs through one coordinator. Acquire only on zero-to-nonzero and release only after nonzero-to-zero plus debounce. Ten threads do not create ten assertions.

## ADR-006 — Hold the display awake during protected work

**Decision:** use one `kIOPMAssertPreventUserIdleDisplaySleep` assertion while aggregate Codex protection is active. The macOS SDK specifies that this prevents automatic display dim/off and also prevents idle system sleep. Release it through the existing debounce as soon as no protected Codex work or enabled Desktop-presence source remains. This supersedes the original system-only assertion after live use showed that a dark display was unexpected and disruptive.

## ADR-007 — Opt-in privileged Closed-Lid lease

**Decision:** the ordinary app continues to use the documented idle-sleep assertion. After explicit user authorization, an isolated root daemon may temporarily set `pmset disablesleep` only while a bounded 120-second lease exists. It snapshots and restores the prior value, persists expiry for crash recovery, accepts no arbitrary command, and defaults off. This supersedes the original no-lid-bypass scope after the owner explicitly requested root-helper support.

## ADR-008 — Version drift by capability probing

**Decision:** record the version for Diagnostics, probe current help for required transports/flags, decode only minimal fields, and fail visibly on incompatibility. Do not depend on a stale hard-coded full schema or opt into unrelated experimental APIs.

## ADR-009 — Combine managed events with privacy-safe Desktop lifecycle markers

**Decision:** use App Server status/events for the server CodexAwake owns. For independent Codex Desktop roots, read only rollout `session_meta` identity and the latest exact `task_started` / `task_complete` marker. Never parse or expose prompts, responses, reasoning, tool output, or titles. Keep bundle presence as a separate optional full-time wake input. Independent cloud/plain CLI sessions retain separate lifecycle and security boundaries.

## ADR-010 — Bounded unknown-state grace

**Decision:** retain an already-needed managed-task assertion for at most 30 seconds while reconnecting. Reconciliation cancels the timer; confirmed server exit clears managed-task protection, while an independently enabled desktop-presence input may still keep the one shared assertion active. An unconfirmed managed state eventually releases to avoid an indefinite assertion.

## ADR-011 — Desktop runtime discovery

**Decision:** after a user-selected override, probe the compatible Codex executable bundled in ChatGPT/Codex Desktop before shell and standard CLI paths. Capability probing remains authoritative, so an installed app bundle is not accepted merely by name.

## ADR-012 — Installed schema is the compatibility authority

**Decision:** generate and inspect the schema from the selected runtime when official examples and live validation disagree. For the tested bundled alpha runtime, `thread/start` uses `sandbox = workspace-write` and `approvalPolicy = on-request`; turn-level `sandboxPolicy.type = workspaceWrite` remains camel-case.

## ADR-013 — Exact client identity for the root helper

**Decision:** the install script writes either the installing app's Apple Team ID or, when no trustworthy Team ID exists, its exact CDHash into the launch daemon arguments. The daemon converts only those validated identity forms into a fixed XPC signing requirement before accepting clients. Signed updates from the same team reuse the helper; ad-hoc rebuilds require helper reinstallation. The privileged API remains limited to status/acquire/renew/release and never accepts executable paths, shell text, settings names, or values.

## ADR-014 — Feature boundaries and injected persistence

**Decision:** keep `AppModel` as the main-actor composition boundary while moving chat/approval lifecycle, Codex Desktop observation, and typed preference storage into focused components. Domain-facing behavior is exposed through narrow protocols, and tests receive isolated stores/fakes. The root helper likewise separates bootstrap, XPC, validation, lease persistence, and fixed `pmset` execution. This applies the supplied Kotlin review principles as Swift SOLID boundaries without importing framework-specific style rules.
