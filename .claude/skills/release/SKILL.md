---
name: release
description: Cut a Xamal release end-to-end (maintainer-only). Does the version-bump prep, then commits, pushes master, tags vx.y.z (last), and watches the Release workflow publish to Hex and create the GitHub Release. Use when the user wants to "release x.y.z", "publish to Hex", "tag and ship", or "cut a release". Requires push rights; the tag push triggers CI which needs HEX_API_KEY. For local prep only (no push), use the version-bump skill.
metadata:
  version: 1.0.0
---

# Release

Cut a release of the Xamal Hex package. This is the **privileged** half — it
pushes to `master` and pushes a tag, which triggers the `Release` workflow
(`.github/workflows/release.yml`) to run `mix hex.publish` and create the GitHub
Release. Only run when the user has push rights and intends to ship publicly.

This skill is about releasing **the Xamal package to Hex** — it is *not* about
deploying an app with Xamal (`mix xamal.deploy`). Don't conflate them.

## The ordering invariant (why this skill exists)

`mix hex.publish` reads the version from `mix.exs`, **not** from the git tag. So
the tag must point at a commit where `mix.exs` already says the matching version,
and the `CHANGELOG.md` must already have a `## [x.y.z]` section (the workflow's
`awk` extractor pulls release notes from it). Get the order wrong and you publish
the wrong version or get a validation failure. **Always push the version-bump
commit first, then tag last.**

## Steps

1. **Prep.** Run the `version-bump` skill for the target version (clean/current
   check, bump `mix.exs`, roll the changelog, verify wiring, `mix ci`). Do not
   proceed unless `mix ci` passed.

2. **Confirm with the user** before any push: show the version delta, the two
   changed files, and the changelog section that becomes the release notes.

3. **Commit.** `git add mix.exs CHANGELOG.md` and commit with the message
   `Bump version to x.y.z` (imperative mood, no AI attribution — see AGENTS.md).

4. **Push `master`.** `git push origin master`. Note: `master` is branch-
   protected (normally requires a PR). The push may report a bypass — that's
   expected for a maintainer with admin. If it's *rejected* for being behind,
   stop, integrate, and re-run from prep.

5. **Tag last, then push the tag.**
   `git tag vx.y.z <bump-commit>` then `git push origin vx.y.z`.
   If a stale `vx.y.z` tag already exists (e.g. a failed earlier attempt),
   delete it first locally and on the remote:
   `git tag -d vx.y.z && git push origin :refs/tags/vx.y.z`, then re-create it
   at the bump commit.

6. **Watch the workflow.** Find the run
   (`gh run list --workflow=Release --limit 3`) and watch it
   (`gh run watch <id> --exit-status`). Expect every step green:
   Verify build → Publish package → Extract changelog section →
   Create GitHub Release.

7. **Verify the outputs** and report:
   - GitHub Release: `gh release view vx.y.z` — confirm the notes match the
     changelog section.
   - Hex publish succeeded (the "Publish package" step is green).

## If the workflow fails

- **"Building xamal a.b.c" shows the wrong version / "Validation error(s)"** →
  the tag points at a commit whose `mix.exs` is stale. The version bump didn't
  land before the tag. Fix `mix.exs`, push, delete + re-create the tag at the
  correct commit.
- **Empty / fallback release notes** → no `## [x.y.z]` section in
  `CHANGELOG.md`. Add it, then re-tag.
- Always read the failing step's log: `gh run view <id> --log-failed`.
