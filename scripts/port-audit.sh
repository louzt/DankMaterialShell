#!/usr/bin/env bash
# Report master commits missing from a release branch.
#
# Usage: port-audit.sh [<target-branch>] [--issue]
#
# Target defaults to the newest origin/release/* branch. --issue writes the
# report to the "Port status: <target>" tracking issue body (needs gh auth).
set -euo pipefail

TARGET=""
UPDATE_ISSUE=0
for arg in "$@"; do
  case "$arg" in
    --issue) UPDATE_ISSUE=1 ;;
    *) TARGET="$arg" ;;
  esac
done

git fetch origin --quiet 2>/dev/null || true

if [ -z "$TARGET" ]; then
  TARGET=$(git branch -r --list 'origin/release/*' --format='%(refname:short)' |
    sed 's|^origin/||' | sort -V | tail -1)
  [ -n "$TARGET" ] || { echo "error: no origin/release/* branch found" >&2; exit 1; }
fi
git rev-parse --verify "origin/${TARGET}" >/dev/null 2>&1 ||
  { echo "error: branch origin/${TARGET} not found" >&2; exit 1; }

BASE=$(git merge-base "origin/${TARGET}" origin/master)

# shas already ported via cherry-pick -x trailers
declare -A PORTED
while read -r sha; do
  [ -n "$sha" ] && PORTED[$sha]=1
done < <(git log --format=%B "${BASE}..origin/${TARGET}" 2>/dev/null |
  grep -oE 'cherry picked from commit [0-9a-f]{40}' | awk '{print $5}')

# git cherry: "+ sha" = not on target (by patch-id), "- sha" = equivalent exists
fixes=""
others=""
fix_count=0
other_count=0
while read -r mark sha; do
  [ "$mark" = "+" ] || continue
  [ -n "${PORTED[$sha]:-}" ] && continue
  subject=$(git log -1 --format=%s "$sha")
  # skip automated bumps/CI commits
  author=$(git log -1 --format=%an "$sha")
  case "$author" in *"[bot]"*) continue ;; esac
  short=$(git rev-parse --short "$sha")
  pr=$(grep -oE '#[0-9]+' <<<"$subject" | head -1 || true)
  line="- [ ] \`${short}\` ${subject} (${author}${pr:+, ${pr}})"
  if grep -qiE '^(fix|hotfix|bugfix)([(:! ]|$)|^[a-z0-9_-]+: *fix' <<<"$subject"; then
    fixes+="${line}"$'\n'
    fix_count=$((fix_count + 1))
  else
    others+="${line#- [ ] }"$'\n'
    other_count=$((other_count + 1))
  fi
done < <(git cherry "origin/${TARGET}" origin/master "$BASE")

REPORT=$(cat <<EOF
## Port audit: \`${TARGET}\` vs \`master\`

Base: \`$(git rev-parse --short "$BASE")\` · generated $(date -u +%Y-%m-%dT%H:%MZ)

### Candidate fixes not ported (${fix_count})

${fixes:-_none — all caught up_ }

<details><summary>Other unported commits (${other_count}) — held for next major</summary>

${others:-none}

</details>
EOF
)

echo "$REPORT"
if [ -n "${GITHUB_STEP_SUMMARY:-}" ]; then
  echo "$REPORT" >> "$GITHUB_STEP_SUMMARY"
fi

if [ "$UPDATE_ISSUE" = 1 ]; then
  REPO="${GITHUB_REPOSITORY:-$(gh repo view --json nameWithOwner --jq .nameWithOwner)}"
  TITLE="Port status: ${TARGET}"
  num=$(gh issue list --repo "$REPO" --state open --search "in:title \"${TITLE}\"" \
    --json number,title --jq "map(select(.title == \"${TITLE}\")) | .[0].number // empty")
  if [ -z "$num" ]; then
    num=$(gh issue create --repo "$REPO" --title "$TITLE" --body "$REPORT" | grep -oE '[0-9]+$')
    echo "created tracking issue #${num}" >&2
  else
    gh issue edit "$num" --repo "$REPO" --body "$REPORT" >/dev/null
    echo "updated tracking issue #${num}" >&2
  fi
fi
