#!/usr/bin/env bash
# Compose the `full` branch by performing real 3-way merges from
# origin/{master,db9,aitorgomez} into the existing `full` tip. No
# `-X ours` / `-X theirs`; conflicts that cannot be auto-resolved by
# rerere or the narrow whitelist abort the workflow so a human can
# resolve them in source. The resulting commit is what the build gate
# and `git push` consume.
#
# Requires PRE_SYNC env (set by the workflow) for diagnostics only.
# Requires .github/scripts/rerere-cache.sh to be sourced beforehand
# OR rerere to already be configured + .git/rr-cache hydrated.

set -euo pipefail

# Auto-resolver for the narrow set of paths that are housekeeping noise
# (release artifacts and CI scaffolding). Anything else aborts.
resolve_auto_conflicts() {
  local label="$1"
  local unmerged
  unmerged=$(git diff --name-only --diff-filter=U)
  [ -n "$unmerged" ] || return 0

  local non_auto
  non_auto=$(printf '%s\n' "$unmerged" | grep -vE '^(releases/|\.github/)' || true)
  if [ -n "$non_auto" ]; then
    echo "::error::${label}: unresolved source conflicts (rerere did not handle):"
    printf '%s\n' "$non_auto" | sed 's/^/  /'
    return 1
  fi

  local path
  while IFS= read -r path; do
    [ -n "$path" ] || continue
    case "$path" in
      releases/*)
        # Prefer the incoming side's release artifact; fall back to
        # delete if it was removed there. The post-merge "Restore own
        # files" step rewrites releases/ from PRE_SYNC anyway.
        if git checkout --theirs -- "$path" 2>/dev/null; then
          git add "$path"
        else
          git rm --ignore-unmatch -q -- "$path"
        fi
        ;;
      .github/*)
        # The merge=keep-ours driver should have prevented this; guard
        # anyway by keeping our side, falling back to delete.
        if git checkout --ours -- "$path" 2>/dev/null; then
          git add "$path"
        else
          git rm --ignore-unmatch -q -- "$path"
        fi
        ;;
    esac
  done <<<"$unmerged"
}

merge_branch() {
  local label="$1"
  local ref="$2"

  echo "::group::Merge ${label} (${ref})"

  if git merge --no-edit --no-ff "$ref"; then
    echo "::endgroup::"
    return 0
  fi

  # rerere may have auto-applied resolutions; if no conflicts remain,
  # commit and move on.
  if [ -z "$(git diff --name-only --diff-filter=U)" ]; then
    GIT_EDITOR=true git commit --no-edit
    echo "  (rerere auto-resolved all conflicts)"
    echo "::endgroup::"
    return 0
  fi

  if ! resolve_auto_conflicts "$label"; then
    git merge --abort
    echo "::endgroup::"
    return 1
  fi

  if [ -n "$(git diff --name-only --diff-filter=U)" ]; then
    echo "::error::${label}: still unmerged after auto-resolve"
    git merge --abort
    echo "::endgroup::"
    return 1
  fi

  GIT_EDITOR=true git commit --no-edit
  echo "::endgroup::"
}

PRE_SYNC="${PRE_SYNC:-$(git rev-parse HEAD)}"
echo "sync-full-merge: PRE_SYNC=${PRE_SYNC} ($(git log -1 --format='%h %s' "$PRE_SYNC"))"

# Order matters for rerere matching: same order each cycle keeps cached
# resolutions applicable. master is intentionally NOT merged here -
# upstream MiSTer-devel content arrives transitively via db9 and
# aitorgomez, both of which sync MiSTer-devel master into their own
# upstreams. Direct master->full merges produced recurring conflicts
# (cfg.h, cfg.cpp, menu.cpp, MiSTer.ini) whose shape shifted with
# every new master commit, defeating rerere.
merge_branch db9        origin/db9
merge_branch aitorgomez origin/aitorgomez

echo "sync-full-merge: composed full @ $(git rev-parse --short HEAD)"
