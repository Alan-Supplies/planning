---
name: start-work-brief
description: Brief the user on today's work by combining the repository's important-issues control board with today's daily note. Use when the user says “오늘 업무 시작”, “업무 시작하자”, asks what to work on today, or needs help reloading their work context before starting.
---

# Start Work Brief

Restore the user's work context with a short, conversational briefing. Optimize for orientation and initiation, not exhaustive status reporting.

## Workflow

1. Determine today's date in the user's local timezone and format it as `YYMMDD`.
2. Read `plan/중요이슈결정및계획.md`.
3. Read `daily/YYMMDD.md`.
4. Follow links only when the two documents do not reveal the current position or the next concrete action.
5. Reconcile the documents:
   - Treat the important-issues document as the source of priority and overall direction.
   - Treat today's daily note as the source of today's commitment, current progress, and immediate execution details.
   - Call out a meaningful mismatch briefly instead of silently choosing one.
6. Give the briefing in Korean unless the user is speaking another language.

## Briefing Shape

Keep the response compact and conversational. Include:

- **오늘의 한 가지:** the single outcome that matters most today.
- **현재 위치:** the latest meaningful progress or dependency.
- **첫 행동:** one concrete action the user can start immediately.
- **놓치면 안 될 것:** at most one time-sensitive follow-up, risk, or pending decision.

End with one small, action-oriented question that helps the user begin, such as whether to inspect a named PR or open the next working document. Do not present a large menu of choices.

## Guardrails

- Prefer 4–8 short lines; avoid reproducing the full task list.
- Lead with the primary outcome, not document-reading details.
- Distinguish confirmed facts from suggestions.
- Do not mark tasks complete, edit planning files, merge changes, delete data, or perform other work unless the user separately asks.
- If today's daily file is missing, say so briefly, derive a provisional briefing from the control board, and offer to create the daily note.
- If both files are missing, report the missing paths and ask where the planning sources are.
