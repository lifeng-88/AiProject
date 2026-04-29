#!/usr/bin/env python3
"""Fill pt, es, ja, fr, de in Localizable.xcstrings from English (cached per unique EN text)."""
import json
import sys
from concurrent.futures import ThreadPoolExecutor, as_completed
from pathlib import Path

try:
    from deep_translator import GoogleTranslator
except ImportError:
    print("pip install deep-translator", file=sys.stderr)
    sys.exit(1)

TARGET_LANGS = ("pt", "es", "ja", "fr", "de")
GOOGLE_TARGETS = {
    "pt": "pt",
    "es": "es",
    "ja": "ja",
    "fr": "fr",
    "de": "de",
}

# Reuse one translator per target (avoids repeated setup)
_TRANSLATORS = {
    lang: GoogleTranslator(source="en", target=gt) for lang, gt in GOOGLE_TARGETS.items()
}


def translate_one(lang: str, text: str) -> tuple[str, str]:
    try:
        return lang, _TRANSLATORS[lang].translate(text)
    except Exception as e:
        print(f"WARN {lang!r} {text[:50]!r}: {e}", file=sys.stderr)
        return lang, text


def translate_all(text: str) -> dict[str, str]:
    if not text.strip():
        return {lang: text for lang in TARGET_LANGS}
    out: dict[str, str] = {}
    with ThreadPoolExecutor(max_workers=5) as pool:
        futures = [pool.submit(translate_one, lang, text) for lang in TARGET_LANGS]
        for fut in as_completed(futures):
            lang, val = fut.result()
            out[lang] = val
    return out


def main() -> None:
    root = Path(__file__).resolve().parents[1]
    path = root / "bbb" / "Localizable.xcstrings"
    data = json.loads(path.read_text(encoding="utf-8"))
    strings = data["strings"]

    # Collect unique English values that need any missing lang
    unique_en: set[str] = set()
    for entry in strings.values():
        loc = entry.get("localizations")
        if not loc or "en" not in loc:
            continue
        en_unit = loc["en"].get("stringUnit") or {}
        en_val = en_unit.get("value")
        if en_val is None:
            continue
        missing = any(lang not in loc for lang in TARGET_LANGS)
        if missing:
            unique_en.add(en_val)

    print(f"Unique English strings to translate: {len(unique_en)}", flush=True)
    cache: dict[str, dict[str, str]] = {}
    for i, text in enumerate(sorted(unique_en, key=len), 1):
        cache[text] = translate_all(text)
        if i % 20 == 0:
            print(f"  ... {i}/{len(unique_en)}", flush=True)

    updated = 0
    for key, entry in strings.items():
        loc = entry.get("localizations")
        if not loc or "en" not in loc:
            continue
        en_unit = loc["en"].get("stringUnit") or {}
        en_val = en_unit.get("value")
        if en_val is None:
            continue
        trans = cache.get(en_val)
        if trans is None:
            continue
        changed = False
        for lang in TARGET_LANGS:
            if lang in loc:
                continue
            loc[lang] = {
                "stringUnit": {
                    "state": "translated",
                    "value": trans[lang],
                }
            }
            changed = True
        if changed:
            updated += 1

    path.write_text(json.dumps(data, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(f"Done. Updated {updated} string entries.")


if __name__ == "__main__":
    main()
