#!/usr/bin/env python3
"""Create a Simulator APNs payload for testing My Notes notification taps."""

from __future__ import annotations

import argparse
import json
import time
from pathlib import Path

BUNDLE_ID = "dev.asobo.worldnotes"


def main() -> None:
    parser = argparse.ArgumentParser(
        description="Create a World Notes My Notes .apns file for iOS Simulator."
    )
    parser.add_argument("place_id", help="Firestore places/{placeId} document ID.")
    parser.add_argument(
        "-o",
        "--output",
        default="/tmp/world_notes_my_notes.apns",
        help="Output .apns path. Defaults to /tmp/world_notes_my_notes.apns.",
    )
    args = parser.parse_args()

    output = Path(args.output).expanduser()
    payload = {
        "Simulator Target Bundle": BUNDLE_ID,
        "aps": {
            "alert": {
                "title": "World Notes",
                "body": "Your note has a new message.",
            },
            "sound": "default",
            "badge": 1,
        },
        # firebase_messaging only surfaces notification tap events that look
        # like FCM notifications. A plain Simulator APNs payload displays, but
        # will not reach getInitialMessage/onMessageOpenedApp without this key.
        "gcm.message_id": f"sim-my-notes-{int(time.time() * 1000)}",
        "type": "my_note_message",
        "placeId": args.place_id,
    }

    output.parent.mkdir(parents=True, exist_ok=True)
    output.write_text(json.dumps(payload, indent=2) + "\n", encoding="utf-8")
    print(output)
    print(f"xcrun simctl push booted {BUNDLE_ID} {output}")


if __name__ == "__main__":
    main()
