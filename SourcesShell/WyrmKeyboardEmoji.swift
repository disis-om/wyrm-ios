import SwiftUI

/*
 * Emoji on Wyrm's own keyboard (OM, 2026-09-29), laid out the way the system
 * keyboard shows them: a sideways-scrolling page per category, the category
 * strip along the bottom with ABC and delete at either end, and the ones used
 * most recently first. Recents stay on this iPhone.
 */

enum WyrmEmoji {
    static let recentKey = "wyrm.ios.keyboard.recent-emoji"

    static let categories: [(name: String, symbol: String, emoji: [String])] = [
        ("Frequently used", "clock", []),
        ("Smileys & people", "face.smiling", Array("😀😃😄😁😆🥹😅😂🤣🥲☺️😊😇🙂🙃😉😌😍🥰😘😗😙😚😋😛😝😜🤪🤨🧐🤓😎🥸🤩🥳😏😒😞😔😟😕🙁☹️😣😖😫😩🥺😢😭😤😠😡🤬🤯😳🥵🥶😱😨😰😥😓🤗🤔🫣🤭🫢🤫🤥😶😐😑😬🙄😯😦😧😮😲🥱😴🤤😪😵🤐🥴🤢🤮🤧😷🤒🤕🤑🤠😈👿👹👺🤡💩👻💀☠️👽👾🤖🎃😺😸😹😻😼😽🙀😿😾👋🤚🖐️✋🖖👌🤌🤏✌️🤞🫰🤟🤘🤙👈👉👆🖕👇☝️👍👎✊👊🤛🤜👏🙌🫶👐🤲🤝🙏✍️💅🤳💪🦾🦵🦶👂🦻👃🧠🫀🫁🦷🦴👀👁️👅👄💋🩸").map(String.init)),
        ("Animals & nature", "pawprint", Array("🐶🐱🐭🐹🐰🦊🐻🐼🐻‍❄️🐨🐯🦁🐮🐷🐽🐸🐵🙈🙉🙊🐒🐔🐧🐦🐤🐣🐥🦆🦅🦉🦇🐺🐗🐴🦄🐝🪱🐛🦋🐌🐞🐜🪰🪲🪳🦟🦗🕷️🦂🐢🐍🦎🦖🦕🐙🦑🦐🦞🦀🐡🐠🐟🐬🐳🐋🦈🐊🐅🐆🦓🦍🦧🦣🐘🦛🦏🐪🐫🦒🦘🦬🐃🐂🐄🐎🐖🐏🐑🦙🐐🦌🐕🐩🦮🐈🐓🦃🦤🦚🦜🦢🦩🕊️🐇🦝🦨🦡🦫🦦🦥🐁🐀🐿️🦔🐾🐉🐲🌵🎄🌲🌳🌴🪵🌱🌿☘️🍀🎍🪴🎋🍃🍂🍁🍄🐚🪨🌾💐🌷🌹🥀🌺🌸🌼🌻🌞🌝🌛🌜🌚🌕🌖🌗🌘🌑🌒🌓🌔🌙🌎🌍🌏🪐💫⭐🌟✨⚡☄️💥🔥🌪️🌈☀️🌤️⛅🌥️☁️🌦️🌧️⛈️🌩️🌨️❄️☃️⛄🌬️💨💧💦🫧☔☂️🌊").map(String.init)),
        ("Food & drink", "fork.knife", Array("🍏🍎🍐🍊🍋🍌🍉🍇🍓🫐🍈🍒🍑🥭🍍🥥🥝🍅🍆🥑🥦🥬🥒🌶️🫑🌽🥕🫒🧄🧅🥔🍠🥐🥯🍞🥖🥨🧀🥚🍳🧈🥞🧇🥓🥩🍗🍖🦴🌭🍔🍟🍕🫓🥪🥙🧆🌮🌯🫔🥗🥘🫕🥫🍝🍜🍲🍛🍣🍱🥟🦪🍤🍙🍚🍘🍥🥠🥮🍢🍡🍧🍨🍦🥧🧁🍰🎂🍮🍭🍬🍫🍿🍩🍪🌰🥜🍯🥛🍼🫖☕🍵🧃🥤🧋🍶🍺🍻🥂🍷🥃🍸🍹🧉🍾🧊🥄🍴🍽️🥣🥡🥢🧂").map(String.init)),
        ("Activity", "gamecontroller", Array("⚽🏀🏈⚾🥎🎾🏐🏉🥏🎱🪀🏓🏸🏒🏑🥍🏏🪃🥅⛳🪁🏹🎣🤿🥊🥋🎽🛹🛼🛷⛸️🥌🎿⛷️🏂🪂🏋️🤼🤸⛹️🤺🤾🏌️🏇🧘🏄🏊🤽🚣🧗🚵🚴🏆🥇🥈🥉🏅🎖️🏵️🎗️🎫🎟️🎪🤹🎭🩰🎨🎬🎤🎧🎼🎹🥁🪘🎷🎺🪗🎸🪕🎻🎲♟️🎯🎳🎮🎰🧩").map(String.init)),
        ("Travel & places", "car", Array("🚗🚕🚙🚌🚎🏎️🚓🚑🚒🚐🛻🚚🚛🚜🦯🦽🦼🛴🚲🛵🏍️🛺🚨🚔🚍🚘🚖🚡🚠🚟🚃🚋🚞🚝🚄🚅🚈🚂🚆🚇🚊🚉✈️🛫🛬🛩️💺🛰️🚀🛸🚁🛶⛵🚤🛥️🛳️⛴️🚢⚓🪝⛽🚧🚦🚥🚏🗺️🗿🗽🗼🏰🏯🏟️🎡🎢🎠⛲⛱️🏖️🏝️🏜️🌋⛰️🏔️🗻🏕️⛺🛖🏠🏡🏘️🏚️🏗️🏭🏢🏬🏣🏤🏥🏦🏨🏪🏫🏩💒🏛️⛪🕌🕍🛕🕋⛩️🛤️🛣️🗾🎑🏞️🌅🌄🌠🎇🎆🌇🌆🏙️🌃🌌🌉🌁").map(String.init)),
        ("Objects", "lightbulb", Array("⌚📱📲💻⌨️🖥️🖨️🖱️🖲️🕹️🗜️💽💾💿📀📼📷📸📹🎥📽️🎞️📞☎️📟📠📺📻🎙️🎚️🎛️🧭⏱️⏲️⏰🕰️⌛⏳📡🔋🔌💡🔦🕯️🪔🧯🛢️💸💵💴💶💷🪙💰💳💎⚖️🪜🧰🪛🔧🔨⚒️🛠️⛏️🪚🔩⚙️🪤🧱⛓️🧲🔫💣🧨🪓🔪🗡️⚔️🛡️🚬⚰️🪦⚱️🏺🔮📿🧿💈⚗️🔭🔬🕳️🩹🩺💊💉🩸🧬🦠🧫🧪🌡️🧹🪠🧺🧻🚽🚰🚿🛁🛀🧼🪥🪒🧽🪣🧴🛎️🔑🗝️🚪🪑🛋️🛏️🛌🧸🪆🖼️🪞🪟🛍️🛒🎁🎈🎏🎀🪄🪅🎊🎉🎎🏮🎐🧧✉️📩📨📧💌📥📤📦🏷️🪧📪📫📬📭📮📯📜📃📄📑🧾📊📈📉🗒️🗓️📆📅🗑️📇🗃️🗳️🗄️📋📁📂🗂️🗞️📰📓📔📒📕📗📘📙📚📖🔖🧷🔗📎🖇️📐📏🧮📌📍✂️🖊️🖋️✒️🖌️🖍️📝✏️🔍🔎🔏🔐🔒🔓").map(String.init)),
        ("Symbols", "heart", Array("❤️🧡💛💚💙💜🖤🤍🤎💔❤️‍🔥❤️‍🩹❣️💕💞💓💗💖💘💝💟☮️✝️☪️🕉️☸️✡️🔯🕎☯️☦️🛐⛎♈♉♊♋♌♍♎♏♐♑♒♓🆔⚛️🉑☢️☣️📴📳🈶🈚🈸🈺🈷️✴️🆚💮🉐㊙️㊗️🈴🈵🈹🈲🅰️🅱️🆎🆑🅾️🆘❌⭕🛑⛔📛🚫💯💢♨️🚷🚯🚳🚱🔞📵🚭❗❕❓❔‼️⁉️🔅🔆〽️⚠️🚸🔱⚜️🔰♻️✅🈯💹❇️✳️❎🌐💠Ⓜ️🌀💤🏧🚾♿🅿️🛗🈳🈂️🛂🛃🛄🛅🚹🚺🚼⚧️🚻🚮🎦📶🈁🔣ℹ️🔤🔡🔠🆖🆗🆙🆒🆕🆓0️⃣1️⃣2️⃣3️⃣4️⃣5️⃣6️⃣7️⃣8️⃣9️⃣🔟🔢#️⃣*️⃣⏏️▶️⏸️⏯️⏹️⏺️⏭️⏮️⏩⏪⏫⏬◀️🔼🔽➡️⬅️⬆️⬇️↗️↘️↙️↖️↕️↔️↪️↩️⤴️⤵️🔀🔁🔂🔄🔃🎵🎶➕➖➗✖️♾️💲💱™️©️®️〰️➰➿🔚🔙🔛🔝🔜✔️☑️🔘🔴🟠🟡🟢🔵🟣⚫⚪🟤🔺🔻🔸🔹🔶🔷🔳🔲▪️▫️◾◽◼️◻️🟥🟧🟨🟩🟦🟪⬛⬜🟫🔈🔇🔉🔊🔔🔕📣📢💬💭🗯️♠️♣️♥️♦️🃏🎴🀄").map(String.init)),
        ("Flags", "flag", ["🇮🇳", "🏳️", "🏴", "🏁", "🚩", "🏳️‍🌈", "🏴‍☠️", "🇺🇸", "🇬🇧", "🇨🇦", "🇦🇺", "🇳🇿", "🇮🇪", "🇩🇪", "🇫🇷", "🇪🇸", "🇮🇹", "🇵🇹", "🇳🇱", "🇧🇪", "🇨🇭", "🇦🇹", "🇸🇪", "🇳🇴", "🇩🇰", "🇫🇮", "🇵🇱", "🇺🇦", "🇷🇺", "🇹🇷", "🇬🇷", "🇧🇷", "🇦🇷", "🇲🇽", "🇨🇴", "🇨🇱", "🇵🇪", "🇯🇵", "🇰🇷", "🇨🇳", "🇹🇼", "🇭🇰", "🇸🇬", "🇲🇾", "🇮🇩", "🇵🇭", "🇹🇭", "🇻🇳", "🇧🇩", "🇵🇰", "🇳🇵", "🇱🇰", "🇦🇪", "🇸🇦", "🇶🇦", "🇪🇬", "🇿🇦", "🇳🇬", "🇰🇪"]),
    ]

    static var recents: [String] {
        (UserDefaults.standard.string(forKey: recentKey) ?? "").components(separatedBy: "\u{1F}").filter { !$0.isEmpty }
    }

    static func used(_ emoji: String) {
        var list = recents.filter { $0 != emoji }
        list.insert(emoji, at: 0)
        UserDefaults.standard.set(list.prefix(32).joined(separator: "\u{1F}"), forKey: recentKey)
    }
}

/// The emoji page of Wyrm's keyboard.
struct WyrmEmojiPanel: View {
    @ObservedObject var controller: WyrmKeyboardController
    let keyHeight: CGFloat
    let height: CGFloat
    @State private var category = WyrmEmoji.recents.isEmpty ? 1 : 0
    @State private var recents = WyrmEmoji.recents

    private var list: [String] { category == 0 ? recents : WyrmEmoji.categories[category].emoji }

    var body: some View {
        VStack(spacing: 4) {
            Text(WyrmEmoji.categories[category].name.uppercased())
                .font(.androidWyrm(10, .bold)).tracking(0.8).foregroundColor(ATheme.quiet)
                .frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 12).padding(.top, 6)
            ScrollViewReader { reader in
                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHGrid(rows: Array(repeating: GridItem(.fixed(38), spacing: 2), count: 4), spacing: 2) {
                        ForEach(Array(list.enumerated()), id: \.offset) { _, emoji in
                            Button {
                                controller.insert(emoji)
                                WyrmEmoji.used(emoji)
                                UIDevice.current.playInputClick()
                            } label: {
                                Text(emoji).font(.system(size: 29)).frame(width: 40, height: 38)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 8)
                    .id(category)
                }
                .onChange(of: category) { _ in reader.scrollTo(category, anchor: .leading) }
            }
            .frame(maxHeight: .infinity)
            HStack(spacing: 0) {
                WyrmSpecialKey(text: "ABC", width: 52, height: keyHeight * 0.82) { controller.layout = .letters }
                ForEach(WyrmEmoji.categories.indices, id: \.self) { index in
                    Button {
                        UISelectionFeedbackGenerator().selectionChanged()
                        if index == 0 { recents = WyrmEmoji.recents }
                        category = index
                    } label: {
                        Image(systemName: WyrmEmoji.categories[index].symbol)
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(category == index ? ATheme.ink : ATheme.quiet)
                            .frame(maxWidth: .infinity).frame(height: keyHeight * 0.82)
                            .background(Circle().fill(category == index ? ATheme.well : Color.clear).frame(width: 30, height: 30))
                    }
                    .buttonStyle(.plain)
                }
                WyrmSpecialKey(symbol: "delete.left", width: 52, height: keyHeight * 0.82, repeats: true) { controller.deleteBackward() }
            }
            .padding(.horizontal, 3).padding(.bottom, 2)
        }
        .frame(height: height)
    }
}
