import SwiftUI
import UIKit

struct WyrmRainPage: View {
    let close: () -> Void
    @ObservedObject private var rain = WyrmRain.shared
    @StateObject private var textures = WyrmSkinTextureLibrary.acquire()
    @State private var tab = "Characters"
    @State private var selected = ""
    @State private var editor = ""
    @State private var user = ""
    @State private var pass = ""
    @State private var personal = false
    @State private var transfer = ""
    @State private var transferMessage = ""
    @State private var undo = [String]()
    private var bot: WyrmRainCharacter { rain.characters.first(where: { $0.id == selected }) ?? rain.characters[0] }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack { Button("‹ Back", action: close); Spacer() }.font(.androidWyrm(14,.semibold))
                Text("Snakey Rain").font(.custom("BodoniModa-Regular",size:34)).foregroundColor(ATheme.ink)
                Toggle("Enable Snakey Rain", isOn: Binding(get:{ rain.enabled },set:rain.enable))
                Text(rain.status).font(.androidWyrm(12,.medium)).foregroundColor(ATheme.quiet)
                Picker("Rain page", selection:$tab) { ForEach(["Characters","Settings","Login"], id:\.self) { Text($0).tag($0) } }.pickerStyle(.segmented)
                if tab == "Login" { login }
                else if tab == "Settings" { settings }
                else { characters }
            }.padding(20).padding(.bottom,36)
        }.background(ATheme.paper.ignoresSafeArea()).foregroundColor(ATheme.ink).font(.androidWyrm(14,.regular))
            .onAppear { textures.prepare(); user = rain.username; pass = rain.password; personal = rain.personal }
    }
    private var login: some View {
        VStack(alignment:.leading,spacing:14) {
            Text("Change the credentials").font(.androidWyrm(19,.bold))
            Text("Enter your personal Snakey account to use Snakey Rain. Otherwise, the public account is used.").font(.androidWyrm(13,.regular))
            Toggle("Use my personal account",isOn:$personal)
            TextField("Username",text:$user).textContentType(.username).autocapitalization(.none).disableAutocorrection(true).textFieldStyle(.roundedBorder)
            SecureField("Password",text:$pass).textContentType(.password).textFieldStyle(.roundedBorder)
            Text("Public account changes are temporary. Its original credentials return when you restart the app.").font(.androidWyrm(12,.regular))
            Button("Connect") { rain.credentials(user,pass,personal:personal); rain.enable(true) }.buttonStyle(.borderedProminent)
            Button("Use public account") { personal = false; rain.credentials("","",personal:false); user = rain.username; pass = rain.password; rain.enable(true) }
            Link("Create a personal account ↗",destination:URL(string:"https://snakeyrain.com/")!)
            Button("Disconnect",action:rain.disconnect)
        }
    }
    private var settings: some View {
        VStack(alignment:.leading,spacing:14) {
            ForEach(WyrmRain.ranges,id:\.0) { key, range in
                VStack(alignment:.leading) {
                    Text("\(Self.settingName(key)) · \(rain.config[key] ?? 0, specifier:key == "rOC" ? "%.2f" : "%.0f")").font(.androidWyrm(13,.medium))
                    Slider(value:Binding(get:{rain.config[key] ?? range.lowerBound},set:{rain.set(key,$0)}),in:range)
                }
            }
            Toggle("Cycle through characters",isOn:Binding(get:{rain.evolveEnabled},set:{rain.flag("evolveEnabled",$0)}))
            Toggle("Player rotation",isOn:Binding(get:{rain.rotationEnabled},set:{rain.flag("rotationEnabled",$0)}))
            WyrmSectionLabel("Keyboard controls")
            ForEach(WyrmRain.defaultKeys.keys.sorted(),id:\.self) { key in
                HStack { Text(key); Spacer(); TextField("Key",text:Binding(get:{rain.keys[key] ?? ""},set:{rain.setKey(key,$0)})).frame(width:90).textFieldStyle(.roundedBorder) }
            }
            WyrmSectionLabel("Import and export")
            Text("Only settings and characters are exported. Passwords stay on this phone.").font(.androidWyrm(12,.regular))
            TextEditor(text:$transfer).frame(height:130).overlay(RoundedRectangle(cornerRadius:12).stroke(ATheme.rule))
            HStack { Button("Export") { transfer = rain.export() }; Button("Import") { transferMessage = rain.importSettings(transfer) ? "Settings imported" : "Could not read these settings" } }
            Text(transferMessage).font(.androidWyrm(12,.regular))
            Button("Reset settings",action:rain.reset)
        }
    }
    private func change(_ write: (inout WyrmRainCharacter) -> Void) {
        var value = bot; write(&value)
        if value.skin != bot.skin { undo.append(bot.skin); undo = Array(undo.suffix(100)) }
        rain.update(value)
    }
    private var groups: [Int] {
        if bot.skin.hasPrefix("/") || bot.skin.hasPrefix("\\"), let preset = Int(bot.skin.dropFirst()), WyrmSkinCatalog.presets.indices.contains(preset) { return WyrmSkinCatalog.presets[preset] }
        return bot.skin.compactMap { WyrmSkinCatalog.group(for:$0) }
    }
    private var characters: some View {
        VStack(alignment:.leading,spacing:14) {
            WyrmSkinPreview(textures:textures,groups:groups,colors:[],preset:Int(bot.skin.dropFirst()) ?? 0,
                custom:!(bot.skin.hasPrefix("/") || bot.skin.hasPrefix("\\")),accessoryID:bot.cosmetic == 255 ? -1:bot.cosmetic,
                tagID:WyrmSkinCatalog.tags.first(where:{$0.ntlID == Int(bot.tag)})?.id ?? -1,backgroundID:0,chain:0.4,swing:0.4,tagScale:0.4,
                trialLook:WyrmTrailSkin.Look(hair:-1,hairTone:0.22,ears:-1,glasses:-1))
                .frame(height:170).accessibilityLabel("Selected Rain snake preview")
            HStack { Button("Add") { rain.add(); selected = rain.characters.last?.id ?? "" }.disabled(rain.characters.count >= 100)
                Button("Remove") { rain.remove(bot.id); selected = rain.characters[0].id }.disabled(rain.characters.count <= 1)
                Button("↑") { rain.move(bot.id,-1) }; Button("↓") { rain.move(bot.id,1) } }
            HStack { Button("Enable all") { rain.all(true) }; Button("Disable all") { rain.all(false) } }
            ScrollView(.horizontal,showsIndicators:false) { HStack { ForEach(rain.characters) { item in Button(item.label) { selected = item.id; editor = ""; undo = [] }.font(.androidWyrm(13,bot.id == item.id ? .bold:.regular)) } } }
            Toggle("Use this character",isOn:Binding(get:{bot.enabled},set:{ value in change{$0.enabled = value} }))
            TextField("Character name",text:Binding(get:{bot.label},set:{value in change{$0.label = value}})).textFieldStyle(.roundedBorder)
            TextField("In-game name",text:Binding(get:{bot.name},set:{value in change{$0.name = value}})).textFieldStyle(.roundedBorder)
            TextField("Skin code",text:Binding(get:{bot.skin},set:{value in change{$0.skin = value}})).autocapitalization(.none).disableAutocorrection(true).textFieldStyle(.roundedBorder)
            Text("\(bot.skin.count)/250").font(.androidWyrm(11,.medium))
            HStack {
                Button("Build a pattern") { editor = editor == "Pattern" ? "":"Pattern" }
                Button("Undo") { if let skin = undo.popLast() { var value = bot; value.skin = skin; rain.update(value) } }.disabled(undo.isEmpty)
                Button("Clear") { change { $0.skin = "" } }
            }
            if editor == "Pattern" {
                LazyVGrid(columns:Array(repeating:GridItem(.flexible(),spacing:6),count:7),spacing:6) {
                    ForEach(WyrmSkinCatalog.validGroups,id:\.self) { id in
                        Button { change { value in value.skin = String((WyrmSkinCatalog.code(for:groups) + WyrmSkinCatalog.code(for:[id])).prefix(250)) } } label: {
                            WyrmAtlasImage(image:textures.beads[id]).frame(height:38).frame(maxWidth:.infinity).background(ATheme.well).cornerRadius(10)
                        }.buttonStyle(.plain).accessibilityLabel("Add bead \(id)")
                    }
                }
            }
            HStack { Button("Repeat ×5") { change { value in value.skin = String((value.skin + String(repeating:String(value.skin.suffix(1)),count:5)).prefix(250)) } }
                Button("Presets") { editor = editor == "Presets" ? "" : "Presets" } }
            if editor == "Presets" {
                LazyVGrid(columns:Array(repeating:GridItem(.flexible()),count:4)) { ForEach(0..<66,id:\.self) { id in Button("\(id)") { change{$0.skin = "/\(id)"}; editor = "" } } }
            }
            HStack { Button("Accessories") { editor = editor == "Accessories" ? "" : "Accessories" }; Button("Tags") { editor = editor == "Tags" ? "" : "Tags" } }
            if editor == "Accessories" {
                Button("None") { change{$0.cosmetic = 255} }
                WyrmRainAccessoryGrid(textures:textures,selected:bot.cosmetic) { id in change{$0.cosmetic = id} }
            }
            if editor == "Tags" {
                Button("None") { change{$0.tag = "-1"} }
                WyrmRainTagGrid(textures:textures,selected:Int(bot.tag) ?? -1) { id in change{$0.tag = String(id)} }
            }
            TextField("Tag id or private tag code",text:Binding(get:{bot.tag},set:{value in change{$0.tag = value}})).textFieldStyle(.roundedBorder).autocapitalization(.none)
            Text("Private bot tag codes are sent to the Rain service. Use a tag only with its owner's permission.").font(.androidWyrm(12,.regular))
        }
    }
    static func settingName(_ key: String) -> String {
        ["maxBots":"Maximum bots","size":"Tornado size","separation":"Tornado separation","finalAng":"Final angle","rOC":"Angle change rate","rotationDir":"Clockwise direction","period":"Wigwag period (ms)","amplitude":"Wigwag amplitude","ranRate":"Random rate (ms)","evolveTime":"Cycle time (seconds)","evolveBots":"Characters per cycle"][key] ?? key
    }
}

// Same catalogues, thumbnails and tile language as the existing Skin page.
struct WyrmRainAccessoryGrid: View {
    @ObservedObject var textures: WyrmSkinTextureLibrary
    let selected: Int; let pick: (Int) -> Void
    var body: some View {
        LazyVGrid(columns:Array(repeating:GridItem(.flexible(),spacing:10),count:4),spacing:10) {
            ForEach(WyrmSkinCatalog.accessories) { item in Button { pick(item.id) } label: {
                WyrmAtlasImage(image:textures.accessoryThumbnails[item.id]).padding(4).aspectRatio(1,contentMode:.fit)
                    .background(ATheme.card).cornerRadius(15).overlay(RoundedRectangle(cornerRadius:15).stroke(selected == item.id ? ATheme.ink:ATheme.rule,lineWidth:selected == item.id ? 2:1))
            }.buttonStyle(.plain).accessibilityLabel("Accessory \(item.id + 1)") }
        }
    }
}
struct WyrmRainTagGrid: View {
    @ObservedObject var textures: WyrmSkinTextureLibrary
    let selected: Int; let pick: (Int) -> Void
    var body: some View {
        LazyVGrid(columns:[GridItem(.adaptive(minimum:76),spacing:10)],spacing:10) {
            ForEach(WyrmSkinCatalog.tagPickerOrder.filter { !WyrmSkinCatalog.isWyrmTag($0.ntlID) }) { item in Button { pick(item.ntlID) } label: {
                WyrmAtlasImage(image:textures.tagThumbnails[item.id]).padding(7).aspectRatio(1,contentMode:.fit)
                    .background(ATheme.card).cornerRadius(15).overlay(RoundedRectangle(cornerRadius:15).stroke(selected == item.ntlID ? ATheme.ink:ATheme.rule,lineWidth:selected == item.ntlID ? 2:1))
            }.buttonStyle(.plain).accessibilityLabel("Tag \(item.ntlID)") }
        }
    }
}

struct WyrmRainPanel: View {
    @ObservedObject private var rain = WyrmRain.shared
    @State private var expanded = false
    @State private var origin = CGSize(width:12,height:24)
    @State private var dragOrigin = CGSize.zero
    var body: some View {
        Group {
            if expanded { controls } else { Button("Rain") { expanded = true; layout() }.frame(width:70,height:54).background(ATheme.paper).cornerRadius(18) }
        }.font(.androidWyrm(12,.semibold)).foregroundColor(ATheme.ink)
            .onReceive(NotificationCenter.default.publisher(for:Notification.Name("WyrmEngineScreenChanged"))) { _ in layout() }
            .onChange(of:rain.enabled) { _ in layout() }
            .onChange(of:rain.snapshot["alive"] as? Bool ?? false) { _ in layout() }
            .onAppear { layout() }
    }
    private func layout() { WyrmIOSSetRainPanel(rain.enabled && (rain.snapshot["alive"] as? Bool == true), expanded, Double(origin.width),Double(origin.height)) }
    private var controls: some View {
        VStack(spacing:8) {
            HStack { Text("Rain · \(rain.count) bots"); Spacer(); Button("×") { expanded = false; layout() } }
            Text(rain.status).font(.androidWyrm(11,.regular)).lineLimit(2)
            HStack { Button(rain.running ? "Stop":"Start") { if rain.running { rain.stop() } else { rain.start() } }
                Button(rain.boosting ? "Boost off":"Boost",action:rain.boost)
                Button("Reconnect") { rain.disconnect(); rain.connect() } }
            ScrollView {
                VStack(spacing:10) {
                    LazyVGrid(columns:[GridItem(.flexible()),GridItem(.flexible())],spacing:8) {
                        ForEach(1..<15,id:\.self) { id in Button((rain.mode == id ? "• ":"") + WyrmRain.modes[id-1]) { rain.setMode(id) }.frame(minHeight:44).frame(maxWidth:.infinity).background(ATheme.well).cornerRadius(12) }
                    }
                    Text("Target a nearby snake")
                    ForEach(Array((rain.snapshot["targets"] as? [[String:Any]] ?? []).enumerated()),id:\.offset) { _, target in
                        Button("Snake \((target["id"] as? NSNumber)?.intValue ?? 0)") { rain.target(target) }.frame(minHeight:44)
                    }
                    Text("Pointer pad · Copy / Follow pointer")
                    GeometryReader { proxy in Text("Drag to aim").frame(maxWidth:.infinity,maxHeight:.infinity).background(ATheme.well)
                        .gesture(DragGesture(minimumDistance:0).onChanged { rain.pointer($0.location,proxy.size) }) }.frame(height:100)
                    HStack { Button("Rotate left") { rain.rotate(rain.rotation == -1 ? 0:-1) }; Button("Rotate right") { rain.rotate(rain.rotation == 1 ? 0:1) } }
                    Button("Stop rotation") { rain.rotate(0) }
                    Text("Live settings")
                    ForEach(WyrmRain.ranges,id:\.0) { key, range in
                        VStack(alignment:.leading) {
                            Text("\(WyrmRainPage.settingName(key)) · \(rain.config[key] ?? 0, specifier:key == "rOC" ? "%.2f":"%.0f")")
                            Slider(value:Binding(get:{rain.config[key] ?? range.lowerBound},set:{rain.set(key,$0)}),in:range)
                        }
                    }
                    Toggle("Cycle characters",isOn:Binding(get:{rain.evolveEnabled},set:{rain.flag("evolveEnabled",$0)}))
                    Toggle("Player rotation",isOn:Binding(get:{rain.rotationEnabled},set:{rain.flag("rotationEnabled",$0)}))
                }
            }
            Capsule().fill(ATheme.ink.opacity(0.35)).frame(width:42,height:7).frame(maxWidth:.infinity).frame(height:44).contentShape(Rectangle())
                .gesture(DragGesture().onChanged { value in
                    if dragOrigin == .zero { dragOrigin = origin }; origin = CGSize(width:dragOrigin.width + value.translation.width,height:dragOrigin.height + value.translation.height); layout()
                }.onEnded { _ in dragOrigin = .zero })
                .accessibilityLabel("Drag Rain panel")
        }.padding(12).frame(maxWidth:.infinity,maxHeight:.infinity).background(ATheme.paper.opacity(0.97)).cornerRadius(20)
    }
}

@objc(WyrmRainHost)
@MainActor
final class WyrmRainHost: NSObject {
    @objc static func handleKey(_ key: String) -> Bool { WyrmRain.shared.handleKey(key) }
    @objc static func makeViewController() -> UIViewController {
        let controller = UIHostingController(rootView:WyrmRainPanel()); controller.view.backgroundColor = .clear; return controller
    }
}
