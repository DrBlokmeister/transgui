# Development and release workflow

This workflow keeps stable releases dependable while allowing beta testers to
use new features early.

## Branches

Use three branch types:

| Branch | Purpose | Receives |
| --- | --- | --- |
| `master` | Stable, releasable code only. | Reviewed release pull requests from `develop`. |
| `develop` | Shared integration branch for the next beta. | Reviewed feature and fix pull requests. |
| `feature/<topic>` or `fix/<topic>` | Short-lived, focused work branch. | Commits for one feature or defect only. |

Create feature branches from `develop`, not from `master`. Keep each pull request
small and target `develop`. After the beta has been tested, open one release pull
request from `develop` to `master`.

The current `codex/responsive-rpc-refresh` branch is a feature branch. Its
changes should be reviewed and merged into `develop` before the first 5.19 beta.
The planned multi-select sidebar work should be developed separately, for example
on `feature/sidebar-multiselect`, then merged into `develop` only when its tests
and manual checks are ready.

## Version and tag policy

Use a single next-version line for each beta:

| Stage | Application and `VERSION.txt` | Git tag |
| --- | --- | --- |
| First 5.19 beta | `5.19.0b1` | `v5.19.0-beta.1` |
| Second 5.19 beta | `5.19.0b2` | `v5.19.0-beta.2` |
| Stable 5.19 release | `5.19.0` | `v5.19.0` |

For every version bump, update these together:

- `VERSION.txt`
- `main.pas` (`AppVersion`, which controls the title bar)
- `transgui.lpi` version metadata
- `history.txt` with concise user-visible release notes

Do not reuse or move a published tag. If a beta needs another fix, make the next
beta number and tag.

## Day-to-day feature work

1. Start from an up-to-date `develop` branch.
2. Create `feature/<topic>` or `fix/<topic>`.
3. Add focused commits with tests appropriate to the change.
4. Run the smallest relevant check locally. For responsiveness work this includes
   `scripts/run-unit-tests.ps1`; run the RPC benchmark when request fields or
   scheduling change.
5. Build the Lazarus project before requesting review.
6. Open a pull request into `develop`. Describe user impact, tests run, skipped
   checks, and any manual scenario that still needs validation.

Keep the sidebar multi-select work separate from the responsiveness changes. It
affects filtering and selection semantics, so it should have its own tests and
manual test checklist: repeated selection, Ctrl/Shift selection, clearing
selection, persistence across refreshes, and interaction with search and groups.

## Beta release checklist

Before publishing a beta:

1. Ensure `develop` is green and has the intended feature set.
2. Update the version files and add release notes to `history.txt`.
3. Build and manually test all changed workflows. For the current beta, test the
   large torrent list, add dialog, changing its destination, disconnected daemon,
   and application shutdown.
4. Merge `develop` to a temporary release branch only if a stabilization period
   is needed; otherwise tag the tested `develop` commit.
5. Create an annotated tag such as `v5.19.0-beta.1` and push it.
6. Publish a GitHub Release marked **pre-release**, with release notes, checksums,
   and the platform artifacts.

Only merge to `master` and create a non-pre-release GitHub Release after the beta
acceptance criteria are met.

## CI and package gaps to close

The existing workflow runs on pushes to `master` and tags, and publishes Linux
and macOS artifacts for every tag. Before using this process for betas, extend it
to:

- run validation on pull requests into `develop` as well as `master`;
- build and upload a Windows portable package;
- mark releases whose tag contains `-beta.` as GitHub pre-releases;
- include checksums for every artifact;
- publish Windows, Linux, and macOS assets only after their builds succeed.

Do not add the release automation until the branch policy is agreed, because it
changes how tags become public releases.

## Suggested first 5.19 beta scope

Include the responsiveness work already on `codex/responsive-rpc-refresh`:

- timing diagnostics and RPC benchmark;
- unchanged-refresh skipping;
- add-dialog periodic-refresh suspension;
- asynchronous free-space lookup;
- snapshot-comparison tests.

Keep the full incremental-grid rewrite and sidebar multi-select out of the first
beta unless they are complete and manually tested. A smaller beta is easier to
diagnose and safer for users with large torrent collections.
