# Changelog

All notable changes to this project are documented here. The format is based on
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and this project adheres
to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [0.3.1]

### Fixed

- Per-task flags are no longer rejected when they lead the arguments. Commands
  like `mix xamal.app.logs -f` (and `-n`, `--since`, `--grep`) failed with
  `Unknown option`; the global option parser now forwards unrecognized flags to
  the task instead of raising.
- Remote commands keep their own flags. `mix xamal.server.exec df -h /` no
  longer has `-h /` consumed as the global `--hosts` option; option scanning
  stops at the first positional argument.
- `mix xamal.app.exec` no longer drops command flags other than `-i`.
- Interactive SSH sessions (`mix xamal.app.exec -i`, `mix xamal.iex`) resolve
  the real terminal device instead of assuming `/dev/tty` is openable, so they
  work when the BEAM runs without a controlling terminal.
- `mix xamal.rollback` no longer prints its "no previous version" error twice.

### Added

- `--skip-push` deploy option to distribute an already-built release instead of
  rebuilding.

### Removed

- `mix xamal.shell`. It mirrored Kamal's `shell` (a bash session inside the
  running container), but Xamal deploys native releases on the host, so it only
  duplicated `mix xamal.iex`. Use `mix xamal.iex` for a remote console or
  `mix xamal.server.exec` for host commands.

## [0.3.0]

See [UPGRADING.md](UPGRADING.md) for step-by-step migration instructions.

### Added

- New `mix xamal.prune` task to remove old releases beyond the retained count.
- New `mix xamal.shell` and `mix xamal.iex` tasks to open a remote shell or IEx
  session against the running release.
- New `mix xamal.migrate` task to run the release migrator (`<App>.Release.migrate`).
- New `mix xamal.server.logs` task to show Caddy/proxy logs from servers.
- New `mix xamal.app.start` task to start the service on its active port without a swap.
- New `mix xamal.app.version` task to show the deployed version per host.
- New `mix xamal.app.stale_releases` task to preview releases that pruning would remove.
- New `mix xamal.version` task to print the installed Xamal version.
- Hex packaging metadata, badges, and HexDocs configuration.

### Changed

- **Breaking:** Replaced the escript CLI with Mix tasks (`mix xamal.*`) as the
  public command surface. Invoke commands via `mix xamal.<task>` instead of the
  previous `xamal` escript binary, and install Xamal as a Mix dependency rather
  than a standalone binary.
- **Breaking:** Configuration is now Elixir config in `config/xamal.exs` instead
  of `config/deploy.yml`, with destination overrides in
  `config/xamal/<destination>.exs`. EEx templating is replaced by plain Elixir
  expressions (e.g. `System.get_env/1`).
- Mix tasks are grouped under a "Mix Tasks" section in the generated docs.

### Removed

- The `xamal` escript binary and the `install.sh` installer that downloaded it.

## [0.2.0]

### Changed

- Internal refactors toward the Mix-first architecture. No user-facing changes.

## [0.1.0]

### Added

- Initial release.

[0.3.1]: https://github.com/dmkenney/xamal/releases/tag/v0.3.1
[0.3.0]: https://github.com/dmkenney/xamal/releases/tag/v0.3.0
[0.2.0]: https://github.com/dmkenney/xamal/releases/tag/v0.2.0
[0.1.0]: https://github.com/dmkenney/xamal/releases/tag/v0.1.0
