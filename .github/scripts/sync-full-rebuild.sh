#!/usr/bin/env bash
# `full` rebuild path. Resets to origin/db9 and merges aitorgomez with
# `-X ours`, then string-patches cfg.h, cfg.cpp, menu.cpp, user_io.cpp
# to re-inject aitorgomez declarations that `-X ours` silently dropped.
#
# Idempotent every cycle: same db9 + aitorgomez tips -> same full tip,
# regardless of prior full state. Workflow follows up by restoring own
# files (releases/, README.md) and .github/workflows/build-feature.yml
# from PRE_SYNC, then force-pushes.
#
# Replaces the previous merge-into-tip + rerere model, which was
# fragile: every db9/aitorgomez change to a non-whitelisted file
# required human intervention to seed a new rerere entry.

set -euo pipefail

resolve_auto_conflicts() {
  local label="$1"
  local prefer="$2"   # 'ours' or 'theirs' for modify/delete fallback
  local unmerged
  local non_auto
  local path

  unmerged=$(git diff --name-only --diff-filter=U)
  if [ -z "$unmerged" ]; then
    echo "::error::${label}: merge failed without conflicts to resolve"
    return 1
  fi

  non_auto=$(printf '%s\n' "$unmerged" | grep -vE '^(releases/|\.github/)' || true)
  if [ -n "$non_auto" ]; then
    echo "::error::${label}: unexpected conflict in source files:"
    printf '%s\n' "$non_auto"
    return 1
  fi

  while IFS= read -r path; do
    [ -n "$path" ] || continue
    case "$path" in
      releases/*)
        if git checkout "--$prefer" -- "$path" 2>/dev/null; then
          git add "$path"
        else
          git rm --ignore-unmatch -q -- "$path"
        fi
        ;;
      .github/*)
        git rm --ignore-unmatch -q -- "$path"
        ;;
    esac
  done <<<"$unmerged"
}

git reset --hard origin/db9

if ! git merge origin/aitorgomez --no-edit --allow-unrelated-histories -X ours; then
  resolve_auto_conflicts "Merge aitorgomez" ours || { git merge --abort; exit 1; }
  git commit --no-edit
fi

python3 - <<'PYEOF'
import os

required = ['cfg.h', 'cfg.cpp', 'menu.cpp', 'user_io.cpp']
missing = [p for p in required if not os.path.isfile(p)]
if missing:
    raise SystemExit(f'patch step: required files missing after merge: {missing}')

with open('cfg.h') as f:
    h = f.read()

if 'loading_txt_up' not in h:
    fields = (
        '\tchar loading_txt_up;\n'
        '\tchar waiting_txt_up;\n'
        '\tchar cfgcore_subfolder[32];\n'
        '\tchar cfgarcade_subfolder[32];\n'
    )
    h = h.replace('} cfg_t;', fields + '} cfg_t;')
    with open('cfg.h', 'w') as f:
        f.write(h)
    print('cfg.h: added aitorgomez fields')

with open('cfg.cpp') as f:
    c = f.read()

if 'LOADING_TXT_UP' not in c:
    entries = (
        '\t{ "LOADING_TXT_UP", (void *)(&(cfg.loading_txt_up)), UINT8, 0, 1 },\n'
        '\t{ "WAITING_TXT_UP", (void *)(&(cfg.waiting_txt_up)), UINT8, 0, 1 },\n'
        '\t{ "CFGCORE_SUBFOLDER", (void*)(&(cfg.cfgcore_subfolder)), STRING, 0, sizeof(cfg.cfgcore_subfolder) - 1 },\n'
        '\t{ "CFGARCADE_SUBFOLDER", (void *)(&(cfg.cfgarcade_subfolder)), STRING, 0, sizeof(cfg.cfgarcade_subfolder) - 1 },\n'
    )
    c = c.replace('\n};\n\nstatic const int nvars', '\n' + entries + '};\n\nstatic const int nvars', 1)
    with open('cfg.cpp', 'w') as f:
        f.write(c)
    print('cfg.cpp: added aitorgomez INI entries')

def ensure_include(filename, include, guard):
    with open(filename) as f:
        src = f.read()
    if guard in src and include not in src:
        last = max(src.rfind('\n#include '), src.rfind('\n#include\t'))
        end = src.index('\n', last + 1)
        src = src[:end] + '\n' + include + src[end:]
        with open(filename, 'w') as f:
            f.write(src)
        print(f'{filename}: added {include}')

ensure_include('menu.cpp',    '#include "loadscreen.h"', 'fade_in_screen')
ensure_include('menu.cpp',    '#include "zaparoo.h"',    'getZaparoo')
ensure_include('user_io.cpp', '#include "loadscreen.h"', 'load_screen_bg')

with open('menu.cpp') as f:
    src = f.read()
if 'init_loader_bg_early();' in src and 'void init_loader_bg_early()' not in src:
    body = (
        'static bool loader_bg_initialized = false;\n'
        '\n'
        'void init_loader_bg_early()\n'
        '{\n'
        '\tif (loader_bg_initialized) return;\n'
        '\n'
        '\tconst char* fname = "loader.png";\n'
        '\tif (!FileExists(fname))\n'
        '\t{\n'
        '\t\tfname = "loader.jpg";\n'
        '\t\tif (!FileExists(fname))\n'
        '\t\t{\n'
        '\t\t\tloader_bg = 1;\n'
        '\t\t\tloader_bg_initialized = true;\n'
        '\t\t\treturn;\n'
        '\t\t}\n'
        '\t}\n'
        '\n'
        '\tloader_bg = 0;\n'
        '\tloader_bg_initialized = true;\n'
        '\tprintf("loader_bg [EARLY INIT] -> %d\\n", loader_bg);\n'
        '}\n'
        '\n'
    )
    marker = '// [MiSTer-DB9-Pro END]\n'
    idx = src.find(marker)
    if idx == -1:
        raise SystemExit('menu.cpp: cannot find DB9-Pro END marker to insert init_loader_bg_early')
    insert_at = idx + len(marker) + 1
    src = src[:insert_at] + body + src[insert_at:]
    with open('menu.cpp', 'w') as f:
        f.write(src)
    print('menu.cpp: restored init_loader_bg_early() body')

with open('user_io.cpp') as f:
    src = f.read()
old_decl = 'static struct { const char *fmtstr; Imlib_Load_Error errno; } err_strings[] = {'
new_decl = 'static struct { const char *fmtstr; Imlib_Load_Error err;   } err_strings[] = {'
if old_decl in src:
    src = src.replace(old_decl, new_decl)
    src = src.replace('err_strings[i].errno', 'err_strings[i].err')
    with open('user_io.cpp', 'w') as f:
        f.write(src)
    print('user_io.cpp: renamed err_strings field errno -> err')
PYEOF

git add cfg.h cfg.cpp menu.cpp user_io.cpp
if ! git diff --cached --quiet; then
  git commit -m "Add aitorgomez declarations not auto-merged from db9 conflict"
fi
