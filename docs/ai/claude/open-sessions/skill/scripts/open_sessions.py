#!/usr/bin/env python3
"""열려 있는 Claude Code 세션의 진행 상태를 정리한다.

`~/.claude/sessions/*.json` 으로 살아 있는 탭을 찾고, 각 탭의 transcript
(`~/.claude/projects/<slug>/<sessionId>.jsonl`) 를 읽어 어디까지 갔는지와
지금 닫아도 되는지를 판정한다. 읽기 전용이며 아무것도 수정하지 않는다.
"""

from __future__ import annotations

import argparse
import json
import os
import re
import shutil
import subprocess
import sys
from concurrent.futures import ThreadPoolExecutor
from datetime import datetime, timedelta, timezone
from pathlib import Path
from typing import Any

KST = timezone(timedelta(hours=9))
HOME = Path.home()
SESSIONS_DIR = HOME / ".claude" / "sessions"
PROJECTS_DIR = HOME / ".claude" / "projects"

IDE_BLOCK = re.compile(r"<ide_[^>]+>.*?</ide_[^>]+>", re.S)
REMINDER = re.compile(r"<system-reminder>.*?</system-reminder>", re.S)
TAG = re.compile(r"<[^>]+>")
WS = re.compile(r"\s+")

NOISE_USER = re.compile(
    r"^(Caveat:|/\w+\b|\[Request interrupted|<command-|Set (effort level|model)\b|"
    r"This session is being continued|Please continue the conversation)",
    re.I,
)
ASKING = re.compile(
    r"(할까요?\?|하시겠|어느\s*쪽|골라\s*주|선택해\s*주|알려\s*주|말해\s*주|"
    r"진행할까|맞나요?\?|괜찮을까|어떻게\s*할까|원하시면|정해\s*주)"
)
DONE = re.compile(
    r"(완료했습니다|완료됐|반영했습니다|반영 완료|적용했습니다|적용 완료|"
    r"머지했습니다|배포했습니다|끝났습니다|통과했습니다|^##?\s*완료|✅)",
    re.M,
)
PROPOSING = re.compile(r"(원하면|원하시면|적용할까|고칠까|이어서 할|다음 단계)")

# 닫기 권고 등급
BLOCK, CHECK, OK = "지금 닫지 마라", "닫기 전 확인", "닫아도 된다"
GROUP_ORDER = [BLOCK, CHECK, OK]


# ---------------------------------------------------------------- 살아있는 탭

def pid_alive(pid: Any) -> bool:
    if not isinstance(pid, int) or pid <= 0:
        return False
    try:
        os.kill(pid, 0)
    except ProcessLookupError:
        return False
    except PermissionError:
        # 프로세스는 있는데 시그널 권한이 없다 — 샌드박스 안에서 남의 탭을 볼 때 이렇게 된다.
        return True
    except OSError:
        return False
    return True


def live_sessions(target_cwd: str | None) -> tuple[list[dict[str, Any]], dict[str, Any]]:
    """pid 가 살아 있는 세션을 sessionId 기준으로 중복 제거해 돌려준다.

    0개로 끝났을 때 "탭이 없다" 와 "디렉토리를 못 읽었다" 를 구분해야 하므로 집계도 같이 낸다.
    """
    found: dict[str, dict[str, Any]] = {}
    stats: dict[str, Any] = {
        "readable": True, "files": 0, "unreadable": 0, "dead": 0, "other_cwd": 0,
    }
    if not SESSIONS_DIR.is_dir():
        stats["readable"] = False
        return [], stats
    for path in SESSIONS_DIR.glob("*.json"):
        stats["files"] += 1
        try:
            data = json.loads(path.read_text(encoding="utf-8"))
        except (OSError, json.JSONDecodeError):
            stats["unreadable"] += 1
            continue
        sid = data.get("sessionId")
        if not isinstance(sid, str):
            stats["unreadable"] += 1
            continue
        if not pid_alive(data.get("pid")):
            stats["dead"] += 1
            continue
        cwd = data.get("cwd") or ""
        if target_cwd and os.path.realpath(cwd) != target_cwd:
            stats["other_cwd"] += 1
            continue
        prev = found.get(sid)
        if prev is None or (data.get("updatedAt") or 0) > (prev.get("updatedAt") or 0):
            data["_procs"] = (prev or {}).get("_procs", 0) + 1
            found[sid] = data
        else:
            prev["_procs"] = prev.get("_procs", 0) + 1
    return list(found.values()), stats


# ---------------------------------------------------------------- transcript

def text_of(content: Any) -> str:
    if isinstance(content, str):
        return content
    if not isinstance(content, list):
        return ""
    parts = [
        item.get("text") or ""
        for item in content
        if isinstance(item, dict) and item.get("type") == "text"
    ]
    return "\n".join(p for p in parts if p)


def blocks_of(content: Any, kind: str) -> list[dict[str, Any]]:
    if not isinstance(content, list):
        return []
    return [i for i in content if isinstance(i, dict) and i.get("type") == kind]


def clean(text: str) -> str:
    text = REMINDER.sub("", IDE_BLOCK.sub("", text))
    return WS.sub(" ", TAG.sub("", text)).strip()


def clip(text: str, n: int) -> str:
    text = WS.sub(" ", text).strip()
    return text if len(text) <= n else text[: n - 1] + "…"


def parse_ts(value: Any) -> datetime | None:
    if isinstance(value, (int, float)):
        return datetime.fromtimestamp(value / 1000 if value > 1e12 else value, KST)
    if isinstance(value, str):
        try:
            return datetime.fromisoformat(value.replace("Z", "+00:00")).astimezone(KST)
        except ValueError:
            return None
    return None


def display_name(raw: dict[str, Any], info: dict[str, Any]) -> str:
    """탭에 붙은 `<폴더>-<임의 2자리>` 태그 대신 사람이 알아볼 이름을 고른다."""
    if raw.get("nameSource") == "user" and raw.get("name"):
        return str(raw["name"])
    if info["title"]:
        return info["title"]
    if info["purpose"]:
        return clip(info["purpose"], 60)
    return str(raw.get("name") or raw["sessionId"][:8])


def transcript_path(session: dict[str, Any]) -> Path | None:
    cwd = session.get("cwd") or ""
    sid = session["sessionId"]
    slug = os.path.abspath(cwd).replace("/", "-")
    for base in (PROJECTS_DIR / slug, *sorted(PROJECTS_DIR.glob("*"))):
        candidate = base / f"{sid}.jsonl"
        if candidate.is_file():
            return candidate
    return None


def empty_info() -> dict[str, Any]:
    return {
        "title": "", "branch": "", "purpose": "", "last_user": "",
        "last_assistant": "", "user_turns": 0, "tools": {}, "files": [],
        "prs": [], "background": [], "worktree": None, "worktree_open": False,
        "plan_exits": 0, "last_tool": "", "tail": "", "last_ts": None,
        "pending_tool": "", "permission_mode": "",
    }


def read_transcript(path: Path) -> dict[str, Any]:
    """진행 상태 판정에 쓰는 신호만 뽑는다."""
    out = empty_info()
    tools: dict[str, int] = {}
    files: list[str] = []
    prs: list[dict[str, Any]] = []
    background: list[str] = []
    open_tool_ids: dict[str, str] = {}
    tail_kind = ""

    with path.open(encoding="utf-8") as handle:
        for line in handle:
            line = line.strip()
            if not line:
                continue
            try:
                obj = json.loads(line)
            except json.JSONDecodeError:
                continue

            kind = obj.get("type")
            if obj.get("gitBranch"):
                out["branch"] = str(obj["gitBranch"])
            ts = parse_ts(obj.get("timestamp"))
            if ts and kind in {"user", "assistant"} and not obj.get("isSidechain"):
                if out["last_ts"] is None or ts > out["last_ts"]:
                    out["last_ts"] = ts

            if kind == "ai-title" and obj.get("aiTitle"):
                out["title"] = str(obj["aiTitle"])
            elif kind == "pr-link":
                prs.append({
                    "number": obj.get("prNumber"),
                    "repo": obj.get("prRepository") or "",
                    "url": obj.get("prUrl") or "",
                })
            elif kind == "permission-mode":
                out["permission_mode"] = str(obj.get("permissionMode") or "")
            elif kind == "worktree-state":
                wt = obj.get("worktreeSession") or {}
                if wt:
                    out["worktree"] = {
                        "name": wt.get("worktreeName") or "",
                        "branch": wt.get("worktreeBranch") or "",
                        "path": wt.get("worktreePath") or "",
                    }
            elif kind == "user":
                if obj.get("isMeta"):
                    continue
                content = (obj.get("message") or {}).get("content")
                results = blocks_of(content, "tool_result")
                if results:
                    for res in results:
                        open_tool_ids.pop(res.get("tool_use_id") or "", None)
                    continue
                body = clean(text_of(content))
                if not body or NOISE_USER.search(body):
                    continue
                out["user_turns"] += 1
                out["purpose"] = out["purpose"] or body
                out["last_user"] = body
                tail_kind = "user"
            elif kind == "assistant":
                content = (obj.get("message") or {}).get("content")
                for call in blocks_of(content, "tool_use"):
                    name = str(call.get("name") or "")
                    tools[name] = tools.get(name, 0) + 1
                    out["last_tool"] = name
                    open_tool_ids[str(call.get("id") or "")] = name
                    inp = call.get("input") or {}
                    if name in {"Edit", "Write", "NotebookEdit"} and inp.get("file_path"):
                        files.append(str(inp["file_path"]))
                    if inp.get("run_in_background"):
                        background.append(
                            f"{name}: {clip(str(inp.get('description') or inp.get('command') or ''), 50)}"
                        )
                    if name == "EnterWorktree":
                        out["worktree_open"] = True
                    elif name == "ExitWorktree":
                        out["worktree_open"] = False
                    elif name == "ExitPlanMode":
                        out["plan_exits"] += 1
                    tail_kind = "tool_use"
                body = text_of(content)
                if body.strip():
                    out["last_assistant"] = body
                    tail_kind = "assistant"

    out["tools"] = tools
    out["files"] = list(dict.fromkeys(files))
    out["prs"] = list({p["number"]: p for p in prs if p["number"]}.values())
    out["background"] = background
    out["tail"] = tail_kind
    out["pending_tool"] = next(iter(open_tool_ids.values()), "")
    return out


# ---------------------------------------------------------------- git / gh

def find_gh() -> str | None:
    return shutil.which("gh") or next(
        (p for p in ("/opt/homebrew/bin/gh", "/usr/local/bin/gh") if os.path.exists(p)),
        None,
    )


def run(cmd: list[str], cwd: str, timeout: int = 8) -> str | None:
    try:
        proc = subprocess.run(
            cmd, cwd=cwd, capture_output=True, text=True, timeout=timeout
        )
    except (OSError, subprocess.SubprocessError):
        return None
    if proc.returncode != 0:
        return None
    return proc.stdout.strip()


def unpushed(cwd: str, branch: str) -> dict[str, Any] | None:
    """브랜치의 미푸시 커밋 수. 업스트림이 없으면 그 사실을 알린다."""
    if not branch or not os.path.isdir(cwd):
        return None
    upstream = run(["git", "rev-parse", "--abbrev-ref", "--symbolic-full-name", "@{u}"], cwd)
    if upstream is None:
        return {"no_upstream": True, "count": 0}
    count = run(["git", "rev-list", "--count", "@{u}..HEAD"], cwd)
    if count is None or not count.isdigit():
        return None
    return {"no_upstream": False, "count": int(count)}


PR_FIELDS = "number,state,isDraft,reviewDecision,mergeStateStatus,title"


def gh_pr(gh: str, cwd: str, *selector: str) -> dict[str, Any] | None:
    raw = run([gh, "pr", "view", *selector, "--json", PR_FIELDS], cwd, timeout=15)
    if not raw:
        return None
    try:
        return json.loads(raw)
    except json.JSONDecodeError:
        return None


def pr_state(gh: str, cwd: str, branch: str, recorded: list[dict[str, Any]]) -> dict[str, Any] | None:
    """브랜치로 먼저 찾고, 없으면 세션이 남긴 PR 번호로 조회한다."""
    if not gh or not os.path.isdir(cwd):
        return None
    if branch:
        found = gh_pr(gh, cwd, branch)
        if found:
            return found
    for pr in reversed(recorded[-2:]):
        selector = [str(pr["number"])]
        if pr.get("repo"):
            selector += ["-R", pr["repo"]]
        found = gh_pr(gh, cwd, *selector)
        if found:
            return found
    return None


def describe_pr(pr: dict[str, Any]) -> str:
    bits = [f"PR #{pr.get('number')}", str(pr.get("state") or "")]
    if pr.get("isDraft"):
        bits.append("draft")
    decision = pr.get("reviewDecision")
    bits.append({
        "APPROVED": "승인됨",
        "CHANGES_REQUESTED": "수정요청",
        "REVIEW_REQUIRED": "리뷰대기",
    }.get(decision, "리뷰없음" if decision in (None, "") else str(decision)))
    if pr.get("mergeStateStatus") in {"DIRTY", "BLOCKED", "BEHIND"}:
        bits.append(f"머지불가({pr['mergeStateStatus']})")
    return " · ".join(b for b in bits if b)


# ---------------------------------------------------------------- 판정

def ago(ts: datetime | None, now: datetime) -> str:
    if ts is None:
        return "시각 불명"
    secs = max(0, int((now - ts).total_seconds()))
    if secs < 60:
        return f"{secs}초 전"
    if secs < 3600:
        return f"{secs // 60}분 전"
    if secs < 86400:
        return f"{secs // 3600}시간 {secs % 3600 // 60}분 전"
    return f"{secs // 86400}일 전"


def classify(session: dict[str, Any]) -> tuple[str, str, str]:
    """(상태, 근거, 닫기 등급)."""
    runtime = session["runtime_status"]
    info = session["info"]
    tail = info["tail"]
    assistant_tail = info["last_assistant"][-1200:]

    if runtime == "busy":
        return "작업중", "응답이나 도구를 실행하는 중이다", BLOCK
    if info["user_turns"] == 0 and not info["tools"]:
        return "빈 탭", "요청을 한 번도 안 보냈다", OK
    if runtime == "waiting":
        pending = info["pending_tool"]
        why = f"{pending} 승인을 기다린다" if pending else "권한 승인이나 질문에 답을 기다린다"
        return "입력대기", why, BLOCK
    if tail == "tool_use" and info["pending_tool"]:
        return "도구 중단", f"{info['pending_tool']} 호출 뒤 결과가 없다", BLOCK
    if tail == "user":
        return "응답 없음", "내 마지막 요청에 답이 없는 채로 멈췄다", BLOCK
    if info["last_tool"] == "AskUserQuestion" and not assistant_tail:
        return "내 답 대기", "선택지를 띄우고 멈췄다", CHECK
    if ASKING.search(assistant_tail):
        return "내 답 대기", "마지막 답이 질문으로 끝났다", CHECK
    if DONE.search(assistant_tail):
        return "일단락", "마지막 답에 완료 표시가 있다", OK
    if PROPOSING.search(assistant_tail):
        return "제안만 남음", "다음 조치를 제안만 하고 적용은 안 했다", CHECK
    if info["user_turns"] <= 1:
        return "한 턴", "요청 한 번으로 끝나 후속 확인이 안 됐다", CHECK
    return "일단락", "후속 질문 없이 끝났다", OK


STALE_AFTER = timedelta(hours=2)


def riders(session: dict[str, Any], now: datetime) -> tuple[list[str], str | None, list[str]]:
    """남은 것 목록, 올려야 할 닫기 등급, 등급을 올린 사유."""
    info = session["info"]
    items: list[str] = []
    reasons: list[str] = []
    escalate: str | None = None
    last = info["last_ts"]
    stale = last is None or (now - last) > STALE_AFTER

    if info["background"]:
        count = len(info["background"])
        if stale:
            items.append(f"백그라운드 {count}건 (오래돼 이미 끝났을 것)")
        else:
            items.append(f"백그라운드 {count}건 (실행 중일 수 있음)")
            escalate = BLOCK
            reasons.append(f"백그라운드 {count}건이 아직 돌고 있을 수 있다")
    if info["worktree_open"] and info["worktree"]:
        items.append(f"worktree `{info['worktree']['name']}` 열린 채")
        if escalate is None:
            escalate = CHECK
            reasons.append("worktree 가 열려 있어 정리가 남았다")
    push = session.get("unpushed")
    if push and push.get("no_upstream"):
        items.append("업스트림 없음 — push 한 적 없는 브랜치")
        if escalate is None:
            escalate = CHECK
            reasons.append("커밋이 로컬에만 있다")
    elif push and push.get("count"):
        items.append(f"미푸시 커밋 {push['count']}개")
        if escalate is None:
            escalate = CHECK
            reasons.append(f"커밋 {push['count']}개가 아직 push 안 됐다")
    pr = session.get("pr")
    if pr:
        items.append(describe_pr(pr))
        if pr.get("state") == "OPEN" and pr.get("reviewDecision") == "CHANGES_REQUESTED":
            if escalate is None:
                escalate = CHECK
                reasons.append(f"PR #{pr.get('number')} 에 수정 요청이 있다")
    elif info["prs"]:
        nums = ", ".join(f"#{p['number']}" for p in info["prs"])
        items.append(f"이 세션에서 만든 PR {nums} (조회 실패)")
    return items, escalate, reasons


def rank(level: str) -> int:
    return GROUP_ORDER.index(level)


ADVICE = {
    "작업중": "지금 닫으면 진행 중인 턴이 버려진다. 끝날 때까지 두거나 먼저 중단시켜라.",
    "입력대기": "답을 기다리며 멈춰 있다. 닫으면 그 요청은 처리되지 않는다.",
    "도구 중단": "도구 호출이 결과 없이 끊겼다. 열어서 상태를 확인하고 닫아라.",
    "응답 없음": "마지막 요청이 처리되지 않았다. 열어서 다시 보내거나 포기할지 정해라.",
    "내 답 대기": "대화는 남지만 질문은 사라진다. 답을 정했으면 닫아도 된다.",
    "제안만 남음": "제안을 받아들일지 정하지 않았다. 나중에 이어갈 거면 메모를 남겨라.",
    "한 턴": "결과를 확인한 적이 없다. 한 번 훑어보고 닫아라.",
    "일단락": "대화는 마무리됐다.",
    "빈 탭": "쓴 적 없는 탭이다. 잃을 게 없다.",
}


# ---------------------------------------------------------------- 출력

def explain_empty(stats: dict[str, Any], scoped: bool) -> list[str]:
    """0개로 끝난 이유를 댄다. 못 읽은 것과 정말 없는 것은 전혀 다른 얘기다."""
    if not stats["readable"]:
        return [
            f"`{SESSIONS_DIR}` 를 읽을 수 없다 — 탭이 없는 게 아니라 **조회가 막힌 것**이다.",
            "권한이나 샌드박스 설정을 확인한다.",
        ]
    if stats["files"] == 0:
        return [f"`{SESSIONS_DIR}` 가 비어 있다. 이 머신에서 연 탭이 없다."]

    out = ["살아 있는 탭이 없다."]
    detail = [f"세션 파일 {stats['files']}개"]
    if stats["dead"]:
        detail.append(f"죽은 프로세스 {stats['dead']}")
    if stats["other_cwd"]:
        detail.append(f"다른 폴더 {stats['other_cwd']}")
    if stats["unreadable"]:
        detail.append(f"읽기 실패 {stats['unreadable']}")
    out.append(" · ".join(detail))
    if scoped and stats["other_cwd"]:
        out.append("다른 폴더의 탭까지 보려면 `--all` 을 붙인다.")
    if stats["dead"] == stats["files"] and stats["files"] > 1:
        out.append(
            "전부 죽은 것으로 나왔다면 프로세스 조회가 막혔을 수 있다 — 샌드박스를 확인한다."
        )
    return out


def render(
    rows: list[dict[str, Any]], scope: str, now: datetime, self_id: str,
    stats: dict[str, Any],
) -> str:
    stamp = now.strftime("%Y-%m-%d %H:%M KST")
    lines = [f"# 열려 있는 세션 — {scope} ({len(rows)}개)", f"{stamp}", ""]
    if not rows:
        lines.extend(explain_empty(stats, scope != "전체 프로젝트"))
        return "\n".join(lines) + "\n"

    grouped: dict[str, list[dict[str, Any]]] = {g: [] for g in GROUP_ORDER}
    for row in rows:
        grouped[row["close"]].append(row)

    counts = " · ".join(f"{g} {len(grouped[g])}" for g in GROUP_ORDER if grouped[g])
    lines.insert(2, counts)

    for group in GROUP_ORDER:
        bucket = grouped[group]
        if not bucket:
            continue
        lines.append(f"## {group} ({len(bucket)})")
        lines.append("")
        for row in bucket:
            info = row["info"]
            mark = "  ← 지금 이 탭" if row["id"] == self_id else ""
            dupe = f" · 탭 {row['procs']}개" if row["procs"] > 1 else ""
            lines.append(f"### {row['label']} · `{row['short']}`{dupe}{mark}")

            started = row["started"].strftime("%m/%d %H:%M") if row["started"] else "?"
            lines.append(
                f"- 상태: **{row['status']}** — {row['why']}"
            )
            lines.append(
                f"- 활동: 마지막 대화 {ago(info['last_ts'], now)} · 탭 열림 {started} · "
                f"{info['user_turns']}턴 · {row['entrypoint']}"
            )

            branch = f"`{info['branch']}`" if info["branch"] else "—"
            wt = info["worktree"]
            if wt and info["worktree_open"]:
                branch += f" (worktree `{wt['name']}`)"
            lines.append(f"- 위치: {branch} · {row['cwd']}")

            if info["purpose"]:
                lines.append(f"- 목적: {clip(info['purpose'], 150)}")
            elif row["status"] == "빈 탭":
                lines.append("- 목적: —")

            work = []
            top = sorted(info["tools"].items(), key=lambda kv: -kv[1])[:3]
            if top:
                work.append(" · ".join(f"{n}×{c}" for n, c in top))
            if info["files"]:
                names = list(dict.fromkeys(os.path.basename(f) for f in info["files"]))
                more = f" 외 {len(names) - 3}개" if len(names) > 3 else ""
                work.append(f"수정 {', '.join(names[:3])}{more}")
            if info["plan_exits"]:
                work.append(f"플랜 확정 {info['plan_exits']}회")
            lines.append(f"- 한 일: {' · '.join(work) if work else '도구 사용 없음'}")

            if row["status"] not in {"일단락", "빈 탭"} and info["last_user"]:
                lines.append(f"- 마지막 요청: {clip(info['last_user'], 130)}")
            if info["last_assistant"]:
                lines.append(f"- 마지막 답: {clip(info['last_assistant'], 130)}")
            if row["remaining"]:
                lines.append(f"- 남은 것: {' · '.join(row['remaining'])}")
            lines.append(f"- 닫기: {row['advice']}")
            lines.append("")
    return "\n".join(lines).rstrip() + "\n"


# ---------------------------------------------------------------- main

def build(args: argparse.Namespace) -> tuple[list[dict[str, Any]], dict[str, Any]]:
    target = None if args.all else os.path.realpath(args.cwd)
    sessions, stats = live_sessions(target)
    rows: list[dict[str, Any]] = []

    for raw in sessions:
        path = transcript_path(raw)
        info = read_transcript(path) if path else empty_info()
        rows.append({
            "id": raw["sessionId"],
            "short": raw["sessionId"][:8],
            "name": raw.get("name") or raw["sessionId"][:8],
            "label": display_name(raw, info),
            "procs": raw.get("_procs", 1),
            "cwd": raw.get("cwd") or "",
            "entrypoint": raw.get("entrypoint") or raw.get("kind") or "",
            "runtime_status": raw.get("status") or "idle",
            "status_hint": "빈 탭" if not info["user_turns"] and not info["tools"] else "",
            "started": parse_ts(raw.get("startedAt")),
            "updated": parse_ts(raw.get("updatedAt")),
            "info": info,
        })

    probes = [r for r in rows if not args.no_net and r["status_hint"] != "빈 탭"]
    if probes:
        gh = find_gh()

        def probe(row: dict[str, Any]) -> None:
            cwd, branch = row["cwd"], row["info"]["branch"]
            row["unpushed"] = unpushed(cwd, branch)
            row["pr"] = pr_state(gh, cwd, branch, row["info"]["prs"]) if gh else None

        with ThreadPoolExecutor(max_workers=min(8, len(probes))) as pool:
            list(pool.map(probe, probes))

    now = datetime.now(KST)
    for row in rows:
        status, why, level = classify(row)
        remaining, escalate, reasons = riders(row, now)
        advice = ADVICE.get(status, "")
        if escalate and rank(escalate) < rank(level):
            level = escalate
            advice = f"{advice} 다만 {', '.join(reasons)}."
        row.update(
            status=status, why=why, close=level,
            remaining=remaining, advice=advice,
        )

    rows.sort(key=lambda r: (rank(r["close"]), -(r["updated"].timestamp() if r["updated"] else 0)))
    return rows, stats


def main() -> None:
    parser = argparse.ArgumentParser(description="열려 있는 Claude Code 세션 진행 상태")
    parser.add_argument("--all", action="store_true", help="모든 프로젝트의 세션을 본다")
    parser.add_argument("--cwd", default=os.environ.get("CLAUDE_PROJECT_DIR") or os.getcwd())
    parser.add_argument("--no-net", action="store_true", help="git/gh 조회를 건너뛴다")
    parser.add_argument("--json", action="store_true", help="원자료를 JSON 으로 낸다")
    args = parser.parse_args()

    now = datetime.now(KST)
    self_id = os.environ.get("CLAUDE_CODE_SESSION_ID") or ""
    try:
        rows, stats = build(args)
    except Exception as err:  # 읽기 전용 도구라 죽는 것보다 사유를 알리는 편이 낫다
        sys.stderr.write(f"open-sessions: {err}\n")
        sys.exit(1)

    if args.json:
        print(json.dumps(rows, ensure_ascii=False, default=str, indent=2))
        return

    scope = "전체 프로젝트" if args.all else os.path.basename(os.path.realpath(args.cwd))
    sys.stdout.write(render(rows, scope, now, self_id, stats))


if __name__ == "__main__":
    main()
