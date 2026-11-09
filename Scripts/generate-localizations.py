"""
Wyrm iOS in the player's language (OM, 2026-10-31).

The words and their translations are Wyrm Android's tables
(`Wyrm Android/app/res/i18n/<code>.json`, made by Wyrm Android's
tools/i18n/extract.py, which also reads this app's SourcesShell, and
translate.py). This writes them as iOS string tables:
Resources/Localization/<code>.lproj/Localizable.strings.

SwiftUI looks a `Text("...")` literal up there by itself; the shared design
components look their String titles up through `wyrmLocalized` (WyrmLanguage.swift).
A template "Tag {0} is yours" becomes the keys Swift builds for an
interpolation: "Tag %@ is yours" (a String) and "Tag %lld is yours" (an Int),
each translated with positional arguments (%1$@ / %1$lld), so a language may
put the pieces in another order. Keys holding a bare % are left out.

    python -X utf8 Scripts/generate-localizations.py
"""
import json
import pathlib
import re
import shutil

HERE = pathlib.Path(__file__).resolve().parent
ROOT = HERE.parent
TABLES = ROOT.parent / "Wyrm Android" / "app" / "res" / "i18n"
OUT = ROOT / "Resources" / "Localization"
HOLE = re.compile(r"\{(\d+)\}")


def escape(text: str) -> str:
    return text.replace("\\", "\\\\").replace('"', '\\"').replace("\n", "\\n").replace("\t", "\\t")


def variants(english: str, translated: str):
    """(key, value) pairs for one line of the table."""
    if "%" in english or "%" in translated:
        return []
    holes = HOLE.findall(english)
    if not holes:
        return [(english, translated)]
    out = []
    for spec in ("@", "lld"):
        key = HOLE.sub("%" + spec, english)
        value = HOLE.sub(lambda m: "%" + str(int(m.group(1)) + 1) + "$" + spec, translated)
        out.append((key, value))
    return out


def main():
    languages = json.loads((TABLES / "languages.json").read_text(encoding="utf-8"))
    if OUT.exists():
        shutil.rmtree(OUT)
    total = 0
    for lang in languages:
        code = lang["code"]
        table = json.loads((TABLES / f"{code}.json").read_text(encoding="utf-8"))
        lines = []
        seen = set()
        for english in sorted(table):
            for key, value in variants(english, table[english]):
                if key in seen:
                    continue
                seen.add(key)
                lines.append(f'"{escape(key)}" = "{escape(value)}";')
        folder = OUT / f"{code}.lproj"
        folder.mkdir(parents=True, exist_ok=True)
        # UTF-8 is accepted for .strings resources.
        (folder / "Localizable.strings").write_text("\n".join(lines) + "\n", encoding="utf-8")
        total += len(lines)
    # The language list the app shows (code + its own name), same as Android's.
    (ROOT / "Resources" / "WyrmLanguages.json").write_text(
        json.dumps(languages, ensure_ascii=False, indent=1), encoding="utf-8")
    print(f"{len(languages)} languages, {total} lines")


if __name__ == "__main__":
    main()
