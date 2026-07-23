import io
import json
import unittest
from unittest.mock import patch

import inspect_slack_token as inspector


class FakeResponse:
    def __init__(self, payload):
        self.body = io.StringIO(json.dumps(payload))

    def __enter__(self):
        return self.body

    def __exit__(self, exc_type, exc, traceback):
        return False


class SlackTokenInspectorTest(unittest.TestCase):
    def test_inspect_paginates_and_sorts_members_first(self):
        responses = [
            {
                "ok": True,
                "team": "Example",
                "team_id": "T1",
                "user": "inspector",
                "user_id": "U1",
                "bot_id": "B1",
            },
            {
                "ok": True,
                "channels": [
                    {
                        "id": "C2",
                        "name": "public-not-joined",
                        "is_member": False,
                        "is_private": False,
                    }
                ],
                "response_metadata": {"next_cursor": "next"},
            },
            {
                "ok": True,
                "channels": [
                    {
                        "id": "C1",
                        "name": "private-joined",
                        "is_member": True,
                        "is_private": True,
                    }
                ],
                "response_metadata": {"next_cursor": ""},
            },
            {
                "ok": False,
                "error": "missing_scope",
                "needed": "groups:read",
            },
        ]

        with patch("urllib.request.urlopen", side_effect=map(FakeResponse, responses)):
            result = inspector.SlackClient("xoxb-test").inspect()

        self.assertEqual(result.identity["bot_id"], "B1")
        self.assertEqual([channel["id"] for channel in result.channels], ["C1", "C2"])
        self.assertEqual(
            result.unavailable_channel_types,
            [
                {
                    "type": "private_channel",
                    "needed_scope": "groups:read",
                    "api_needed_scopes": "groups:read",
                }
            ],
        )

    def test_select_channel_accepts_hash_name_and_id(self):
        channels = [
            {
                "id": "C123",
                "name": "General",
                "is_member": True,
                "is_private": False,
            }
        ]
        self.assertEqual(inspector.select_channels(channels, "#general"), channels)
        self.assertEqual(inspector.select_channels(channels, "c123"), channels)

    def test_extract_channel_id_from_message_permalink(self):
        permalink = (
            "https://example.slack.com/archives/C012ABC34/"
            "p1784786400000000?thread_ts=1784780000.000000"
        )
        self.assertEqual(
            inspector.channel_id_from_permalink(permalink),
            "C012ABC34",
        )
        self.assertIsNone(
            inspector.channel_id_from_permalink("https://example.slack.com/")
        )

    def test_api_error_preserves_missing_scope(self):
        response = FakeResponse(
            {"ok": False, "error": "missing_scope", "needed": "groups:read"}
        )
        with patch("urllib.request.urlopen", return_value=response):
            with self.assertRaises(inspector.SlackApiError) as raised:
                inspector.SlackClient("xoxb-test").call("conversations.list")

        self.assertEqual(raised.exception.needed, "groups:read")


if __name__ == "__main__":
    unittest.main()
