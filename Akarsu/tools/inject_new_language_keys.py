#!/usr/bin/env python3
"""Insert new language.option.* keys and update language.picker.footer (en + zh-Hans)."""
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
P = ROOT / "bbb" / "Localizable.xcstrings"

def unit(en: str, zh: str) -> dict:
    return {
        "extractionState": "manual",
        "localizations": {
            "en": {"stringUnit": {"state": "translated", "value": en}},
            "zh-Hans": {"stringUnit": {"state": "translated", "value": zh}},
        },
    }

data = json.loads(P.read_text(encoding="utf-8"))
s = data["strings"]

new = {
    "language.option.portuguese": unit("Portuguese", "葡萄牙语"),
    "language.option.portuguese.subtitle": unit(
        "Always use Portuguese in this app", "本应用始终使用葡萄牙语界面"
    ),
    "language.option.spanish": unit("Spanish", "西班牙语"),
    "language.option.spanish.subtitle": unit(
        "Always use Spanish in this app", "本应用始终使用西班牙语界面"
    ),
    "language.option.japanese": unit("Japanese", "日语"),
    "language.option.japanese.subtitle": unit(
        "Always use Japanese in this app", "本应用始终使用日语界面"
    ),
    "language.option.french": unit("French", "法语"),
    "language.option.french.subtitle": unit(
        "Always use French in this app", "本应用始终使用法语界面"
    ),
    "language.option.german": unit("German", "德语"),
    "language.option.german.subtitle": unit(
        "Always use German in this app", "本应用始终使用德语界面"
    ),
}
for k, v in new.items():
    s[k] = v

s["language.picker.footer"]["localizations"]["en"]["stringUnit"]["value"] = (
    'App interface language. "Follow system" matches iOS Settings → General → Language & Region. '
    "Selected languages apply only inside this app."
)
s["language.picker.footer"]["localizations"]["zh-Hans"]["stringUnit"]["value"] = (
    "仅影响本应用界面语言。「跟随系统」与 iOS 设置 → 通用 → 语言与地区 一致；"
    "任选语言仅在本应用内生效。"
)

P.write_text(json.dumps(data, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
print("OK", P)
