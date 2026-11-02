#!/usr/bin/env python3
"""Fails the build when localization is incomplete (brief D7):
- every String Catalog entry needs a translated, non-empty value in both ar and en;
- every localization key used in Swift code must exist in a String Catalog.
Keys follow the `area.name` convention (see CLAUDE.md)."""
import json
import pathlib
import re
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
LANGS = ("ar", "en")
KEY_PREFIXES = "common|home|diag|widget|specs|library|detail|editor|mywidgets|tab|settings|guide|compass|tasbeeh|tiles|ai|create|onboarding|keyguide|notice|permissions"
# SF Symbol names (systemImage:/systemName:) look like keys but are icons, not text.
KEY_RE = re.compile(r'(?<!systemImage: )(?<!systemName: )"((?:' + KEY_PREFIXES + r')\.[A-Za-z0-9_.]+)"')
SKIP_DIRS = {"build", ".build", "DerivedData", "WidgetStudio.xcodeproj"}


def skipped(path: pathlib.Path) -> bool:
    return any(part in SKIP_DIRS for part in path.parts)


def string_units(localization: dict):
    if "stringUnit" in localization:
        yield localization["stringUnit"]
    for variation in localization.get("variations", {}).values():
        for case in variation.values():
            yield from string_units(case)


errors: list[str] = []
keys: set[str] = set()

for catalog in sorted(ROOT.rglob("*.xcstrings")):
    if skipped(catalog):
        continue
    rel = catalog.relative_to(ROOT)
    data = json.loads(catalog.read_text(encoding="utf-8"))
    for key, entry in data.get("strings", {}).items():
        keys.add(key)
        if entry.get("shouldTranslate") is False:
            continue
        localizations = entry.get("localizations", {})
        for lang in LANGS:
            if lang not in localizations:
                errors.append(f"{rel}: '{key}' has no {lang} translation")
                continue
            for unit in string_units(localizations[lang]):
                if unit.get("state") != "translated" or not unit.get("value", "").strip():
                    errors.append(f"{rel}: '{key}' [{lang}] is not translated")

for swift in sorted(ROOT.rglob("*.swift")):
    if skipped(swift):
        continue
    for match in KEY_RE.finditer(swift.read_text(encoding="utf-8")):
        if match.group(1) not in keys:
            errors.append(f"{swift.relative_to(ROOT)}: key '{match.group(1)}' is missing from the String Catalogs")

if errors:
    print("Localization check failed:")
    print("\n".join(f"  - {e}" for e in errors))
    sys.exit(1)
print(f"Localization check passed: {len(keys)} keys, all translated in {', '.join(LANGS)}.")
