#!/usr/bin/env python3
"""Claude Code 세션을 목적·완료 여부 표로 정리한다.

Stop 훅이 매 턴 갱신하므로 탭을 그냥 닫아도 마지막 답 시점의 상태가 남는다.
SessionStart 는 죽은 세션을 백필하고, 미완만 다음 탭 컨텍스트에 넣는다.
"""

from __future__ import annotations

import json
import os
import re
import sys
from datetime import datetime, timedelta, timezone
from pathlib import Path
from typing import Any

KST = timezone(timedelta(hours=9))
HOME = Path.home()
SESSIONS_DIR = HOME / ".claude" / "sessions"
PROJECTS_DIR = HOME / ".claude" / "projects"

IDE_BLOCK = re.compile(r"<ide_[^>]+>.*?</ide_[^>]+>", re.S)
TAG = re.compile(r"<[^>]+>")
WS = re.compile(r"\s+")

DONE_USER = re.compile(
    r"(적용했다|적용했어|포스 푸시|푸시했다|푸시 했다|머지했다|배포했다|됐다|됐어|고마워|감사합니다|\blgtm\b|\bdone\b)",
    re.I,
)
DONE_ASSISTANT = re.compile(
    r"(^|\n)##?\s*완료|완료\s*[—–-]|완료했습니다|운영이 dev 와 일치",
    re.I,
)
ASK_AGAIN = re.compile(
    r"(할까\?|할까요\?|말해달라|알려줄래|진행할까|원하면 말해|말해 주세요)",
)
PROPOSE_FIX = re.compile(
    r"(고치면|수정할까|워크플로를 실제로|원하면 적용|남은 리스크|정리가 필요하면)",
)
NOISE_USER = re.compile(
    r"^(Caveat:|/extra-usage\b|/usage\b|/compact\b|/context\b)",
    re.I,
)


def fail_open(err: BaseException) -> None:
    sys.stderr.write(f"session-recap: {err}\n")
    sys.exit(0)


def read_payload() -> dict[str, Any]:
    raw = sys.stdin.read() if not sys.stdin.isatty() else ""
    if not raw.strip():
        return {}
    try:
        data = json.loads(raw)
        return data if isinstance(data, dict) else {}
    except json.JSONDecodeError:
        return {}


def parse_ts(value: Any) -> datetime | None:
    if value is None:
        return None
    if isinstance(value, (int, float)):
        ts = value / 1000 if value > 1e12 else value
        return datetime.fromtimestamp(ts, KST)
    if isinstance(value, str):
        try:
            return datetime.fromisoformat(value.replace("Z", "+00:00")).astimezone(KST)
        except ValueError:
            return None
    return None


def extract_text(content: Any) -> str:
    if isinstance(content, str):
        return content
    if isinstance(content, list):
        parts: list[str] = []
        for item in content:
            if isinstance(item, str):
                parts.append(item)
            elif isinstance(item, dict) and item.get("type") == "text":
                parts.append(item.get("text") or "")
        return "\n".join(parts)
    return ""


def clean_user(text: str) -> str:
    text = IDE_BLOCK.sub("", text)
    text = TAG.sub("", text)
    return WS.sub(" ", text).strip()


def is_tool_result(content: Any) -> bool:
    if isinstance(content, list):
        return any(isinstance(c, dict) and c.get("type") == "tool_result" for c in content)
    return False


def project_slug(path: str) -> str:
    return os.path.abspath(path).replace("/", "-")


def resolve_transcripts_dirs(payload: dict[str, Any], cwd: str) -> list[Path]:
    """transcript_path 의 부모와 cwd slug 디렉터리를 둘 다 본다.

    둘이 다를 수 있다(리줌·워크트리·새 탭). 한쪽만 보면 목록이 비어
    기존 파일을 덮어쓰게 되므로 후보를 모두 모아 합친다.
    """
    dirs: list[Path] = []
    transcript = payload.get("transcript_path")
    if isinstance(transcript, str) and transcript:
        parent = Path(transcript).expanduser().parent
        if parent.is_dir():
            dirs.append(parent)
    candidate = PROJECTS_DIR / project_slug(cwd)
    if candidate.is_dir() and candidate not in dirs:
        dirs.append(candidate)
    return dirs


def pid_alive(pid: int) -> bool:
    if pid <= 0:
        return False
    try:
        os.kill(pid, 0)
        return True
    except OSError:
        return False


def live_session_ids() -> set[str]:
    live: set[str] = set()
    if not SESSIONS_DIR.is_dir():
        return live
    for path in SESSIONS_DIR.glob("*.json"):
        try:
            data = json.loads(path.read_text(encoding="utf-8"))
        except (OSError, json.JSONDecodeError):
            continue
        sid = data.get("sessionId")
        pid = data.get("pid")
        if isinstance(sid, str) and isinstance(pid, int) and pid_alive(pid):
            live.add(sid)
    return live


def local_gitignored(project_dir: Path) -> bool:
    gitignore = project_dir / ".gitignore"
    if not gitignore.is_file():
        return False
    try:
        text = gitignore.read_text(encoding="utf-8")
    except OSError:
        return False
    for line in text.splitlines():
        stripped = line.strip()
        if stripped in {"local", "local/", "/local", "/local/"}:
            return True
    return False


def recap_paths(project_dir: Path, transcripts_dir: Path) -> list[Path]:
    paths: list[Path] = []
    if (project_dir / "local").is_dir() or local_gitignored(project_dir):
        paths.append(project_dir / "local" / "claude-sessions.md")
    paths.append(transcripts_dir / "session-recap.md")
    return paths


READ_ERROR = object()


def parse_session(path: Path) -> Any:
    sid = path.stem
    title = ""
    branch = ""
    cwd = ""
    first_ts: datetime | None = None
    last_ts: datetime | None = None
    users: list[str] = []
    last_assistant = ""
    prs: list[str] = []

    try:
        with path.open(encoding="utf-8") as handle:
            for line in handle:
                line = line.strip()
                if not line:
                    continue
                try:
                    obj = json.loads(line)
                except json.JSONDecodeError:
                    continue
                ts = parse_ts(obj.get("timestamp"))
                if ts:
                    first_ts = first_ts or ts
                    last_ts = ts
                if obj.get("gitBranch"):
                    branch = str(obj.get("gitBranch"))
                if obj.get("cwd"):
                    cwd = str(obj.get("cwd"))
                kind = obj.get("type")
                if kind == "ai-title" and obj.get("aiTitle"):
                    title = str(obj["aiTitle"])
                elif kind == "pr-link":
                    num = obj.get("prNumber")
                    if num is not None:
                        prs.append(str(num))
                elif kind == "user":
                    if obj.get("isMeta"):
                        continue
                    message = obj.get("message") or {}
                    content = message.get("content")
                    if is_tool_result(content):
                        continue
                    text = clean_user(extract_text(content))
                    if not text or NOISE_USER.search(text):
                        continue
                    users.append(text)
                elif kind == "assistant":
                    message = obj.get("message") or {}
                    text = extract_text(message.get("content"))
                    if text:
                        last_assistant = text
    except OSError:
        return READ_ERROR

    if not users:
        return None

    purpose = users[0]
    last_user = users[-1]
    return {
        "id": sid,
        "short": sid[:8],
        "title": title or purpose[:80],
        "branch": branch,
        "cwd": cwd,
        "first_ts": first_ts,
        "last_ts": last_ts,
        "purpose": purpose,
        "last_user": last_user,
        "last_assistant": last_assistant,
        "prs": list(dict.fromkeys(prs)),
        "user_turns": len(users),
        "mtime": datetime.fromtimestamp(path.stat().st_mtime, KST),
    }


def classify(session: dict[str, Any], live: set[str]) -> tuple[str, str]:
    last_user = session["last_user"]
    last_assistant = session["last_assistant"]
    asked = bool(ASK_AGAIN.search(last_assistant[-1200:]))
    proposed = bool(PROPOSE_FIX.search(last_assistant[-1200:]))
    user_done = bool(DONE_USER.search(last_user))
    asst_done = bool(DONE_ASSISTANT.search(last_assistant))

    if session["id"] in live:
        if user_done or (asst_done and not asked):
            return "완료", "라이브 세션이지만 완료 신호가 있다"
        return "진행중", "탭이 아직 열려 있다"

    if user_done and not asked:
        return "완료", f"사용자: {clip(last_user, 80)}"
    if asst_done and not asked:
        return "완료", "마지막 답에 완료 표시"
    if asked and (proposed or session["user_turns"] > 1):
        return "부분", "작업은 있었고 마지막이 후속 질문"
    if asked:
        return "미완", "마지막 답이 질문으로 끝남"
    if proposed:
        return "부분", "다음 조치 제안만 있고 적용은 안 됨"
    if session["user_turns"] >= 2:
        return "완료", "후속 질문 없이 끝남"
    return "부분", "한 턴으로 끝남 — 후속 미확인"


def clip(text: str, n: int) -> str:
    text = WS.sub(" ", text).strip()
    return text if len(text) <= n else text[: n - 1] + "…"


def fmt_range(first: datetime | None, last: datetime | None) -> str:
    if not first:
        return "시간 없음"
    left = first.strftime("%m/%d %H:%M")
    if not last or last == first:
        return left
    if first.date() == last.date():
        return f"{left}–{last.strftime('%H:%M')}"
    return f"{left}–{last.strftime('%m/%d %H:%M')}"


STATUS_ORDER = {"진행중": 0, "미완": 1, "부분": 2, "완료": 3}
STATUS_LABEL = {
    "진행중": "진행중",
    "미완": "미완",
    "부분": "부분",
    "완료": "완료",
}


def render(project_name: str, sessions: list[dict[str, Any]]) -> str:
    now = datetime.now(KST).strftime("%Y-%m-%d %H:%M KST")
    lines = [
        f"# Claude sessions — {project_name}",
        f"갱신: {now}",
        "탭을 닫아도 마지막 답 시점 상태가 유지된다. `/sessions` 로 다시 그릴 수 있다.",
    ]
    by_status: dict[str, list[dict[str, Any]]] = {key: [] for key in STATUS_ORDER}
    for session in sessions:
        by_status[session["status"]].append(session)

    for status in STATUS_ORDER:
        rows = by_status[status]
        if not rows:
            continue
        lines.append(f"## {STATUS_LABEL[status]}")
        for session in rows:
            pr = f" · PR #{', #'.join(session['prs'])}" if session["prs"] else ""
            branch = f"`{session['branch']}`" if session["branch"] else "—"
            lines.append(f"### {session['title']}")
            lines.append(
                f"- id `{session['short']}` · {fmt_range(session['first_ts'], session['last_ts'])} · {branch}{pr}"
            )
            lines.append(f"- 목적: {clip(session['purpose'], 180)}")
            lines.append(f"- 판정: **{session['status']}** — {session['evidence']}")
            if session["status"] != "완료":
                lines.append(f"- 마지막 요청: {clip(session['last_user'], 140)}")
    if not sessions:
        lines.append("기록된 세션이 없다.")
    return "\n".join(lines) + "\n"


def collect(
    transcripts_dirs: list[Path], live: set[str]
) -> tuple[list[dict[str, Any]], int, int]:
    """(세션 목록, 훑은 jsonl 수, 읽기 실패 수)."""
    by_id: dict[str, dict[str, Any]] = {}
    scanned = 0
    failed = 0
    for transcripts_dir in transcripts_dirs:
        for path in transcripts_dir.glob("*.jsonl"):
            scanned += 1
            parsed = parse_session(path)
            if parsed is READ_ERROR:
                failed += 1
                continue
            if not parsed:
                continue
            status, evidence = classify(parsed, live)
            parsed["status"] = status
            parsed["evidence"] = evidence
            prev = by_id.get(parsed["id"])
            if prev and (prev["last_ts"] or prev["mtime"]) >= (
                parsed["last_ts"] or parsed["mtime"]
            ):
                continue
            by_id[parsed["id"]] = parsed
    sessions = sorted(
        by_id.values(), key=lambda item: item["last_ts"] or item["mtime"], reverse=True
    )
    return sessions, scanned, failed


def write_recap(paths: list[Path], markdown: str) -> list[Path]:
    written: list[Path] = []
    for path in paths:
        try:
            path.parent.mkdir(parents=True, exist_ok=True)
            tmp = path.with_suffix(path.suffix + ".tmp")
            tmp.write_text(markdown, encoding="utf-8")
            tmp.replace(path)
            written.append(path)
        except OSError as err:
            sys.stderr.write(f"session-recap: skip {path}: {err}\n")
    return written


def unfinished_context(sessions: list[dict[str, Any]], recap_file: str) -> str:
    open_ones = [s for s in sessions if s["status"] in {"진행중", "미완", "부분"}]
    if not open_ones:
        return ""
    lines = [
        "이 프로젝트의 이전 Claude Code 세션 중 아직 안 끝난 것이 있다.",
        "사용자가 묻기 전에 나열하지 말고, 관련 작업이 이어지면 이 맥락을 써라.",
        f"전체 목록: {recap_file}",
        "",
    ]
    for session in open_ones[:8]:
        lines.append(
            f"- [{session['status']}] {clip(session['title'], 80)} — {clip(session['purpose'], 120)}"
        )
    return "\n".join(lines)


def emit_json(payload: dict[str, Any]) -> None:
    sys.stdout.write(json.dumps(payload, ensure_ascii=False))


def resolve_cwd(payload: dict[str, Any]) -> str:
    env = os.environ.get("CLAUDE_PROJECT_DIR")
    if env:
        return env
    cwd = payload.get("cwd")
    if isinstance(cwd, str) and cwd:
        return cwd
    return os.getcwd()


def main() -> None:
    mode = sys.argv[1] if len(sys.argv) > 1 else "print"
    payload = read_payload()
    cwd = resolve_cwd(payload)
    project_dir = Path(cwd)
    transcripts_dirs = resolve_transcripts_dirs(payload, cwd)
    if not transcripts_dirs:
        if mode in {"start", "stop", "end"}:
            emit_json({"continue": True, "suppressOutput": True})
        else:
            sys.stdout.write("이 경로에 Claude Code 세션 기록이 없다.\n")
        return

    live = live_session_ids()
    sessions, scanned, failed = collect(transcripts_dirs, live)
    markdown = render(project_dir.name, sessions)
    # session-recap.md 는 cwd slug 디렉터리가 정본이다. 없을 때만 다른 후보를 쓴다.
    slug_dir = PROJECTS_DIR / project_slug(cwd)
    paths = recap_paths(
        project_dir, slug_dir if slug_dir in transcripts_dirs else transcripts_dirs[0]
    )

    # 목록이 비었거나 읽기 실패가 성공보다 많은 회차는 신뢰할 수 없다.
    # 이럴 때 덮어쓰면 기존 기록이 "기록된 세션이 없다" 한 줄로 초기화된다.
    trustworthy = bool(sessions) and failed < len(sessions)
    existing = [path for path in paths if path.exists()]
    if trustworthy or not existing:
        written = write_recap(paths, markdown)
    else:
        written = []
        sys.stderr.write(
            f"session-recap: keep existing recap "
            f"(sessions={len(sessions)} scanned={scanned} unreadable={failed})\n"
        )
    recap_file = str((written or existing or paths)[0])

    if mode == "print":
        sys.stdout.write(markdown)
        if not trustworthy and existing:
            sys.stdout.write("\n(신뢰할 수 없는 회차라 파일은 그대로 두었다.)\n")
        sys.stdout.write(f"\n파일: {recap_file}\n")
        return

    if mode == "start":
        context = unfinished_context(sessions, recap_file)
        output: dict[str, Any] = {"continue": True, "suppressOutput": True}
        if context:
            output["hookSpecificOutput"] = {
                "hookEventName": "SessionStart",
                "additionalContext": context,
            }
        emit_json(output)
        return

    emit_json({"continue": True, "suppressOutput": True})


if __name__ == "__main__":
    try:
        main()
    except Exception as err:  # noqa: BLE001 — hook must never block Claude
        fail_open(err)
