"""Execute production palette/intensity/migration maths with Swift on Apple CI."""
from pathlib import Path
import re,shutil,subprocess,tempfile,hashlib
ROOT=Path(__file__).resolve().parents[1]
theme=(ROOT/'SourcesShell/WyrmTheme.swift').read_text(encoding='utf-8')
tables=(ROOT/'SourcesShell/WyrmThemeTables.swift').read_text(encoding='utf-8')
sync=(ROOT/'SourcesShell/WyrmAccountSync.swift').read_text(encoding='utf-8')
for file in ['WyrmCinematicAuth.swift','WyrmDesignMain.swift','WyrmSkinStudio.swift']:
 assert 'â€' not in (ROOT/'SourcesShell'/file).read_text(encoding='utf-8'), 'UTF-8 text was decoded as a legacy code page: '+file
android=ROOT.parent/'Wyrm Android/android/app/src/main/java/com/wyrm/omrajput/ui'
if android.exists():
 assert "PasswordVisualTransformation('•')" in (android/'CinematicAuthScreen.kt').read_text(encoding='utf-8')
 for file in ['CinematicAuthScreen.kt','IosArenaPicker.kt','NotificationsScreen.kt','Trails.kt']:
  assert 'â€' not in (android/file).read_text(encoding='utf-8'),file
assert '("wyrm.ios.theme", .sync)' in sync
assert 'wyrm.ios.theme-mode' in theme and 'defaults.set(mode.rawValue' in theme
assert 'case .auto: return systemDark ? dark : light' in tables
assert r'content.environment(\.wyrmPaletteOverride' in theme
assert 'p.hero.bg, p.hero.on, p.hero2.bg, p.hero2.on' in theme
assert '.background(palette.paper.color)' not in theme, 'hero scope must not add a square backing'
assert 'private let visibleThemes: [WyrmThemeID] = [.sand, .linen, .grape, .cyan, .metal3, .midnight, .colonial3,' in (ROOT/'SourcesShell/WyrmSettingsPages.swift').read_text(encoding='utf-8')
visible=re.search(r'private let visibleThemes: \[WyrmThemeID\] = \[(.*?)\]',(ROOT/'SourcesShell/WyrmSettingsPages.swift').read_text(encoding='utf-8'),re.S).group(1)
visible_ids=re.findall(r'\.(\w+)',visible)
assert len(visible_ids)==15 and len(set(visible_ids))==15
if android.exists():
 kt_visible=re.search(r'val themes = listOf\((.*?)\)',(android/'SettingsAccessibilityScreen.kt').read_text(encoding='utf-8'),re.S).group(1)
 assert [i.lower() for i in re.findall(r'WyrmThemeId\.(\w+)',kt_visible)]==visible_ids
for file in ['WyrmDesignComponents.swift','WyrmCinematicAuth.swift']:
 assert '.shadow(color: wyrmScopedColours.ink' not in (ROOT/'SourcesShell'/file).read_text(encoding='utf-8'), 'theme ink becomes a white glow in dark mode'

# Hash every one of the seventeen original roles, not just the headline swatches.
expected_classic={'classic_blush': '231dde59605eaced5ff06d3291818dd4f850ca985f61d2c505f11360b17a1aaf',
 'classic_forest': '9ce81d342a3e05d131f9af2d8c76197953083fb577ea972184ad916a839978dd',
 'classic_graphite': '9d3f3566aec4e7d86466998de5c1f1d211ced529f4d8abe18e29917fe47d4780',
 'classic_lilac': '95e25306f94c1ad66c375fef1acd5d04492a603697fc763fa777dc9b91a1eec0',
 'classic_midnight': '82f7d5b18e9eae19b7f1ee8052caf34e63da9c07b4006c18102f45f016001c4d',
 'classic_paper': '80f28a5154108ef2360199e4482a41e17a5a498d4923df0bbadf3a06ada73dcd',
 'classic_slate': 'f65cbe1422b7e40df8a481f8117c355ad8a7c4bc7c5034c64beed9cc61f1b6d4',
 'classic_sun': '3180183ca8e41ef092738728bb516342e19cfc3baea498e38b282ccbc3afb372'}

for name,digest in expected_classic.items():
 block=tables.split('case .'+name+':',1)[1].split('case .',1)[0]
 arrays=re.findall(r'WyrmPalette\(\[([^\]]+)\]',block)
 values=re.findall(r'0x[0-9A-F]{8}',arrays[1 if name in ['classic_graphite','classic_midnight'] else 0])
 assert len(values)==17
 assert hashlib.sha256(','.join(f'{int(c,16):08X}' for c in values).encode()).hexdigest()==digest,name
print('Eight classic palettes: all 136 original roles match pinned hashes')

model=theme[theme.index('struct WyrmPalette:'):theme.index('final class WyrmThemeStore:')]
model=re.sub(r'    var color: Color \{[^\n]+\}\n','',model)
table_model=tables.replace('import SwiftUI','')
restore_start=sync.index('        let savedDefaults = doc["defaults"]')
restore_end=sync.index('        if doc["lbOriginalV1"] as? Bool == true',restore_start)
restore_model='func restoreTheme(_ doc: [String:Any], _ d: UserDefaults) {\n'+sync[restore_start:restore_end]+'\n}\n'
fixtures=r'''
func readable(_ fg:WyrmRGBA,_ bg:WyrmRGBA,_ label:String) {
    precondition(contrastRatio(bg,fg) >= 4.4999,label)
}
precondition(WyrmThemeID.allCases.count == 30)
var checks=0
for theme in WyrmThemeID.allCases {
 for mode in [WyrmThemeMode.light,.dark] {
  for intensity in [0.0,0.5,1.0] {
   let p=theme.side(mode:mode,systemDark:false).withIntensity(intensity)
   for h in [p.hero,p.hero2] {
    let attainable=max(contrastRatio(h.bg,.white),contrastRatio(h.bg,WyrmRGBA(argb:0xFF000000)))
    precondition(contrastRatio(h.bg,h.on)>=min(6.5,attainable)-0.0001,"hero ink must reach 6.5 when the palette allows it")
   }
   for (a,b,label) in [(p.ink,p.paper,"ink/paper"),(p.quiet,p.paper,"quiet/paper"),(p.quiet,p.well,"placeholder/field"),(p.link,p.paper,"link/paper"),(p.tabIdle,p.tabBar,"tab/bar"),(p.chevron,p.paper,"chevron/paper"),(p.live,p.card,"live/card"),(p.badge,p.card,"badge/card"),(p.hero.on,p.hero.bg,"onHero/hero"),(p.hero2.on,p.hero2.bg,"onHero2/hero2"),(p.hero.quiet,p.hero.well,"hero placeholder/field"),(p.hero2.quiet,p.hero2.well,"hero2 placeholder/field")] {
    readable(a,b,"\(theme.rawValue) \(mode) \(intensity) \(label)");checks+=1
   }
  }
 }
}
for (old,id,mode) in [("paper","classic_paper","light"),("graphite","classic_graphite","dark"),("blush","classic_blush","light"),("sun","classic_sun","light"),("slate","classic_slate","light"),("lilac","classic_lilac","light"),("forest","classic_forest","light"),("midnight","classic_midnight","dark")] {
 let value=WyrmThemeID.resolve(name:old,modeRaw:nil)
 precondition(value.0.rawValue==id && value.1.rawValue==mode)
}
precondition(WyrmThemeID.resolve(name:"future-theme",modeRaw:nil).0 == .sand)
precondition(WyrmThemeID.resolve(name:nil,modeRaw:nil).0 == .classic_paper && WyrmThemeID.resolve(name:nil,modeRaw:nil).1 == .light)
precondition(WyrmThemeID.sand.side(mode:.auto,systemDark:true).dark)
precondition(!WyrmThemeID.sand.side(mode:.auto,systemDark:false).dark)
let suite="WyrmThemeFixture-"+UUID().uuidString
let d=UserDefaults(suiteName:suite)!
defer { d.removePersistentDomain(forName:suite) }
d.set("light",forKey:"wyrm.ios.theme-mode")
restoreTheme(["themeRefreshV1":true,"defaults":["wyrm.ios.theme":["s","graphite"]]],d)
precondition(d.string(forKey:"wyrm.ios.theme")=="classic_graphite" && d.string(forKey:"wyrm.ios.theme-mode")=="dark","old document must override the stale startup mode")
restoreTheme(["themeRefreshV1":true,"defaults":["wyrm.ios.theme":["s","midnight"],"wyrm.ios.theme-mode":["s","light"]]],d)
precondition(d.string(forKey:"wyrm.ios.theme-mode")=="light","new Midnight light choice survives restore")
restoreTheme(["themeRefreshV1":true,"defaults":["wyrm.ios.theme":["s","future-theme"]]],d)
precondition(d.string(forKey:"wyrm.ios.theme")=="sand")
d.set(0.7,forKey:"wyrm.ios.theme-intensity")
restoreTheme(["themeRefreshV1":true,"defaults":["wyrm.ios.theme":["i",23],"wyrm.ios.theme-mode":["s",false],"wyrm.ios.theme-intensity":["f",true]]],d)
precondition(d.string(forKey:"wyrm.ios.theme")=="sand" && d.double(forKey:"wyrm.ios.theme-intensity")==0.7,"invalid typed keys skipped individually")
restoreTheme(["defaults":["wyrm.ios.theme":["s","uniform"],"wyrm.ios.theme-mode":["s","light"]]],d)
precondition(d.string(forKey:"wyrm.ios.theme")=="uniform" && d.string(forKey:"wyrm.ios.theme-mode")=="light" && d.double(forKey:"wyrm.ios.theme-intensity")==0.7,"legacy account appearance restores without a refresh marker")
print("Production Swift theme maths: \(checks) contrast checks, 30 palettes, old-document migrations and Auto passed")
'''
if shutil.which('swift'):
 with tempfile.TemporaryDirectory() as d:
  p=Path(d)/'palette.swift';p.write_text('import Foundation\nimport CoreFoundation\n'+model+'\n'+table_model+'\n'+restore_model+'\n'+fixtures,encoding='utf-8')
  subprocess.run(['swift',str(p)],check=True)
else:print('Swift palette execution deferred to Apple CI; source contracts passed')
