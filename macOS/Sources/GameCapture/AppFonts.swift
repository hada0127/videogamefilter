import SwiftUI
import CoreText

enum AppFonts {
    private static let regular = load("HadaSans-Regular")
    private static let semibold = load("HadaSans-SemiBold")
    private static func load(_ name: String) -> NSFont {
        let size: CGFloat = 16
        guard let url = Bundle.module.url(forResource: name, withExtension: "otf"),
              let descriptors = CTFontManagerCreateFontDescriptorsFromURL(url as CFURL) as? [CTFontDescriptor],
              let descriptor = descriptors.first else { return NSFont.systemFont(ofSize: size) }
        return CTFontCreateWithFontDescriptor(descriptor, size, nil) as NSFont
    }
    static func native(_ size: CGFloat, bold: Bool = false) -> NSFont {
        CTFontCreateCopyWithAttributes(bold ? semibold : regular, size, nil, nil) as NSFont
    }
    static func font(_ size: CGFloat, bold: Bool = false) -> Font { Font(native(size, bold: bold)) }
}
