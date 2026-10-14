"""Rain/update persistence and coordinate contracts; native Swift fixtures on CI."""
from pathlib import Path
import subprocess
import sys
import tempfile

ROOT = Path(__file__).resolve().parents[1]
S = ROOT / "SourcesShell"
rain = (S / "WyrmRain.swift").read_text(encoding="utf-8")
page = (S / "WyrmRainPage.swift").read_text(encoding="utf-8")
sync = (S / "WyrmAccountSync.swift").read_text(encoding="utf-8")
perf = (S / "WyrmPerformance.swift").read_text(encoding="utf-8")
main = (ROOT / "SourcesOriginal/Main.m").read_text(encoding="utf-8")
engine = ROOT / "build-original-source/app/src"
header = (engine / "game/user_settings.h").read_text(encoding="utf-8")
settings = (engine / "game/user_settings.c").read_text(encoding="utf-8")
keys = (engine / "mobile/mobile_hotkeys.c").read_text(encoding="utf-8")

assert header.index("bool keys_white_v1;") > header.index("bool spine_mine[2];")
assert "uint8_t reserved_white_alignment[2];" in header
assert "bytes_read >= ext_at + white_at + 1" in settings
assert "memset(ext->key_colour, 0, sizeof(ext->key_colour))" in settings
assert "x->keys_white_v1 = true;" in settings
assert "ImU32 primary = color(1.0f, 1.0f, 1.0f, 1.0f);" in keys
assert 'value["colors"] = stored[...last].map' in rain
assert "colors: c.previewColors, maxBeads: 250" in page
assert "groups: c.previewGroups, colors: c.previewColors" in page
wire = rain.split("private func sendCharactersNow", 1)[1] if "private func sendCharactersNow" in rain else ""
assert wire and "colors" not in wire.split("\n    }", 1)[0]
assert '("wyrm.ios.device-migrations.", .keep)' in sync
assert sync.index("applyShared(shared)", sync.index("private func tryRestore")) < sync.index("applyUpdateDefaults()", sync.index("private func tryRestore"))
assert '"keysWhiteV1": true' in sync and 'doc["keysWhiteV1"] as? Bool != true' in sync
assert 'd.set(Self.limitMax, forKey: Self.limitKey)' in perf
assert "limit == Self.limitMax ? displayMax" in perf
assert "UIPanGestureRecognizer" in page and "gesture.location(in: nil)" in page
assert "landscapePresentation ? dy : dx" in main and "landscapePresentation ? -dx : dy" in main
assert "wantedWidth * fit" in main and "geometry.size.width / 428" in page
print("Rain/update source contracts passed")

# Compile and run the production character type itself on macOS. It has no
# UIKit dependency; missing/invalid per-position colours must preserve skin.
if sys.platform == "darwin":
    model = rain[rain.index("struct WyrmRainCharacter:"):rain.index("/// Pure Rain")]
    fixtures = r'''
var c = WyrmRainCharacter.from(["skin":"abc", "colors":["e0123456", "ff102030", "c0abcdef"]])
assert(c.colors == [0xe0123456, 0xff102030, 0xc0abcdef])
assert(WyrmRainCharacter.from(c.dictionary).colors == c.colors)
let old = WyrmRainCharacter.from(["skin":"abc"])
assert(old.colors == [0,0,0] && old.skin == "abc")
assert(old.dictionary["colors"] == nil)
let zeroSuffix = WyrmRainCharacter.from(["skin":"abc", "colors":["ff123456", "", ""]])
assert((zeroSuffix.dictionary["colors"] as? [String]) == ["ff123456"])
assert(WyrmRainCharacter.from(zeroSuffix.dictionary).colors == zeroSuffix.colors)
let bad = WyrmRainCharacter.from(["skin":"abcde", "colors":["100000000", "xx", 34, "ff123456", NSNull()]])
assert(bad.colors == [0,0,0,0xff123456,0] && bad.skin == "abcde")
c.setSkin("abdq")
assert(c.colors == [0xe0123456,0xff102030,0,0])
c.setSkin("/12")
assert(c.colors == [0,0,0])
c.setSkin("abc")
assert(c.colors == [0,0,0])
let long = WyrmRainCharacter.from(["skin":String(repeating:"a", count:300), "colors":Array(repeating:"ff123456", count:300)])
assert(long.skin.count == 250 && long.colors.count == 250)
print("Rain Swift character fixtures passed: old document, ARGB roundtrip, invalid entries, prefix, preset, bound")
'''
    with tempfile.TemporaryDirectory() as temp:
        script = Path(temp) / "rain.swift"
        script.write_text("import Foundation\n" + model + fixtures, encoding="utf-8")
        subprocess.run(["swift", str(script)], check=True)
