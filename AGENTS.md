# Agents

## Project

Xamal is an Elixir escript CLI that deploys Elixir releases to bare metal servers via SSH. Port of Kamal (Ruby/Docker) but using native releases + Caddy instead of Docker + kamal-proxy.

## Stack

- Elixir 1.15+, OTP 26+
- Escript binary (`mix escript.build` → `./xamal`)
- YAML config with EEx templating (`config/deploy.yml`)
- SSH via Erlang `:ssh` stdlib
- Tests: `mix test` (ExUnit)

## Architecture

- `lib/xamal/commands/` — Pure functions returning command lists (`["cmd", "arg1"]`), composed with `combine/pipe/chain`
- `lib/xamal/cli/` — CLI dispatch layer, imports `Xamal.CLI.Base` for shared helpers (`say`, `run_hook`, `with_lock`, etc.)
- `lib/xamal/configuration/` — Structs with `new/1` constructors parsing from maps
- `lib/xamal/commander.ex` — Agent-based runtime state (config, lock, host/role filtering)
- `test/xamal/cli_integration_test.exs` — E2E tests that invoke the compiled escript binary

## Important: Rebuild escript before testing

Integration tests run the installed escript binary, NOT the source code. After any code change, you MUST rebuild and reinstall before running tests:

```
mix escript.build && mix escript.install --force
```

Stale escript binaries cause tests to fail with confusing errors where the source looks correct but the runtime behavior is wrong.

## Conventions

- Commands modules return list-of-strings, never execute anything
- CLI modules handle execution, output, and orchestration
- Config structs are immutable; built once from YAML
- Hooks run locally, not on remote servers
- `mix test` must pass before committing

## Commit messages

- No AI attribution in commit messages — no "Co-Authored-By", no mentioning Claude, Copilot, ChatGPT, or any AI tool
- Keep messages short and descriptive
- Use imperative mood ("Add feature" not "Added feature")
