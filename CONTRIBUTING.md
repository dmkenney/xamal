# Contributing to Xamal

Thanks for your interest in improving Xamal. This guide covers the development
workflow and the conventions the project follows.

## Development setup

```sh
git clone https://github.com/dmkenney/xamal
cd xamal
mix deps.get
```

Xamal targets Elixir 1.15+ and OTP 26+.

## Before you open a PR

- **Run `mix ci`.** It runs the full quality suite — Credo, the architecture
  policy, Dialyzer, and the test suite (`mix test`). CI runs the same checks, so
  a green `mix ci` locally means your PR should pass.
- **Add a changelog entry.** Put a short, user-facing note under the
  `## [Unreleased]` section at the top of [`CHANGELOG.md`](CHANGELOG.md), using
  the existing `### Added` / `### Changed` / `### Fixed` / `### Removed`
  headings. Do **not** add a version number or edit `mix.exs` — versioning is a
  maintainer step done at release time (see below). Targeting `## [Unreleased]`
  keeps parallel PRs conflict-free.
- **Keep commits in imperative mood** ("Add feature", not "Added feature") and
  **without AI attribution** — no `Co-Authored-By` lines, no mentions of AI
  tools. See [AGENTS.md](AGENTS.md) for the full conventions.

## Conventions

The architectural conventions live in [AGENTS.md](AGENTS.md) (symlinked as
`CLAUDE.md`). In short:

- Public command surface is Mix tasks (`mix xamal.*`); no escript, no
  `Xamal.CLI.*` modules.
- Command builder modules under `lib/xamal/commands/` return lists of strings
  and never execute anything.
- Config structs are immutable and built from Elixir config.

## Releases (maintainers)

Releases are cut by maintainers, not in contributor PRs. The flow is:

1. Roll the `## [Unreleased]` changelog section into a numbered `## [x.y.z]`
   section and bump `@version` in `mix.exs`.
2. Commit, push `master`, and push a `vx.y.z` tag.
3. The [`Release` workflow](.github/workflows/release.yml) runs on the tag:
   `mix ci`, `mix hex.publish`, and a GitHub Release built from the changelog
   section.

Contributors only add notes under `## [Unreleased]` — the version number and the
publish are decided at release time. (Maintainers: the `version-bump` and
`release` skills in `.claude/skills/` automate this.)

## Questions

Open an issue or a discussion on [GitHub](https://github.com/dmkenney/xamal).
