# traffic-stats

A single, central collector for GitHub **clone ("Downloads") traffic** across all
your repos. One scheduled workflow snapshots each repo's 14-day clone window,
accumulates an **all-time per-repo tally**, and publishes one
[Shields](https://shields.io) badge per repo via **GitHub Pages**.

**Why this instead of a per-repo workflow:** GitHub only keeps 14 days of clone
traffic, so *something* must persist the running total. Doing that with a daily
commit inside each product repo clutters its history. Here, the only commits land
in **this throwaway stats repo** (never in your product repos), and the badges are
served from Pages — a CDN, so the badge always renders (no shields→GitHub 524).

```
repos.txt ──► scripts/collect.sh ──► data/<owner>__<repo>.json   (committed here, durable)
                                 └─► public/<repo>.json           (served via Pages → badge)
```

---

## One-time setup

1. **Create the repo.** Push this directory to a new GitHub repo named
   `traffic-stats` (any name works — it only affects the Pages URL below):
   ```bash
   cd traffic-stats
   git init && git add -A && git commit -m "Central clone-traffic collector"
   gh repo create traffic-stats --public --source . --push
   ```
   Public or private both work; a **public** repo gets free Pages.

2. **Create a PAT** with clone-traffic access to every repo you'll track. The
   built-in `GITHUB_TOKEN` can't do this — it only covers this repo.
   - **Fine-grained** (preferred): select the repos to track (or "all repos"),
     and grant **Repository permissions → Administration: Read-only** (that's what
     the clone-traffic API requires) plus **Contents: Read and write** (to commit
     `data/` here — or just include this repo).
   - **Classic**: scope `repo`.

   Add it as an Actions secret on this repo named **`TRAFFIC_TOKEN`**:
   ```bash
   gh secret set TRAFFIC_TOKEN
   ```

3. **Enable Pages from Actions.** Repo → **Settings → Pages → Build and
   deployment → Source: GitHub Actions**. (No branch to pick — the workflow
   deploys an artifact.)

4. **First run.** Actions → *Traffic — collect clone stats* → **Run workflow**.
   It commits the first `data/` snapshot and deploys the badges. Your badges are
   then live at:
   ```
   https://<owner>.github.io/traffic-stats/<repo>.json
   ```

---

## Add a repo to track

Edit **`repos.txt`** — one `owner/repo` per line — and commit. Make sure your
`TRAFFIC_TOKEN` has Administration:Read on it. The next run picks it up (or run
the workflow manually).

## Add the badge to a product repo's README

Paste into that repo's `README.md` (swap `<owner>`/`harbor`):

```markdown
[![Downloads](https://img.shields.io/endpoint?url=https://<owner>.github.io/traffic-stats/harbor.json)](https://github.com/<owner>/harbor)
```

The badge file is named after the **repo** (the part after `/`), so
`alaa-almaliki/harbor` → `harbor.json`.

---

## How it works / notes

- **No double-counting, no lost days.** `data/` is keyed by `YYYY-MM-DD`;
  re-fetching a day overwrites it with GitHub's latest number. Running daily keeps
  every day inside the 14-day window. The all-time total is the exact sum of daily
  `count`s. (Unique-cloner counts are per-window only — the same person recurs
  across weeks — so they're intentionally not summed.)
- **What gets committed:** only `data/*.json`, and only when it changes
  (`[skip ci]`). Badges (`public/*.json`) are regenerated each run and deployed to
  Pages via artifact — never committed (see `.gitignore`).
- **Badge reliability:** served from the Pages CDN with a 12-hour shields cache
  (`cacheSeconds`), so it renders fast and can't 524 the way a
  `raw.githubusercontent.com` endpoint can.
- **Resilience:** one repo failing (e.g. token missing access) logs an error and
  the run exits non-zero, but the other repos are still updated. If runs fail for
  **14 consecutive days**, that window's clones are unrecoverable (GitHub's limit,
  not this tool's).
- **History pre-dating your first run is gone** — GitHub doesn't expose clones
  older than 14 days, so the all-time tally starts accumulating from run one.

## Local test

```bash
GH_TOKEN=<a PAT with the access above> bash scripts/collect.sh
cat data/*.json public/*.json
```
