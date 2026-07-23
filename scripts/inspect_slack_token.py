#!/usr/bin/env python3
"""Inspect the identity and channel access of a Slack Web API token."""

from __future__ import annotations

import argparse
import json
import os
import re
import sys
import urllib.error
import urllib.parse
import urllib.request
from dataclasses import dataclass
from typing import Any


API_BASE_URL = "https://slack.com/api"
CHANNEL_TYPES = ("public_channel", "private_channel")
EXPECTED_SCOPES = {
    "public_channel": "channels:read",
    "private_channel": "groups:read",
}


class SlackApiError(Exception):
    """A Slack Web API request failed."""

    def __init__(self, method: str, error: str, needed: str | None = None):
        super().__init__(error)
        self.method = method
        self.error = error
        self.needed = needed


@dataclass
class Inspection:
    identity: dict[str, Any]
    channels: list[dict[str, Any]]
    unavailable_channel_types: list[dict[str, str]]

    def as_dict(self) -> dict[str, Any]:
        member_channels = [channel for channel in self.channels if channel["is_member"]]
        visible_channels = [channel for channel in self.channels if not channel["is_member"]]
        return {
            "identity": self.identity,
            "member_channels": member_channels,
            "visible_not_joined_channels": visible_channels,
            "unavailable_channel_types": self.unavailable_channel_types,
        }


class SlackClient:
    def __init__(self, token: str, timeout: float = 10.0):
        self.token = token
        self.timeout = timeout

    def call(self, method: str, **params: str) -> dict[str, Any]:
        body = urllib.parse.urlencode(params).encode("utf-8")
        request = urllib.request.Request(
            f"{API_BASE_URL}/{method}",
            data=body,
            headers={
                "Authorization": f"Bearer {self.token}",
                "Content-Type": "application/x-www-form-urlencoded; charset=utf-8",
                "User-Agent": "slack-token-inspector/1.0",
            },
            method="POST",
        )

        try:
            with urllib.request.urlopen(request, timeout=self.timeout) as response:
                payload = json.load(response)
        except urllib.error.HTTPError as exc:
            raise SlackApiError(method, f"http_{exc.code}") from exc
        except urllib.error.URLError as exc:
            raise ConnectionError(f"Slack API 연결 실패: {exc.reason}") from exc
        except (json.JSONDecodeError, UnicodeDecodeError) as exc:
            raise SlackApiError(method, "invalid_json_response") from exc

        if not payload.get("ok"):
            raise SlackApiError(
                method,
                payload.get("error", "unknown_error"),
                payload.get("needed"),
            )
        return payload

    def inspect(self, include_archived: bool = False) -> Inspection:
        identity_response = self.call("auth.test")
        identity = {
            key: identity_response[key]
            for key in ("team", "team_id", "user", "user_id", "bot_id", "url")
            if key in identity_response
        }

        channels: list[dict[str, Any]] = []
        unavailable_channel_types: list[dict[str, str]] = []
        for channel_type in CHANNEL_TYPES:
            cursor = ""
            while True:
                try:
                    response = self.call(
                        "conversations.list",
                        types=channel_type,
                        exclude_archived=str(not include_archived).lower(),
                        limit="200",
                        cursor=cursor,
                    )
                except SlackApiError as exc:
                    if exc.error != "missing_scope":
                        raise
                    unavailable_channel_types.append(
                        {
                            "type": channel_type,
                            "needed_scope": EXPECTED_SCOPES[channel_type],
                            "api_needed_scopes": exc.needed or "알 수 없음",
                        }
                    )
                    break
                channels.extend(
                    normalize_channel(channel) for channel in response["channels"]
                )
                cursor = (
                    response.get("response_metadata", {})
                    .get("next_cursor", "")
                    .strip()
                )
                if not cursor:
                    break

        channels.sort(key=lambda channel: (not channel["is_member"], channel["name"]))
        return Inspection(
            identity=identity,
            channels=channels,
            unavailable_channel_types=unavailable_channel_types,
        )


def normalize_channel(channel: dict[str, Any]) -> dict[str, Any]:
    return {
        "id": channel["id"],
        "name": channel.get("name", "(이름 없음)"),
        "is_member": bool(channel.get("is_member")),
        "is_private": bool(channel.get("is_private")),
        "is_archived": bool(channel.get("is_archived")),
        "is_shared": bool(channel.get("is_shared")),
    }


def token_kind(token: str) -> str:
    if token.startswith("xoxb-"):
        return "bot"
    if token.startswith("xoxp-"):
        return "user"
    if token.startswith("xapp-"):
        return "app"
    return "unknown"


def channel_id_from_permalink(permalink: str) -> str | None:
    match = re.search(r"/archives/([CGD][A-Z0-9]+)/", permalink)
    return match.group(1) if match else None


def select_channels(
    channels: list[dict[str, Any]], query: str | None
) -> list[dict[str, Any]]:
    if not query:
        return channels
    normalized = query.removeprefix("#").casefold()
    return [
        channel
        for channel in channels
        if channel["id"].casefold() == normalized
        or channel["name"].casefold() == normalized
    ]


def format_channel(channel: dict[str, Any]) -> str:
    attributes = ["참여 중" if channel["is_member"] else "조회 가능/미참여"]
    attributes.append("비공개" if channel["is_private"] else "공개")
    if channel["is_archived"]:
        attributes.append("보관됨")
    if channel["is_shared"]:
        attributes.append("Slack Connect")
    return f"- #{channel['name']} ({channel['id']}) — {', '.join(attributes)}"


def print_human(inspection: Inspection, query: str | None) -> None:
    identity = inspection.identity
    subject = identity.get("user", identity.get("user_id", "알 수 없음"))
    if identity.get("bot_id"):
        subject += f" (bot_id: {identity['bot_id']})"

    print(f"워크스페이스: {identity.get('team', '알 수 없음')} ({identity.get('team_id', '-')})")
    print(f"토큰 주체: {subject}")
    if identity.get("url"):
        print(f"워크스페이스 URL: {identity['url']}")

    for unavailable in inspection.unavailable_channel_types:
        label = (
            "비공개 채널"
            if unavailable["type"] == "private_channel"
            else "공개 채널"
        )
        print(
            f"경고: {label}은 권한 부족으로 조회하지 못했습니다 "
            f"(필요 scope: {unavailable['needed_scope']}).",
            file=sys.stderr,
        )

    selected = select_channels(inspection.channels, query)
    if query:
        print(f"\n채널 검색: {query}")
        if not selected:
            print("- 현재 토큰으로 조회되지 않습니다.")
            return
        for channel in selected:
            print(format_channel(channel))
        return

    member_channels = [channel for channel in selected if channel["is_member"]]
    visible_channels = [channel for channel in selected if not channel["is_member"]]

    print(f"\n참여 중인 채널 ({len(member_channels)}개)")
    if member_channels:
        for channel in member_channels:
            print(format_channel(channel))
    else:
        print("- 없음")

    print(f"\n조회 가능하지만 참여하지 않은 채널 ({len(visible_channels)}개)")
    if visible_channels:
        for channel in visible_channels:
            print(format_channel(channel))
    else:
        print("- 없음")


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        description="Slack Web API 토큰의 주체와 접근 가능한 채널을 확인합니다."
    )
    parser.add_argument(
        "--token-env",
        default="SLACK_TOKEN",
        help="토큰을 읽을 환경변수 이름 (기본값: SLACK_TOKEN)",
    )
    parser.add_argument(
        "--channel",
        help="특정 채널 이름(#general) 또는 ID(C01234567)만 확인",
    )
    parser.add_argument(
        "--message-link",
        help="Slack 메시지 링크에서 채널 ID만 추출(API 호출 및 토큰 불필요)",
    )
    parser.add_argument(
        "--include-archived",
        action="store_true",
        help="보관된 채널도 포함",
    )
    parser.add_argument("--json", action="store_true", help="JSON으로 출력")
    parser.add_argument("--timeout", type=float, default=10.0, help="API 제한 시간(초)")
    return parser


def main(argv: list[str] | None = None) -> int:
    args = build_parser().parse_args(argv)
    if args.message_link:
        channel_id = channel_id_from_permalink(args.message_link)
        if not channel_id:
            print(
                "오류: Slack 메시지 링크에서 채널 ID를 찾지 못했습니다. "
                "메시지 메뉴의 '링크 복사'로 얻은 URL인지 확인하세요.",
                file=sys.stderr,
            )
            return 2
        if args.json:
            print(json.dumps({"channel_id": channel_id}, ensure_ascii=False))
        else:
            print(f"채널 ID: {channel_id}")
        return 0

    token = os.environ.get(args.token_env, "").strip()
    if not token:
        print(
            f"오류: {args.token_env} 환경변수에 Slack 토큰을 설정하세요.",
            file=sys.stderr,
        )
        return 2

    kind = token_kind(token)
    if kind == "app":
        print(
            "오류: xapp- 앱 레벨 토큰은 채널 조회용 Web API 토큰이 아닙니다. "
            "xoxb- 봇 토큰 또는 xoxp- 사용자 토큰을 사용하세요.",
            file=sys.stderr,
        )
        return 2
    if kind == "unknown":
        print(
            "경고: 일반적인 xoxb-/xoxp- 토큰 형식이 아닙니다. "
            "Incoming Webhook URL은 이 도구로 역조회할 수 없습니다.",
            file=sys.stderr,
        )

    try:
        inspection = SlackClient(token, timeout=args.timeout).inspect(
            include_archived=args.include_archived
        )
    except SlackApiError as exc:
        print(f"Slack API 오류 ({exc.method}): {exc.error}", file=sys.stderr)
        return 1
    except ConnectionError as exc:
        print(str(exc), file=sys.stderr)
        return 1

    if args.json:
        result = inspection.as_dict()
        if args.channel:
            result["matched_channels"] = select_channels(
                inspection.channels, args.channel
            )
        print(json.dumps(result, ensure_ascii=False, indent=2))
    else:
        print_human(inspection, args.channel)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
