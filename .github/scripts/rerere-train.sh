#!/usr/bin/env bash
# Walk merge commits in <rev-range> (default: full), replay each merge from
# its first parent against the other parent(s) WITHOUT any -X strategy, and
# record the committed resolution into .git/rr-cache via `git rerere`.
#
# Run this once locally to seed the rerere database from history before
# enabling the new sync-full workflow. Push the resulting cache to the
# `merge-resolutions` orphan branch with rerere-cache.sh's rerere_save.
#
# Usage:
#   .github/scripts/rerere-train.sh [rev-range]
#
# Examples:
#   .github/scripts/rerere-train.sh                # default: full
#   .github/scripts/rerere-train.sh full ^master   # only full's merges since master

set -euo pipefail

RANGE=("${@:-full}")

if ! git diff --quiet || ! git diff --cached --quiet; then
  echo "rerere-train: working tree dirty; commit or stash first" >&2
  exit 1
fi

orig_head="$(git rev-parse --abbrev-ref HEAD)"
if [ "$orig_head" = "HEAD" ]; then
  orig_head="$(git rev-parse HEAD)"
fi

cleanup() {
  git merge --abort 2>/dev/null || true
  git reset -q --hard
  git checkout -q "$orig_head"
}
trap cleanup EXIT

git config rerere.enabled true
git config rerere.autoupdate true

trained=0
seen=0

while read -r commit parent1 rest; do
  [ -n "${rest:-}" ] || continue
  seen=$((seen + 1))

  echo "==> $commit (parent1=$parent1, others=$rest)"
  git checkout -q "$parent1^0"

  if git merge --no-edit --no-gpg-sign --no-ff $rest >/dev/null 2>&1; then
    git reset -q --hard "$parent1"
    continue
  fi

  # Capture preimage
  git rerere

  # Apply the actual recorded resolution from the historical merge commit
  git checkout "$commit" -- .

  # Record postimage
  git rerere

  git reset -q --hard "$parent1"
  trained=$((trained + 1))
done < <(git rev-list --parents --merges "${RANGE[@]}")

echo
echo "rerere-train: scanned $seen merges, trained $trained conflict resolutions"
echo "rr-cache entries: $(find .git/rr-cache -mindepth 1 -maxdepth 1 -type d 2>/dev/null | wc -l)"
