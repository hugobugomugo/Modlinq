#!/usr/bin/env python3
"""Fetches the Deadlock hero portraits into assets/characters_deadlock/.

Valve ships hero art as compiled textures inside the game VPKs, so the icons
come from the community asset API instead, which serves the same PNGs Valve
uses in the hero picker.

The source card is 280x380 with a transparent background. Cards in the app are
square and draw with BoxFit.cover, so the portrait is cropped to its top square
and resized to 256 - the framing the ZZZ and NTE rosters already use.

Run from mod_manager_flutter/:

    python3 scripts/fetch_deadlock_icons.py

Needs Pillow. Only writes files whose hero is on the roster in
lib/utils/deadlock_characters.dart; a hero added there later is picked up on
the next run.
"""

import io
import json
import re
import sys
import urllib.request
from pathlib import Path

from PIL import Image

HEROES_URL = "https://api.deadlock-api.com/v1/assets/heroes"
# The API and its asset bucket answer 403 to urllib's default agent.
USER_AGENT = "modlinq-icon-fetch"
OUT_DIR = Path("assets/characters_deadlock")
ROSTER_FILE = Path("lib/utils/deadlock_characters.dart")
SIZE = 256

# Roster ids whose slug does not match the API's hero name.
ALIASES = {
    "doorman": "the_doorman",
    "ratking": "rat_king",
}


def slug(value: str) -> str:
    return re.sub(r"[^a-z0-9]+", "_", value.lower()).strip("_")


def roster_ids() -> list[str]:
    """The ids listed in deadlockCharactersData, in roster order."""
    source = ROSTER_FILE.read_text(encoding="utf-8")
    block = source.split("deadlockCharactersData = [", 1)[1].split("];", 1)[0]
    return re.findall(r"CharacterData\(id: '([^']+)'", block)


def get(url: str) -> bytes:
    request = urllib.request.Request(url, headers={"User-Agent": USER_AGENT})
    with urllib.request.urlopen(request, timeout=60) as response:
        return response.read()


def fetch_heroes() -> dict[str, dict]:
    heroes = json.loads(get(HEROES_URL))
    return {slug(hero["name"]): hero for hero in heroes}


def portrait(url: str, *, crop: bool) -> Image.Image:
    """The art at [url] as a square [SIZE] icon with its alpha kept.

    A hero card is cropped to its top square, which lands the head where the
    other rosters put it. The fallback art is a narrow 120x200 strip, so that
    one is fitted whole into the square instead - cropping it square would be
    a blurry close-up of a nose.
    """
    art = Image.open(io.BytesIO(get(url))).convert("RGBA")

    if crop:
        side = min(art.width, art.height)
        return art.crop((0, 0, side, side)).resize((SIZE, SIZE), Image.LANCZOS)

    art.thumbnail((SIZE, SIZE), Image.LANCZOS)
    square = Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 0))
    square.paste(art, ((SIZE - art.width) // 2, (SIZE - art.height) // 2))
    return square


def main() -> int:
    if not ROSTER_FILE.exists():
        print(f"run me from mod_manager_flutter/: no {ROSTER_FILE}", file=sys.stderr)
        return 1

    heroes = fetch_heroes()
    OUT_DIR.mkdir(parents=True, exist_ok=True)

    missing = []
    for character_id in roster_ids():
        hero = heroes.get(ALIASES.get(character_id, character_id))
        images = (hero or {}).get("images", {})

        # Heroes Valve has not shipped yet carry no hero card, only the small
        # vertical strip from the top bar.
        url = images.get("icon_hero_card")
        fallback = url is None and images.get("top_bar_vertical_image")
        if not url and not fallback:
            missing.append(character_id)
            continue

        icon = portrait(url or fallback, crop=url is not None)
        # WebP behind a .png name, which is what the ZZZ roster already ships:
        # Flutter goes by content, and the folder stays a quarter of the size.
        icon.save(OUT_DIR / f"{character_id}.png", "WEBP", quality=92, method=6)
        print(f"  {character_id}{' (no hero card yet)' if fallback else ''}")

    if missing:
        print(f"no hero card for: {', '.join(missing)}", file=sys.stderr)
        return 1

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
