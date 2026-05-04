#!/usr/bin/env bash
# Persist .git/rr-cache to/from an orphan branch so conflict resolutions
# survive across CI runs.
#
# Source this file then call:
#   rerere_load [remote]    # hydrate .git/rr-cache from <remote>/<RERERE_BRANCH>
#   rerere_save [remote]    # snapshot .git/rr-cache to <remote>/<RERERE_BRANCH>
#
# Defaults: remote=origin, RERERE_BRANCH=merge-resolutions

set -u

: "${RERERE_BRANCH:=merge-resolutions}"

rerere_load() {
  local remote="${1:-origin}"
  local cache=".git/rr-cache"

  mkdir -p "$cache"

  if ! git fetch --no-tags --depth=1 "$remote" "$RERERE_BRANCH" 2>/dev/null; then
    echo "rerere_load: $remote/$RERERE_BRANCH absent (first run); skipping"
    return 0
  fi

  rm -rf "$cache"
  mkdir -p "$cache"
  git archive FETCH_HEAD | tar -x -C "$cache"
  echo "rerere_load: hydrated $cache from $remote/$RERERE_BRANCH ($(git rev-parse --short FETCH_HEAD))"
}

rerere_save() {
  local remote="${1:-origin}"
  local cache=".git/rr-cache"

  if [ ! -d "$cache" ] || [ -z "$(ls -A "$cache" 2>/dev/null)" ]; then
    echo "rerere_save: $cache empty; nothing to push"
    return 0
  fi

  local tmpidx
  tmpidx="$(mktemp)"
  # shellcheck disable=SC2064
  trap "rm -f '$tmpidx'" RETURN

  local f rel sha
  while IFS= read -r -d '' f; do
    rel="${f#"$cache"/}"
    sha="$(git hash-object -w "$f")"
    GIT_INDEX_FILE="$tmpidx" git update-index --add --cacheinfo "100644,$sha,$rel"
  done < <(find "$cache" -type f -print0)

  local tree
  tree="$(GIT_INDEX_FILE="$tmpidx" git write-tree)"

  local parent_args=()
  if git fetch --no-tags --depth=1 "$remote" "$RERERE_BRANCH" 2>/dev/null; then
    local existing_tree
    existing_tree="$(git rev-parse FETCH_HEAD^{tree})"
    if [ "$tree" = "$existing_tree" ]; then
      echo "rerere_save: tree unchanged; skipping push"
      return 0
    fi
    parent_args=(-p FETCH_HEAD)
  fi

  local head_short
  head_short="$(git rev-parse --short HEAD 2>/dev/null || echo unknown)"
  local commit
  commit="$(git commit-tree "$tree" "${parent_args[@]}" -m "rerere snapshot from sync-full @ ${head_short}")"

  git push "$remote" "${commit}:refs/heads/${RERERE_BRANCH}"
  echo "rerere_save: pushed $(git rev-parse --short "$commit") to $remote/$RERERE_BRANCH"
}
