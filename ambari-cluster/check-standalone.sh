#!/usr/bin/env bash
# =============================================================================
# check-standalone.sh — verify this spec package has no external dependency.
#
# Constitution P9: this package must be executable after being copied into a
# new, empty repository, with no other project present and no reference
# cluster running.
#
# Run it from the package root, and run it again after copying the package
# somewhere else:
#
#     ./check-standalone.sh
#     cp -r . /tmp/x && cd /tmp/x && ./check-standalone.sh
#
# Exit 0 = self-contained. Exit 1 = something reaches outside.
# =============================================================================
set -uo pipefail
cd "$(dirname "$0")"
ROOT=$(pwd -P)
fail=0
pass() { printf '  \033[32mPASS\033[0m  %s\n' "$1"; }
bad()  { printf '  \033[31mFAIL\033[0m  %s\n' "$1"; fail=1; }

echo "Checking package self-containment"
echo "Root: $ROOT"
echo

# --- 1. Relative links must resolve INSIDE the package -----------------------
# A path like ../../specs/... is fine from reference/predecessor/ — it stays
# in the tree. What matters is whether the RESOLVED path escapes the root,
# not how many ../ segments it has.
echo "1. Relative paths stay inside the package"
esc=0
while IFS=: read -r file _ link; do
  [ -z "${link:-}" ] && continue
  d=$(dirname "$file")
  resolved=$(cd "$d" 2>/dev/null && cd "$(dirname "$link")" 2>/dev/null && pwd -P) || continue
  case "$resolved" in
    "$ROOT"|"$ROOT"/*) ;;
    *) bad "escapes the package: $file -> $link"; esc=1 ;;
  esac
done < <(grep -rnoE '\.\./[A-Za-z0-9._/-]+' --include='*.md' --include='*.yaml' --include='*.sh' . \
         | sed 's/^\.\///' | awk -F: '{print $1":"$2":"$3}')
[ "$esc" -eq 0 ] && pass "no relative path resolves outside the root"

# --- 2. No executable reference to the predecessor tree ----------------------
echo "2. No executable file points at the predecessor repository"
# Excluded: reference/predecessor/ (verbatim archived copies, never executed)
# and this checker itself, whose own patterns would otherwise match.
hits=$(grep -rn "docker-hive/" \
         --include='*.py' --include='*.sh' --include='*.yaml' --include='*.yml' \
         --include='Makefile' --include='Dockerfile' . 2>/dev/null \
       | grep -v '^\./reference/predecessor/' \
       | grep -v '^\./check-standalone\.sh:')
if [ -n "$hits" ]; then
  echo "$hits"
  bad "executable reference to the predecessor tree"
else
  pass "none (prose and attribution comments are fine)"
fi

# --- 3. No task requires a live predecessor cluster --------------------------
# This is the dependency a path check cannot see: an instruction that only
# works if the old cluster happens to be running.
echo "3. No task requires a running predecessor cluster"
live=$(grep -rniE "on the predecessor cluster|from the running docker-hive|against the old cluster" \
         specs/ 2>/dev/null | grep -v 'no running\|not.*running\|none is assumed\|no predecessor cluster')
if [ -n "$live" ]; then
  echo "$live"
  bad "a task depends on a live reference deployment"
else
  pass "baselines are computed from committed inputs, not captured"
fi

# --- 4. Every referenced embedded input exists -------------------------------
echo "4. Every referenced reference/predecessor/ input is present"
missing=0
for p in $(grep -rhoE 'reference/predecessor/[A-Za-z0-9._-]+' . | sort -u); do
  [ -e "$p" ] || { bad "referenced but missing: $p"; missing=1; }
done
[ "$missing" -eq 0 ] && pass "all present"

# --- 5. Every internal spec cross-link resolves ------------------------------
echo "5. Internal cross-links resolve"
broken=0
while IFS= read -r line; do
  file=${line%%:*}; link=${line#*:}
  d=$(dirname "$file")
  [ -e "$d/$link" ] || { bad "broken link in $file -> $link"; broken=1; }
done < <(grep -rhoE '\]\([A-Za-z0-9._/-]+\.md\)' --include='*.md' . >/dev/null 2>&1; \
         grep -rnoE '\]\((\.\./|\./)?[A-Za-z0-9._/-]+\.md\)' --include='*.md' . \
         | sed 's/^\.\///' | sed 's/:[0-9]*:\](/:/' | sed 's/)$//')
[ "$broken" -eq 0 ] && pass "all internal .md links resolve"

echo
if [ "$fail" -eq 0 ]; then
  printf '\033[32mSELF-CONTAINED\033[0m — this package can be copied anywhere and remain executable.\n'
else
  printf '\033[31mNOT SELF-CONTAINED\033[0m — see failures above (constitution P9).\n'
fi
exit "$fail"
