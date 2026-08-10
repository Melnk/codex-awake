# Codex App Server compatibility

App Server and its WebSocket transport are evolving. This project treats the CLI installed on the user's machine as the runtime authority and the official OpenAI documentation as design guidance.

## Sources and investigation commands

The intended inspection commands are:

```bash
codex --version
codex --help
codex app-server --help
codex app-server generate-json-schema --out .build/codex-schema/json
codex app-server generate-ts --out .build/codex-schema/typescript
```

On the development machine used for this checkout on 2026-08-10, all three `codex` preflight commands returned `command not found`, including login-shell and fixed-path checks. Schema generation and a real server launch were therefore not performed. No minimum real Codex version is claimed as tested. `.build/codex-schema/` is ignored and generated dumps must not be committed unless a small compile-time model is deliberately selected.

The implementation was compared with the current [official Codex App Server documentation](https://developers.openai.com/codex/app-server), which documents:

- `codex app-server --listen unix://PATH`;
- `codex --remote unix://PATH`;
- WebSocket HTTP Upgrade over Unix sockets;
- JSON-RPC-style messages without the `jsonrpc` header;
- `initialize` followed by `initialized`;
- `thread/list`, `thread/read`, `thread/loaded/list`;
- `thread/status/changed`, `turn/started`, `turn/completed`, `thread/closed`;
- runtime statuses `notLoaded`, `idle`, `systemError`, and `active` with `activeFlags`.

## Runtime compatibility gate

CodexAwake accepts a binary only when:

1. it is executable;
2. `--version` succeeds;
3. top-level help includes `--remote`;
4. App Server help includes `--listen` and `unix://`.

The exact version string is displayed but is not used as a substitute for capabilities. Incompatible versions produce a user-visible safe error and no server is launched.

## Experimental surface

The App Server command and transport are described by OpenAI as experimental. CodexAwake does not set `capabilities.experimentalApi`. Its observation path uses methods currently available without that flag. The optional `thread/turns/list`, `thread/items/list`, process APIs, and experimental filters are not used.

When protocol drift causes decoding or a method error, CodexAwake keeps prompts private, marks activity unknown, attempts reconnect/reconciliation, and releases after the bounded grace period rather than holding an assertion indefinitely.

## Multi-client semantics

Automated tests simulate multiple clients and notification/reconciliation behavior. A real installed Codex CLI was unavailable, so notification fan-out between an observer client and turns started by another TUI is not claimed as experimentally verified in this checkout. Correctness does not depend on notification broadcast: periodic `thread/loaded/list` + `thread/read` reconciliation remains the source of truth.

Run the read-only real check after installing/updating Codex:

```bash
scripts/real_app_server_test.sh
```

Then manually connect two or more TUI clients and follow the assertion procedure in the README. A model turn must be initiated only with the user's consent because it can consume quota.
