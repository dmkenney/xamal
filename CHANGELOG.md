# Changelog

All notable changes to this project are documented here. The format is based on
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and this project adheres
to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Fixed

- `mix xamal.server.bootstrap` now writes the Caddyfile against the port that
  is actually serving, instead of always using `app_port`. Bootstrap is the
  only command that re-renders the systemd unit, so it gets run against live
  servers; on a server whose last blue-green deploy landed on `alt_port`, it
  previously repointed Caddy at the idle port and reloaded, causing an outage
  until the next deploy swapped back. The recorded port is used only when it
  is `app_port` or `alt_port`; otherwise it falls back to `app_port`.

## [0.4.1]

### Changed

- Interactive SSH sessions now use OTP 28's supported raw terminal mode
  (`:shell.start_interactive({:noshell, :raw})`) when available, instead of
  taking over fd 0 with a port. This removes the "stealing control of fd=0"
  path on newer OTP releases. OTP 26/27 keep the previous fd/stty approach as
  a fallback, which now also handles macOS/BSD `stty -f`.

## [0.4.0]

### Changed

- **Renamed the build tasks** away from the registry-derived `push`/`pull`
  verbs, which were misleading for a tarball-over-SSH workflow (nothing is
  pushed to a registry, and "pull" actually uploaded to the server):
  - `mix xamal.build.push` → `mix xamal.build` (build the tarball locally)
  - `mix xamal.build.pull` → `mix xamal.build.upload` (upload the tarball to servers)
  - `mix xamal.build.deliver` and `mix xamal.build.details` are unchanged.
  - The `--skip-push` deploy option is renamed to `--skip-build` (it skips the
    build and uploads an existing tarball). These are hard renames with no
    deprecation aliases.

### Added

- `CONTRIBUTING.md` documenting the development workflow, the `## [Unreleased]`
  changelog convention, and the maintainer release process.

## [0.3.2]

### Changed

- Release tarballs now upload via the system `scp` binary when an on-disk SSH
  key (`ssh.keys`) is configured, instead of Erlang's SFTP channel. SFTP's small
  window made large transfers slow (observed ~9 min for a ~120 MB tarball); scp
  runs at full link speed. Flows without an on-disk key (`key_data` from a
  secrets manager, or an SSH agent) continue to use the in-VM SFTP channel, as
  does the fallback when no `scp` binary is present.

### Fixed

- The release workflow no longer fails when a changelog entry contains
  backticks or `$()`. Release notes are now passed to `gh release create` via
  `--notes-file` instead of being interpolated into the command, so shell
  metacharacters in the notes are not executed.

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

[0.4.1]: https://github.com/dmkenney/xamal/releases/tag/v0.4.1
[0.4.0]: https://github.com/dmkenney/xamal/releases/tag/v0.4.0
[0.3.2]: https://github.com/dmkenney/xamal/releases/tag/v0.3.2
[0.3.1]: https://github.com/dmkenney/xamal/releases/tag/v0.3.1
[0.3.0]: https://github.com/dmkenney/xamal/releases/tag/v0.3.0
[0.2.0]: https://github.com/dmkenney/xamal/releases/tag/v0.2.0
[0.1.0]: https://github.com/dmkenney/xamal/releases/tag/v0.1.0
