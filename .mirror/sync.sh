#!/usr/bin/env bash
#
# Materialise an upstream release into this repository's working tree.
#
# This script is the single source of truth for "what the mirror should contain".
# The sync workflow runs it and commits the result; the verify workflow runs it
# and asserts that `git diff` is empty. One code path, no way for the two to
# disagree.
#
# Deliberate properties:
#   * Read-only, unauthenticated access to upstream (public repo, release tarball).
#   * Upstream's .github/ directory is deleted before anything is written, so no
#     upstream workflow, action, or CODEOWNERS file can ever land in this repo.
#   * Upstream code is never installed, imported, or executed.
#   * Only curl/tar/git/python3 are required.
#
# Usage: .mirror/sync.sh <upstream-tag>          e.g. .mirror/sync.sh v0.7.1

set -euo pipefail

UPSTREAM_REPO="${UPSTREAM_REPO:-Aleph-Alpha-Research/eval-framework}"
TAG="${1:?usage: .mirror/sync.sh <upstream-tag>}"

# Reject anything that isn't a plausible git tag before it reaches curl.
if ! printf '%s' "$TAG" | grep -Eq '^[A-Za-z0-9][A-Za-z0-9._/-]{0,99}$'; then
  echo "refusing implausible tag: $TAG" >&2
  exit 1
fi

REPO_ROOT="$(git rev-parse --show-toplevel)"
cd "$REPO_ROOT"

# Top-level paths owned by *this* repo. Never overwritten, never deleted by a
# sync. Everything else at top level is upstream's and is replaced wholesale.
# Keep this list dot-prefixed where possible so it cannot collide with upstream.
KEEP=(.git .github .mirror MIRROR.md)

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

echo "==> Fetching ${UPSTREAM_REPO}@${TAG}"
curl --fail --silent --show-error --location --retry 3 \
  --output "$TMP/upstream.tar.gz" \
  "https://codeload.github.com/${UPSTREAM_REPO}/tar.gz/refs/tags/${TAG}"

mkdir -p "$TMP/src"
tar -xzf "$TMP/upstream.tar.gz" -C "$TMP/src" --strip-components=1

# Upstream paths that are dropped rather than mirrored, because GitHub gives
# them special meaning in whatever repo they happen to live in:
#   .github/     -> workflows, composite actions, issue templates, dependabot
#   CODEOWNERS   -> honoured at repo root; upstream's references Aleph Alpha
#                   teams that do not exist in this org
STRIP=(.github CODEOWNERS .github/CODEOWNERS docs/CODEOWNERS)
for path in "${STRIP[@]}"; do
  rm -rf "$TMP/src/${path}"
done

echo "==> Replacing mirrored content"
while IFS= read -r -d '' entry; do
  name="${entry#./}"
  for keep in "${KEEP[@]}"; do
    if [ "$name" = "$keep" ]; then
      continue 2
    fi
  done
  rm -rf -- "$entry"
done < <(find . -mindepth 1 -maxdepth 1 -print0)

cp -a "$TMP/src/." .

echo "==> Recording state"
# Prefer the peeled commit when the tag is annotated; exact ref match only, so
# that v0.7.1 can never resolve against v0.7.10.
COMMIT="$(git ls-remote "https://github.com/${UPSTREAM_REPO}.git" \
    "refs/tags/${TAG}" "refs/tags/${TAG}^{}" \
  | awk -v t="refs/tags/${TAG}" '
      $2 == t "^{}" { peeled = $1 }
      $2 == t       { plain  = $1 }
      END           { print (peeled != "" ? peeled : plain) }')"
if [ -z "$COMMIT" ]; then
  echo "could not resolve ${TAG} to a commit" >&2
  exit 1
fi

UPSTREAM_REPO="$UPSTREAM_REPO" TAG="$TAG" COMMIT="$COMMIT" python3 - <<'PY'
import json, os
state = {
    "upstream_repo": os.environ["UPSTREAM_REPO"],
    "tag": os.environ["TAG"],
    "commit": os.environ["COMMIT"],
}
with open(".mirror/state.json", "w") as fh:
    json.dump(state, fh, indent=2, sort_keys=True)
    fh.write("\n")
PY

echo "==> Done: ${TAG} (${COMMIT})"
