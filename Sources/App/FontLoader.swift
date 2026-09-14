import CoreText
import Foundation

enum FontLoader {
    static func registerBundledFonts() {
        guard let url = Bundle.main.url(forResource: "manrope", withExtension: "ttf") else {
            return
        }
        CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
    }
}

