#!/usr/bin/env python3
"""Replace common Unicode characters with ASCII equivalents in repo text files.

Canonical home: the agentstartstack template repo. Host projects consume it via
the .agentstartstack submodule; do not fork a local copy -- fix it here so the
correction flows downstream with the next submodule bump.

REPLACEMENTS keys are written as backslash-u escape sequences on purpose: that keeps this
source file itself ASCII-only, so the sanitizer can never strip the Unicode out
of its own mapping table (which is exactly how earlier copies silently turned
into a no-op). Anything not in the table is left untouched and reported at the
end so a human can decide on an ASCII spelling.
"""

from __future__ import annotations

import os
import re
import sys

SKIP_DIRS = {".git", ".esphome", "__pycache__", "node_modules", ".pio"}
SKIP_BASENAMES = {"ascii-only-sanitize.py"}
SKIP_EXT = {
    ".ttf", ".bin", ".png", ".jpg", ".gif", ".webp", ".ico", ".woff", ".woff2",
    ".pyc", ".o", ".a", ".so", ".elf", ".map",
}

REPLACEMENTS = [
    # -- Dashes and hyphens --
    ("\u2014", "--"),  # em dash
    ("\u2013", "-"),   # en dash
    ("\u2012", "-"),   # figure dash
    ("\u2015", "--"),  # horizontal bar
    ("\u2011", "-"),   # non-breaking hyphen
    ("\u2212", "-"),   # minus sign

    # -- Ellipsis --
    ("\u2026", "..."),  # horizontal ellipsis

    # -- Section / reference marks --
    ("\u00A7", "section"),  # section sign
    ("\u00B6", "para"),     # pilcrow / paragraph sign

    # -- Quotes --
    ("\u2018", "'"),   # left single quote
    ("\u2019", "'"),   # right single quote / apostrophe
    ("\u201C", "\""),  # left double quote
    ("\u201D", "\""),  # right double quote
    ("\u201A", ","),   # single low quote
    ("\u2032", "'"),   # prime
    ("\u2033", "\""),  # double prime

    # -- Arrows --
    ("\u2192", "->"),   # rightwards arrow
    ("\u21D2", "=>"),   # rightwards double arrow
    ("\u2190", "<-"),   # leftwards arrow
    ("\u21D0", "<="),   # leftwards double arrow
    ("\u2191", "^"),    # upwards arrow
    ("\u2193", "v"),    # downwards arrow
    ("\u2194", "<->"),  # left-right arrow

    # -- Comparison and math operators --
    ("\u2265", ">="),  # greater than or equal
    ("\u2264", "<="),  # less than or equal
    ("\u2260", "!="),  # not equal
    ("\u2248", "~="),  # approximately equal
    ("\u00D7", "x"),   # multiplication sign
    ("\u00F7", "/"),   # division sign

    # -- Bullets and middle dots --
    ("\u2022", "-"),  # bullet
    ("\u2023", "-"),  # triangular bullet
    ("\u25E6", "-"),  # white bullet
    ("\u2043", "-"),  # hyphen bullet
    ("\u00B7", "."),  # middle dot
    ("\u2027", "."),  # hyphenation point

    # -- Status marks --
    ("\u2713", "[OK]"),            # check mark
    ("\u2714", "[OK]"),            # heavy check mark
    ("\u2705", "[OK]"),            # white heavy check mark
    ("\u2611", "[OK]"),            # ballot box with check
    ("\u2717", "[FAIL]"),          # ballot x
    ("\u2718", "[FAIL]"),          # heavy ballot x
    ("\u2715", "[FAIL]"),          # multiplication x
    ("\u274C", "[FAIL]"),          # cross mark
    ("\u26A0", "[WARN]"),          # warning sign
    ("\u2139", "[INFO]"),          # information source
    ("\U0001F6A8", "[CRITICAL]"),  # police car light
    ("\u2610", "[TODO]"),          # ballot box

    # -- Box drawing (ASCII-art trees and rules) --
    ("\u2500", "-"),    # light horizontal
    ("\u2550", "="),    # double horizontal
    ("\u2502", "|"),    # light vertical
    ("\u2551", "|"),    # double vertical
    ("\u251C", "|-"),   # light vertical and right
    ("\u2524", "-|"),   # light vertical and left
    ("\u252C", "-+-"),  # light down and horizontal
    ("\u2534", "-+-"),  # light up and horizontal
    ("\u253C", "-+-"),  # light vertical and horizontal
    ("\u250C", "+-"),   # light down and right
    ("\u2510", "-+"),   # light down and left
    ("\u2514", "`-"),   # light up and right
    ("\u2518", "-+"),   # light up and left

    # -- Units and symbols --
    ("\u2126", "Ohm"),   # ohm sign
    ("\u03A9", "Ohm"),   # greek capital omega
    ("\u00B5", "u"),     # micro sign
    ("\u03BC", "u"),     # greek small mu
    ("\u00B0", " deg"),  # degree sign

    # -- Spaces (normalize to plain space) --
    ("\u00A0", " "),  # no-break space
    ("\u2007", " "),  # figure space
    ("\u202F", " "),  # narrow no-break space
    ("\u2009", " "),  # thin space

    # -- Zero-width and invisible (drop) --
    ("\u200B", ""),  # zero width space
    ("\u200C", ""),  # zero width non-joiner
    ("\u200D", ""),  # zero width joiner
    ("\uFEFF", ""),  # byte order mark / zero width no-break space
    ("\uFE0F", ""),  # variation selector-16 (emoji presentation)
]


def sanitize(text: str) -> str:
    for old, new in REPLACEMENTS:
        text = text.replace(old, new)
    return text


def should_process(path: str) -> bool:
    if os.path.basename(path) in SKIP_BASENAMES:
        return False
    if os.path.splitext(path)[1].lower() in SKIP_EXT:
        return False
    return True


def iter_files(root: str):
    for dirpath, dirnames, filenames in os.walk(root):
        dirnames[:] = [d for d in dirnames if d not in SKIP_DIRS]
        for name in filenames:
            path = os.path.join(dirpath, name)
            if should_process(path):
                yield path


def main() -> int:
    root = os.path.abspath(sys.argv[1] if len(sys.argv) > 1 else ".")
    changed = 0
    remaining = []

    for path in iter_files(root):
        try:
            with open(path, encoding="utf-8") as f:
                original = f.read()
        except (UnicodeDecodeError, OSError):
            continue
        if not re.search(r"[^\x00-\x7F]", original):
            continue
        updated = sanitize(original)
        if updated != original:
            with open(path, "w", encoding="utf-8", newline="") as f:
                f.write(updated)
            changed += 1
        if re.search(r"[^\x00-\x7F]", updated):
            remaining.append(path)

    print(f"Updated {changed} file(s)")
    if remaining:
        print(f"Still non-ASCII in {len(remaining)} file(s):")
        for p in remaining[:30]:
            print(f"  {p}")
        return 1
    print("All scanned text files are ASCII-only")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
