---
name: start-work-brief
description: Start today's work with a concise, Linear-led view of major workstreams classified as ahead of plan, on track, or delayed/at risk. Reconcile the repository's control board and daily notes, then identify one outcome to finish today. Use when the user says “오늘 할 일 시작”, “오늘 업무 시작”, “업무 시작하자”, or asks what to work on today.
---

# Start Work Brief

Give the user a quick sense of whether their important work is moving well. Lead with the three-way assessment of workstreams or milestones, then choose today's one essential outcome. Individual issue details support the judgment; they are not the main briefing.

## Sources and startup

1. Use the user's local date. In this repository, the control board is `roadmap/중요이슈결정및계획.md`; recent daily notes are normally `daily/YYMM/YYMMDD.md`, with older notes sometimes directly under `daily/`. Find the latest note by date rather than assuming yesterday has one.
2. Inspect the current branch and configured upstream and attempt `git pull --ff-only` before relying on repository notes. The startup request authorizes this pull. Do not switch branches, stash, discard, commit, merge, rebase, or resolve conflicts. If the pull fails, state why and treat local notes as potentially stale; continue with live Linear when available.
3. Use the user's explicit priority as the starting point. Read the control board and recent daily outcome for intended priorities, promises, and dependencies. Read today's note if present.
4. Check current Linear projects, milestones, and the few linked issues needed to judge those priorities. Linear is the primary source for ownership, dates, status, scope, and recent decisions. Use PRs, workflow results, package versions, or other delivery evidence when a Linear status alone cannot establish whether a milestone gate passed. Keep the source and time of a judgment clear.
5. If Linear cannot be reached, tell the user and ask for the missing workstream progress. Give a clearly provisional view from available notes while waiting. Do not infer that no work happened merely because a local note or Linear status is old.

## Classify the work, not the ticket list

Group related issues into no more than a few meaningful workstreams or milestones. Compare each with its planned gate and date, the dependency order, and evidence of completed work. Classify each workstream under one of these headings:

- **예상보다 잘 진행:** a verifiable milestone result or useful downstream validation arrived earlier than planned. A low Linear percentage by itself is not evidence of being ahead.
- **정상진행중:** the next gate has a credible path to its target date, with active implementation or verification and no unresolved blocker that makes the date implausible.
- **늦어지거나 진행 안 됨:** a target has passed, planned dates conflict with remaining work, a critical gate is blocked, or expected work has no meaningful progress. Say `지연 확정` or `위험 신호` explicitly; a future phase intentionally waiting on a prerequisite is not automatically late.

Use one short row per material workstream, not one row per issue. If a category has no supported item, say `현재 없음`. Treat progress percentages as context only: newly added issues can lower the percentage while implementation advances. Check the actual finish gate. A final integration or release PR that depends on several tasks belongs **after** those tasks; do not recommend it as the immediate next action.

For each row, give the evidence in plain language and the next gate or decision date. Link to the relevant Linear project or issue. Keep detailed issue and PR lists out of the briefing unless a specific blocker cannot be understood without them.

## Choose today's work and reconcile records

After the three-way view, state **오늘 반드시 끝낼 1개** with a verifiable completion condition and one first action. Select it from the user's priority and the most consequential next gate, not merely the nearest due date or a low-priority ticket. Mention at most one other time-sensitive dependency.

Check whether the last daily note distinguishes actual results from unfinished work. If a missing result or stale decision would change today's priority, ask one bundled, specific question while continuing independent checks; do not make the whole briefing wait when reliable current evidence exists. Treat the user's answer and verified external evidence as evidence, and note unresolved conflicts.

Create or update today's daily note when the startup request calls for starting the day. Put the three-way workstream snapshot near the top, before the detailed task list. Record the single essential outcome, completion condition, first action, and any material unresolved gate. Update the control board only when the priority or status actually changed. Preserve prior-day history and distinguish completed, incomplete, waiting, and replanned work. A verifiable completion may come from the user or delivery evidence; do not mark it complete from a plan, a checkbox, or an unreviewed PR alone.

## Briefing shape

In Korean unless the user speaks another language:

1. A compact three-row table: **분류 · 업무 흐름 · 판단 근거와 다음 관문**. Show the project-level picture first.
2. **오늘 반드시 끝낼 1개:** outcome and measurable finish condition.
3. **첫 행동:** one concrete action. Add a question only when missing information materially changes the choice.

Keep the visible briefing short. A detailed audit can live in the daily note or a linked investigation document. Stop once the user can tell what is ahead, what is on schedule, what needs attention, and what to do first.
