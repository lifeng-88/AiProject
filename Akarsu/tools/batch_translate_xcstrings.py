#!/usr/bin/env python3
"""Fill pt/es/ja/fr/de in Localizable.xcstrings from English via Google Translate."""
import json
import re
import socket
import time
from pathlib import Path
from typing import List, Optional, Tuple

from deep_translator import GoogleTranslator

ROOT = Path(__file__).resolve().parents[1]
XCSTRINGS = ROOT / "bbb" / "Localizable.xcstrings"
CACHE = ROOT / "tools" / ".translate_cache.json"

LANGS = ("pt", "es", "ja", "fr", "de")
TARGET = {"pt": "pt", "es": "es", "ja": "ja", "fr": "fr", "de": "de"}

socket.setdefaulttimeout(25)


def placeholders(s: str) -> List[str]:
    return re.findall(r"%lld|%@|%%", s)


def shield_format_tokens(s: str) -> Tuple[str, List[str]]:
    """Replace printf-style tokens so translators do not corrupt them."""
    parts: List[str] = []

    def repl(m: re.Match) -> str:
        parts.append(m.group(0))
        return f"⟦{len(parts) - 1}⟧"

    out = re.sub(r"%lld|%@|%%", repl, s)
    return out, parts


def unshield_format_tokens(s: str, parts: List[str]) -> str:
    for i, tok in enumerate(parts):
        s = s.replace(f"⟦{i}⟧", tok)
    return s


def translate_preserve(text: str, target: str) -> str:
    if not text:
        return text
    shielded, parts = shield_format_tokens(text)
    t = GoogleTranslator(source="en", target=TARGET[target])
    last_err: Optional[Exception] = None
    for attempt in range(4):
        try:
            out = t.translate(shielded)
            out = unshield_format_tokens(out, parts)
            if placeholders(text) and placeholders(out) != placeholders(text):
                print("WARN ph:", repr(text)[:100], "->", repr(out)[:100])
            return out
        except Exception as e:
            last_err = e
            time.sleep(1.5 * (attempt + 1))
    raise last_err  # type: ignore[misc]


def main() -> None:
    cache: dict[str, dict[str, str]] = {}
    if CACHE.exists():
        cache = json.loads(CACHE.read_text(encoding="utf-8"))

    data = json.loads(XCSTRINGS.read_text(encoding="utf-8"))
    strings = data["strings"]

    uniq: dict[str, None] = {}
    for v in strings.values():
        if not isinstance(v, dict) or "localizations" not in v:
            continue
        locs = v["localizations"]
        en = locs.get("en", {}).get("stringUnit", {}).get("value")
        if en:
            uniq[en] = None

    ordered = sorted(uniq.keys(), key=lambda s: (len(s), s))
    for i, en in enumerate(ordered):
        if en not in cache:
            cache[en] = {}
        need = any(not cache[en].get(lang) for lang in LANGS)
        if not need:
            continue
        for lang in LANGS:
            if cache[en].get(lang):
                continue
            cache[en][lang] = translate_preserve(en, lang)
            time.sleep(0.15)
        if (i + 1) % 10 == 0:
            CACHE.write_text(json.dumps(cache, ensure_ascii=False, indent=2), encoding="utf-8")
            print(f"… {i + 1}/{len(ordered)}")

    CACHE.write_text(json.dumps(cache, ensure_ascii=False, indent=2), encoding="utf-8")

    for _, v in strings.items():
        if not isinstance(v, dict) or "localizations" not in v:
            continue
        locs = v["localizations"]
        en = locs.get("en", {}).get("stringUnit", {}).get("value")
        if not en or en not in cache:
            continue
        for lang in LANGS:
            val = cache[en].get(lang)
            if not val:
                continue
            locs[lang] = {"stringUnit": {"state": "translated", "value": val}}

    XCSTRINGS.write_text(json.dumps(data, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print("Wrote", XCSTRINGS)


if __name__ == "__main__":
    main()
