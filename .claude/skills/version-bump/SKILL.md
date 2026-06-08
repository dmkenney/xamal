---
name: version-bump
description: Prepare a new Xamal version locally — bump @version in mix.exs, roll the CHANGELOG.md ## [Unreleased] section into a numbered release section, run mix ci, and verify the README/docs/package wiring is still correct. Use when the user wants to "bump the version", "prep a release", "cut x.y.z", or before tagging/publishing. Stops before any commit, tag, or push — that privileged step belongs to the release skill. Safe for any contributor to run in a branch.
metadata:
  version: 1.0.0
---

# Version bump

Prepare the repository for a new release **locally**. This skill never commits,
tags, pushes, or publishes — it only edits files and verifies them. Use the
`release` skill for the privileged steps (those need push rights / `HEX_API_KEY`).

## Inputs

- The target version (e.g. `0.3.3`). If the user didn't give one, infer from the
  unreleased changes and SemVer, then confirm:
  - Bug fixes only → patch (`0.3.2` → `0.3.3`)
  - New backwards-compatible features → minor (`0.3.2` → `0.4.0`)
  - Breaking changes → major (`0.3.2` → `1.0.0`), or minor while `0.x`
- Read the current version from `mix.exs` (`@version "..."`).

## Steps

1. **Confirm the repo is clean and current.** Run `git fetch` and check the
   working tree is clean and the local branch is not behind its remote. If the
   remote has moved, stop and tell the user to integrate first — tagging a stale
   commit is the failure mode this skill exists to prevent.

2. **Bump `@version` in `mix.exs`.** Change only the `@version "..."` attribute
   (line ~4). Everything else (`package()`, `docs()`, `source_ref`) is derived
   from it — do not touch those.

3. **Roll the changelog.** In `CHANGELOG.md`:
   - Rename the `## [Unreleased]` heading to `## [x.y.z]`.
   - Add a fresh empty `## [Unreleased]` section above it (so contributors always
     have a target for the next cycle).
   - Add a tag-link line at the bottom in the existing style:
     `[x.y.z]: https://github.com/dmkenney/xamal/releases/tag/vx.y.z`
   - Keep the existing Keep-a-Changelog format (`### Added/Changed/Fixed/Removed`,
     no dates). Do **not** switch formats.
   - If `## [Unreleased]` is empty, draft entries from
     `git log <prev-tag>..HEAD --oneline` and the PR titles, then ask the user to
     review them. Never invent user-facing notes for internal/CI-only commits
     without flagging them.

4. **Verify the wiring is still correct** (these are derived, not edited — confirm
   they didn't drift):
   - `README.md` install snippet uses a `~>` constraint
     (e.g. `{:xamal, "~> 0.3", ...}`). It should **only** change on a major/minor
     boundary that moves the constraint, never on a patch. Leave it alone unless
     the new version crosses that boundary.
   - `mix.exs` `docs()` `source_ref: "v#{@version}"` and `package()` links still
     point at the right places (they're derived — just sanity-check).

5. **Run `mix ci`.** It must pass clean (credo, architecture policy, dialyzer 0
   errors, all tests). If it fails, stop and report — do not proceed.

6. **Report** the two files changed (`mix.exs`, `CHANGELOG.md`), the version
   delta, and the changelog section that will become the release notes. Then hand
   off: tell the user the prep is done and the `release` skill (or a maintainer)
   handles commit → push → tag → publish.

## Do not

- Do not `git commit`, `git tag`, `git push`, or `mix hex.publish`.
- Do not edit `package()`/`docs()` directly or add a `maintainers:` field
  (Hex uses package owners via `mix hex.owner`, not the deprecated field).
- Do not bump the README `~>` constraint on a patch release.
