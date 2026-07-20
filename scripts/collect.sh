#!/usr/bin/env bash
# collect.sh — accumulate GitHub "git clones" traffic for MANY repos into
# per-repo all-time tallies, and emit a Shields endpoint badge per repo.
#
# GitHub retains only the last 14 days of clone traffic, so this snapshots that
# window and merges it into a persistent, date-keyed per-repo store. The workflow
# runs daily (well inside the 14-day window); re-fetching an already-recorded day
# overwrites it with GitHub's latest number for that day, so nothing is ever
# double-counted and no day is ever lost.
#
# Reads:  repos.txt                    one "owner/repo" per line ('#'/blank ok)
# Writes: data/<owner>__<repo>.json    persistent per-repo store   (committed)
#         public/<repo>.json           Shields endpoint badge      (served via Pages,
#                                       NOT committed — regenerated each run)
#
# Env:
#   GH_TOKEN   a token with Administration:Read (clone traffic) on EVERY tracked
#              repo. The built-in GITHUB_TOKEN only covers this stats repo, so a
#              PAT is required — see README.md. Fed from secrets.TRAFFIC_TOKEN.
set -euo pipefail

token="${GH_TOKEN:?GH_TOKEN not set — add a TRAFFIC_TOKEN secret (see README.md)}"
list="${1:-repos.txt}"
[ -f "$list" ] || { echo "::error::repo list '$list' not found" >&2; exit 1; }

mkdir -p data public
failures=0

while IFS= read -r line || [ -n "$line" ]; do
  # strip inline '#' comment + all whitespace; skip blanks/comments
  repo="$(printf '%s' "$line" | sed 's/#.*//' | tr -d '[:space:]')"
  [ -n "$repo" ] || continue
  case "$repo" in
    */*) ;;
    *) echo "::warning::skipping malformed entry '$repo' (want owner/repo)" >&2; continue ;;
  esac

  owner="${repo%%/*}"; name="${repo##*/}"
  data="data/${owner}__${name}.json"
  badge="public/${name}.json"
  [ -f "$data" ] || printf '{}\n' > "$data"

  # Last-14-days clone traffic. Status captured separately so a non-2xx (e.g.
  # 403/404 = token lacks Administration:Read on this repo) gives an actionable
  # error rather than a bare curl failure — and one bad repo doesn't abort the
  # rest (recorded as a failure, non-zero exit at the end).
  body="$(mktemp)"
  status="$(curl -sSL -o "$body" -w '%{http_code}' \
    -H "Authorization: Bearer $token" \
    -H "Accept: application/vnd.github+json" \
    -H "X-GitHub-Api-Version: 2022-11-28" \
    "https://api.github.com/repos/$repo/traffic/clones" || echo 000)"

  if [ "$status" != 200 ]; then
    echo "::error::$repo — clone-traffic API returned HTTP $status (does the token have Administration:Read on it?)" >&2
    sed 's/^/  api: /' "$body" >&2 || true
    rm -f "$body"; failures=$((failures + 1)); continue
  fi
  resp="$(cat "$body")"; rm -f "$body"

  # Merge each day's {count,uniques} into the store, keyed by YYYY-MM-DD.
  merged="$(jq -n --argjson old "$(cat "$data")" --argjson new "$resp" '
    reduce ($new.clones[]?) as $c ($old;
      .[$c.timestamp[0:10]] = {count: $c.count, uniques: $c.uniques})')"
  printf '%s\n' "$merged" > "$data"

  # All-time total = exact sum of daily counts. Uniques are per-window only (the
  # same cloner recurs across weeks), so they are deliberately not totalled.
  total="$(printf '%s' "$merged" | jq '[.[].count] | add // 0')"

  # Shields endpoint badge. Pages serves this from a CDN, so shields' fetch is
  # fast and reliable (no origin 524). cacheSeconds throttles shields' refetch —
  # the number only moves once a day, so 12h is plenty.
  jq -n --arg msg "$total" '{
    schemaVersion: 1,
    label: "Downloads",
    message: $msg,
    color: "blue",
    cacheSeconds: 43200
  }' > "$badge"

  printf '  %-42s total_clones=%s\n' "$repo" "$total"
done < "$list"

if [ "$failures" -gt 0 ]; then
  echo "::error::$failures repo(s) failed — see errors above" >&2
  exit 1
fi
echo "done."
