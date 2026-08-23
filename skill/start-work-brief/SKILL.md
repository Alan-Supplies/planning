---
name: start-work-brief
description: Update the current branch from its configured upstream, then brief the user on today's work by combining the repository's important-issues control board with today's daily note. Ask a focused catch-up question when recent work changes may be missing from those records. Use when the user says “오늘 업무 시작”, “업무 시작하자”, asks what to work on today, or needs help reloading and correcting their work context before starting.
---

# Start Work Brief

Restore the user's work context with a short, conversational briefing. Optimize for orientation and initiation, not exhaustive status reporting.

## Workflow

1. Before reading planning files, inspect the current branch and its configured upstream, then run `git pull --ff-only`. The startup request authorizes this pull. Do not switch branches, stash or discard changes, create commits, merge, rebase, or resolve conflicts automatically. If no upstream is configured or the pull fails because of local changes, divergence, authentication, network access, or any other reason, report the exact issue and stop before producing a potentially stale briefing.
2. Determine today's date in the user's local timezone and format it as `YYMMDD`.
3. Read `plan/중요이슈결정및계획.md`.
4. Read the most recent previous daily note, normally yesterday's `daily/YYMMDD.md`.
5. Read today's `daily/YYMMDD.md` if it exists.
6. Check whether the previous daily note records what actually happened. Treat the record as incomplete when planned work has no outcome and the `완료 및 결과` or `종료 점검` section is empty or still contains template placeholders. Do not infer completion from plans, unchecked boxes, or uncommitted files.
7. If the previous day's actual progress is missing, ask one focused question before creating or finalizing today's note. Name the previous day's primary task and any concrete result already visible in the note. Ask what was completed, what remains, and the next action without presenting a long questionnaire.
8. After the user answers, update the previous daily note with the smallest accurate change:
   - Mark an item complete only when the user confirms its verifiable completion condition was met.
   - Record actual completed work separately from incomplete work.
   - Fill the closeout status as `완료`, `재계획`, `대기`, or `중단`, with the reason and next action.
   - Preserve existing details and do not rewrite unrelated entries.
9. Use the corrected previous-day state when creating or updating today's note and briefing. If the user reports no progress, record that fact and carry forward only a concrete next action rather than copying the whole plan blindly.
10. Follow links only when the documents do not reveal the current position or the next concrete action.
11. Reconcile the documents:
   - Treat the important-issues document as the source of priority and overall direction.
   - Treat today's daily note as the source of today's commitment, current progress, and immediate execution details.
   - Call out a meaningful mismatch briefly instead of silently choosing one.
12. Check whether another recent work change may be missing. Treat any of these as a signal, not proof:
   - Today's note is missing, empty, or only repeats an older plan.
   - A task's stated next action appears overdue without a result or status update.
   - The documents disagree about completion, ownership, priority, or the next action.
   - The latest recorded progress leaves an obvious gap between what was planned and what should happen today.
13. If a missing change could materially alter today's briefing, ask one focused catch-up question before finalizing it. Name the specific task and the suspected gap; do not ask a generic question such as “업데이트 있나요?”. When useful, mention two or three likely statuses in plain language. Wait for the answer, then reconcile it with the documents and continue the briefing.
14. If the gap is minor or the available evidence is sufficient, give a provisional briefing and put one concise confirmation question at the end instead of blocking progress.
15. Give the briefing in Korean unless the user is speaking another language.

## Catch-up Questions

- Ask only about the single missing change most likely to affect today's priority or first action.
- Prefer questions grounded in the last recorded state, for example: “결제 오류 PR은 어제 리뷰 대기였는데, 지금은 머지 완료·수정 중·계속 대기 중 어디에 가까운가요?”
- Distinguish the user's answer from repository-confirmed facts when they conflict.
- For a missing previous-day closeout, use the answer immediately to update that daily note and finish today's briefing. For other catch-up answers, edit planning files only when the user asks.

## Briefing Shape

Keep the response compact and conversational. Include:

- **오늘의 한 가지:** the single outcome that matters most today.
- **현재 위치:** the latest meaningful progress or dependency.
- **첫 행동:** one concrete action the user can start immediately.
- **놓치면 안 될 것:** at most one time-sensitive follow-up, risk, or pending decision.

End with one small, action-oriented question that helps the user begin, such as whether to inspect a named PR or open the next working document. If a minor catch-up confirmation is still needed, use that as the ending question. Do not present a large menu of choices.

## Guardrails

- Prefer 4–8 short lines; avoid reproducing the full task list.
- Lead with the primary outcome, not document-reading details.
- Distinguish confirmed facts from suggestions.
- Do not mark tasks complete without explicit confirmation, merge changes, delete data, or perform unrelated work. The startup request authorizes only the previous-day closeout correction and today's daily-note creation or update described above.
- If today's daily file is missing, say so briefly, derive a provisional briefing from the control board, and offer to create the daily note.
- If both files are missing, report the missing paths and ask where the planning sources are.
