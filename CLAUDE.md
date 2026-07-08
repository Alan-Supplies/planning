# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this repository is

This is **not an application codebase**. It is Alan's personal/team planning and knowledge-base repo
for work on **Preppers** (a restaurant ordering platform: KDS/POS/KIOSK/ORDER/AUTH servers). It holds
daily logs, meeting notes, architecture references, Jira/sprint planning, saved Claude Code plans, and
one Claude Code Skill. The actual product source lives in separate repositories (e.g. `preppers-server`)
that are not part of this repo — conventions here (branching, commit style, etc.) describe how to work
in *those* repos, not this one.

There is no build, lint, or test pipeline for this repository itself.

## Directory layout

- `daily/` — daily work logs, one file per day named `YYMMDD.md` (e.g. `260408.md`).
- `docs/` — reference docs grouped by topic: `plans/` (specs and TODOs per initiative), `preppers/`
  (product docs, see `ARCHITECTURE.md`), `order/`, `pos/`, `db/`, `deployment/`, `monitoring/`,
  `grafana/`, `network/`, `보안/` (security), `restful/`, `메뉴/`, `회의/` (meeting notes), etc.
  - `docs/ai/` — Claude Code operating conventions, one file per tool/topic. Some files chain via
    `@other.md` imports (e.g. `data.md` → `db.md`, `deploy.md` → `github.md` + `jira.md`) — this is
    the repo's existing pattern for composing AI context, reused below.
  - `docs/plans/*.plan.md` — plans saved from Claude Code's plan mode (hashed filename suffix);
    treat these as historical records of what was proposed/done, not living specs.
- `project/<name>/` — scoped spikes/investigations, typically with a `GOAL.md` stating the hypothesis,
  success criteria, and scope boundaries (see `project/test-fly/GOAL.md`).
- `skill/fit-parser/` — a Claude Code **Skill** (`SKILL.md`) for parsing Garmin `.fit` activity files.
- `러닝/` — personal running data: source `.fit` files plus this skill's `_records.csv` / `_summary.json`
  output, dated `YYYYMMDD설명.fit`.
- `api/` — `.http` request collections (e.g. `opensearch/base.http`) for the VS Code REST Client extension.
- `kds-dev.session.sql`, `.vscode/settings.json` — ad-hoc queries and a SQLTools connection profile for
  the read-only `kds-dev` MySQL database; credentials are documented in `docs/ai/db.md`, do not duplicate
  them elsewhere.
- `sprint/`, `presentation/`, `매장/`, `희의/` — sprint notes, presentation prep, per-store notes, and
  meeting notes.

## Commands

- Parse a Garmin `.fit` file: `python3 skill/fit-parser/scripts/parse_fit.py <fit-file>` — writes
  `<name>_records.csv` and `<name>_summary.json` next to the input file.
- Run ad-hoc queries against `kds-dev`: use the `kds-dev` connection in `.vscode/settings.json`
  (SQLTools extension, read-only) or the queries in `kds-dev.session.sql`.
- Exercise OpenSearch/API endpoints: open `api/opensearch/base.http` with the REST Client extension.

## Conventions

From `.cursorrules`:
- Prefix each reply with `[topic] {YYYY-MM-DD HH:MM}` derived from the question's timing/subject.
- Ask a clarifying question when information needed to answer is missing, rather than guessing.
- Always tag fenced code blocks with a language (use `text` for plain text).
- New reference material goes under `docs/<topic>/`; new daily entries go in `daily/YYMMDD.md`.

Per-tool conventions used when Claude Code operates on the linked product repos (imported so they load
automatically — see each file for full detail):

- @docs/ai/github.md
- @docs/ai/jira.md
- @docs/ai/notion.md
- @docs/ai/slack.md
- @docs/ai/test.md
- @docs/ai/sales.md
- @docs/ai/db.md

## Product architecture (context for planning docs)

The Preppers system this repo plans for has five services (see `docs/preppers/ARCHITECTURE.md` for the
full diagram):
- `KDS` (kitchen display, per-position order view) talks to `KDS_SERVER`.
- `POS` (delivery-platform/counter orders) and `KIOSK` (self-service orders) each talk to their own
  server, which forwards standardized orders to `ORDER_SERVER`.
- `AUTH_SERVER` issues JWTs for all three clients.
- `ORDER_SERVER` and `KDS_SERVER` both read/write a shared MySQL ledger.
