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

## ADR-006 — Do not hold the display awake

**Decision:** use `kIOPMAssertionTypePreventUserIdleSystemSleep`, not a display-sleep assertion. Codex work does not require the screen to remain lit.

## ADR-007 — No lid-close promise

**Decision:** document supported idle-sleep prevention only. Lid-close behavior is governed by macOS clamshell policy; hacks, fake input, global `pmset`, and kernel workarounds are excluded.

## ADR-008 — Version drift by capability probing

**Decision:** record the version for Diagnostics, probe current help for required transports/flags, decode only minimal fields, and fail visibly on incompatibility. Do not depend on a stale hard-coded full schema or opt into unrelated experimental APIs.

## ADR-009 — Separate desktop presence from managed task state

**Decision:** supervise and enumerate tasks only on the server CodexAwake owns. Detect the independent Codex Desktop process by its documented bundle identity as an ON/OFF keep-awake input, but never present that presence as a task or claim access to its private task contents/status. Independent cloud/plain CLI sessions retain separate lifecycle and security boundaries.

## ADR-010 — Bounded unknown-state grace

**Decision:** retain an already-needed managed-task assertion for at most 30 seconds while reconnecting. Reconciliation cancels the timer; confirmed server exit clears managed-task protection, while an independently enabled desktop-presence input may still keep the one shared assertion active. An unconfirmed managed state eventually releases to avoid an indefinite assertion.

## ADR-011 — Desktop runtime discovery

**Decision:** after a user-selected override, probe the compatible Codex executable bundled in ChatGPT/Codex Desktop before shell and standard CLI paths. Capability probing remains authoritative, so an installed app bundle is not accepted merely by name.
