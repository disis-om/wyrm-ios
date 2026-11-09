"""Wardrobe ownership/layout contracts and portable Swift motion regression.
Source checks do not establish app compilation or visual/device acceptance.
"""
from pathlib import Path
import shutil
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[1]
def read(name):
    return (ROOT / "SourcesShell" / name).read_text(encoding="utf-8")
scene = read("WyrmWardrobeScene.swift")
root = read("WyrmSkinStudio.swift")
controls = read("WyrmWardrobeControls.swift")
mesh = read("WyrmSkins.swift")
motion = read("WyrmWardrobeMotion.swift")
checks = {
    "scene owns clock, motion, rope and mesh across all picker changes":
        "@StateObject private var scene = WyrmWardrobeSceneState()" in scene
        and "let motion = WyrmWardrobeMotion()" in scene and "let ropes = WyrmWardrobeRopes()" in scene
        and "let mesh = WyrmSkinMesh()" in scene,
    "same raised camera destination and divider for every picker":
        "0.5 - 0.30 * open" in scene and "size.height * 0.34" in scene
        and "if raised != self.raised" in scene and "proxy.size.height * 0.66" in root,
    "original tag solver is persistent": "let native = WyrmNtlPreviewRope()" in scene,
    "raw touch handoff runs through portable tracker": "scene.touches.down(" in scene
        and "scene.touches.move(" in scene and "scene.touches.up(" in scene and "isMultipleTouchEnabled = true" in scene,
    "single/two saved skins finite and three loop": "infinite: !saved || next.count >= 3" in scene
        and "if size <= 1 { rebase(0) }" in motion,
    "Wyrm skins inserted after three presets": "Array(defaults.prefix(3)) + creatures + Array(defaults.dropFirst(3))" in scene,
    "Wyrm skins use actual posed native rendering": "scene.mesh.drawPosed" in scene
        and "wyrm_skin_preview_pose(" in mesh and "truncatingRemainder(dividingBy: 9) > 7.2" in mesh,
    "fixed headers and Wyrm look segments sit outside choices scroll":
        root.index("WyrmWardrobeHeader(title:") < root.index('ScrollViewReader { scroll in', root.index('WyrmWardrobeHeader(title:'))
        and 'WSSegmented(options: ["Hair", "Ears", "Glasses"]' in root,
    "build uses pinned colours undo redo OK with exact history": all(x in controls for x in
        ["glyph: .colours", "glyph: .undo", "glyph: .redo", "glyph: .ok", "history.undo()", "history.redo()"]),
    "saved chooser has no separate OK pane": "![.overview, .presets, .texture, .saved].contains(section)" in root,
    "texture dock opens immediately": "WyrmWardrobeTextureDock(" in root and "Select texture" not in controls,
    "one rigid head transform for the in-phase body morph": "headDrawing(headContext" in scene and "let head = points[57], headSize = bead" in scene
        and "1.16 * bead * morph" in scene and "first + 127" in scene,
    # The code field is a real text view since 2026-11-07 (cursor drag, Select all, Copy).
    "Build code and private tag fields reveal above native keys": 'WyrmSkinCodeField(groups: groups, placeholder: "Paste a skin code"' in controls
        and 'scroll.scrollTo("wardrobe-code"' in controls and 'scroll.scrollTo("wardrobe-tag-input"' in root
        and '.modifier(WyrmAboveKeys())' in root,
    "arena resize is fixed beside OK, never after grid": 'glyph: .resize, label: "Adjust size"' in controls
        and 'adjust: section == .background' in root and 'adjustSizeButton.padding(12)' not in root,
    "compact eight-choice texture dock has stagger and a short scope switch": 'ForEach(Array(WyrmSkinTexture.offered.enumerated())' in controls
        and 'width: 36, height: 22' in controls and '.delay(Double(position) * 0.024)' in controls,
    "all categories use shared authored vectors": all(x in root for x in
        ["(.pattern, .build)", "(.accessories, .accessories)", "(.tags, .tags)", "(.background, .background)",
         "(.wyrmAccessories, .wyrmAccessories)", "(.texture, .texture)", "(.saved, .saved)"]),
    "Skin keeps expanded native tab bar": ".tabBarMinimizeBehavior(tab == .skin ? .never : .onScrollDown)" in read("WyrmDesignMain.swift"),
    "Studio player access hidden; explicit debug probe retained":
        '!ProcessInfo.processInfo.arguments.contains("--smoke-skin-studio")' in read("WyrmSkinStudioPage.swift"),
    "saved scene hold opens its existing Edit/Remove actions":
        'onHold: onHold' in scene and 'UILongPressGestureRecognizer' in scene
        and 'gesture.minimumPressDuration = 0.45' in scene
        and 'hold.isEnabled = enabled && scene.saved' in scene
        and 'WyrmSavedSelectionBar(count: savedSelection.count' in root
        and 'savedLibrary.delete(savedSelection)' in root
        and 'action("Remove"' in read('WyrmSavedSkins.swift'),
}
android = ROOT.parent / 'Wyrm Android/android/app/src/main/java/com/wyrm/omrajput/ui'
if android.exists():
    a=(android/'AndroidSkinWardrobe.kt').read_text(encoding='utf-8')
    b=(android/'IosSkinScreen.kt').read_text(encoding='utf-8')
    checks['Android saved hold includes one skin, cancels on drag, reuses actions'] = (
        'if (!browsing || entries.isEmpty())' in a and 'latestHold?.invoke(it)' in a
        and 'withTimeoutOrNull(' in a and 'viewConfiguration.touchSlop' in a
        and 'onHold = { item ->' in b and 'SavedSelectionBar(savedSelection.size' in b
        and 'SavedSkins.delete(savedSelection)' in b and 'SelectionAction("Remove"' in b)
for name, ok in checks.items():
    print(f"{'PASS' if ok else 'FAIL'}: {name}")
assert all(checks.values()), "wardrobe source contract failed"
print(f"Wardrobe source contracts: {len(checks)}/{len(checks)} passed")
swift = shutil.which("swiftc")
if swift:
    with tempfile.TemporaryDirectory(prefix="wyrm-swift-wardrobe-") as temp:
        executable = Path(temp) / "motion"
        subprocess.run([swift, str(ROOT / "SourcesShell/WyrmWardrobeMotion.swift"),
                        str(ROOT / "Tests/wardrobe_motion_check.swift"), "-o", str(executable)], check=True)
        subprocess.run([str(executable)], check=True)
else:
    print("Swift motion execution skipped: swiftc unavailable on this host")
