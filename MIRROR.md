# Read-only mirror

This repository is an **automated, read-only mirror** of
[`Aleph-Alpha-Research/eval-framework`](https://github.com/Aleph-Alpha-Research/eval-framework),
maintained for the OpenEuroLLM consortium. The upstream project is developed by
Aleph Alpha Research and licensed under Apache-2.0; see `LICENSE`.

The version currently mirrored here is recorded in
[`.mirror/state.json`](.mirror/state.json).

## Do not open pull requests here

Changes made in this repository will be **silently overwritten** by the next sync
and will make CI fail in the meantime. Please file issues and pull requests
upstream: <https://github.com/Aleph-Alpha-Research/eval-framework>.

## How the mirror works

Two workflows, no secrets, no credentials shared with upstream:

| Workflow | Trigger | What it does |
| --- | --- | --- |
| `.github/workflows/sync-upstream.yml` | nightly + manual | Checks for a new upstream **release**. If there is one, replaces the mirrored tree with that release's contents and tags it `upstream-<version>`. A no-op between releases. |
| `.github/workflows/verify-mirror.yml` | nightly, push, PR | Re-downloads the recorded release and asserts this repository is byte-identical to it. |

Both call `.mirror/sync.sh`, so the check and the sync can never disagree about
what "in sync" means.

## Intentional deviations from upstream

Everything upstream ships is mirrored, except two paths that GitHub treats as
active configuration in whichever repository they live in:

- `.github/` — upstream's workflows, composite actions and templates. Dropping
  this directory is what guarantees **none of upstream's CI ever runs here**.
- `CODEOWNERS` — refers to Aleph Alpha teams that do not exist in this
  organisation.

Files this repository owns and the sync never touches: `.github/`, `.mirror/`,
`MIRROR.md`.

## Security properties

- No repository, organisation or environment secrets are used or required.
- Upstream is read anonymously over HTTPS; no token is ever presented to it.
- Writes use the automatic `GITHUB_TOKEN`, scoped to this repository, granted
  `contents: write` in one job and nothing anywhere else.
- Mirrored code is never installed, imported, built or executed by CI here.
