//
//  Colours.swift
//  Enchanted
//
//  Created by Augustinas Malinauskas on 09/12/2023.
//
//  CLT build: the asset catalog cannot be compiled without Xcode's actool, so
//  the palette is reconstructed from the Colors/*.colorset definitions here.
//  Values match Contents.json (display-p3 / extended-srgb / system references).
//

import SwiftUI
#if canImport(AppKit)
import AppKit
#else
import UIKit
#endif

// MARK: - Palette
extension Color {
    static let labelCustom = Color(nsColor: .labelColor)

    static let bgCustom = Color(nsColor: NSColor(name: nil) { appearance in
        appearance.isDark ? NSColor.black : NSColor.white
    })

    static let grayCustom = Color(nsColor: NSColor(srgbRed: 0.557, green: 0.557, blue: 0.576, alpha: 1))

    static let gray2Custom = Color(nsColor: NSColor(name: nil) { appearance in
        appearance.isDark
            ? NSColor(srgbRed: 0.388, green: 0.388, blue: 0.400, alpha: 1)
            : NSColor(displayP3Red: 0.676, green: 0.697, blue: 0.679, alpha: 1)
    })

    static let gray3Custom = Color(nsColor: NSColor(name: nil) { appearance in
        appearance.isDark
            ? NSColor(srgbRed: 0.282, green: 0.282, blue: 0.290, alpha: 1)
            : NSColor(displayP3Red: 0.792, green: 0.790, blue: 0.814, alpha: 1)
    })

    static let gray4Custom = Color(nsColor: NSColor(name: nil) { appearance in
        appearance.isDark
            ? NSColor(srgbRed: 0.329, green: 0.329, blue: 0.337, alpha: 1)
            : NSColor(srgbRed: 0.820, green: 0.820, blue: 0.839, alpha: 1)
    })

    static let gray5Custom = Color(nsColor: NSColor(name: nil) { appearance in
        appearance.isDark
            ? NSColor(srgbRed: 0.173, green: 0.173, blue: 0.180, alpha: 1)
            : NSColor(srgbRed: 0.898, green: 0.898, blue: 0.918, alpha: 1)
    })
}

private extension NSAppearance {
    var isDark: Bool {
        bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
    }
}

// MARK: - hex
extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 3: // RGB (12-bit)
            (a, r, g, b) = (UInt64(255), (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6: // RGB (24-bit)
            (a, r, g, b) = (UInt64(255), int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8: // ARGB (32-bit)
            (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default:
            (a, r, g, b) = (1, 1, 1, 0)
        }

        self.init(
            .sRGB,
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue:  Double(b) / 255,
            opacity: Double(a) / 255
        )
    }
}
