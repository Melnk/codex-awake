# Code review guidelines

This checklist adapts the supplied Kotlin review examples to Swift/macOS. It preserves the engineering intent instead of copying Kotlin syntax into Swift.

## Responsibilities and SOLID

- A type has one reason to change. UI state coordination, persistence, Desktop observation, chat lifecycle, privileged state storage, XPC transport, and `pmset` execution are separate responsibilities.
- High-level policy depends on small protocols (`PowerAssertionControlling`, `PowerProtectionControlling`, `CodexDesktopSessionScanning`, `AppPreferencesStoring`, `CodexChatClient`) rather than constructing implementation details inside business logic.
- Keep interfaces narrow. A chat component cannot manage power, and the root XPC service cannot execute arbitrary commands or accept paths/settings from a client.
- Put independently meaningful types in their own files. Tiny private SwiftUI views may stay together only when they form one cohesive visual component and have no independent behavior.
- Prefer composition and explicit dependency injection. Global singletons are allowed only at the composition boundary and must be wrapped before domain use.

## Validation and errors

- Validate input at the boundary or in a dedicated validator. The component that performs a side effect should receive an already valid request or enforce only its own domain invariant.
- Preserve the most useful typed error; do not replace it with a generic failure unless crossing a security boundary.
- Do not silently ignore an error that changes user-visible or system state. Cancellation and idempotent cleanup are the only normal `try?` cases, and should be evident from context.
- Bound all untrusted or external values: message sizes, identifiers, arrays, durations, error text, payloads, and retries.

## Privacy and security

- Prompts, responses, file contents, tool output, credentials, authorization headers, lease tokens, and raw protocol payloads never enter OSLog or diagnostics.
- Review configuration changes for their whole-system scope, not only the local call site.
- Root code exposes a narrow fixed API, validates the caller identity and input, uses fixed executable paths, has bounded leases, and restores previous state after release, crash, expiry, or uninstall.
- Tests must not weaken the production security boundary merely to make integration easier.

## Tests

- Use Arrange–Act–Assert. Separate setup, the single behavior under test, and assertions visually; add comments where the phases are not obvious.
- Test product behavior, not a framework or dependency implementation already covered upstream.
- Prefer injected in-memory fakes over a large integration stack when both prove the same application behavior.
- Every bug fix needs a focused regression test where the affected layer can be exercised deterministically.
- Keep timing, filesystem roots, preferences, process launchers, scanners, and power controllers injectable.

## Swift-specific quality

- UI mutations live on `@MainActor`; mutable concurrent state lives in actors or a private serial queue.
- Long-running tasks are owned, cancellable, and stopped during shutdown.
- Use value types for snapshots and protocol payloads; use reference types only for identity or shared lifecycle.
- Avoid force unwraps and `try!`. Use `guard`, typed errors, and idempotent cleanup.
- Prefer native Swift expression style when it improves clarity, but readability and explicit lifecycle handling are more important than terseness.

## Review completion

Before merge: run `./scripts/test.sh`, build the app bundle, run `./scripts/verify.sh`, inspect `git diff --check`, verify no secret-shaped/runtime files are present, and live-check the display assertion plus Closed-Lid helper status when those paths changed.
