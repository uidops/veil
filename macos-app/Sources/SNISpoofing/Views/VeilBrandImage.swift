import SwiftUI
import AppKit

/// Loads `Veil.png` from the SwiftPM resource bundle (not `Bundle.main` image assets).
struct VeilBrandImage: View {
    var size: CGFloat = 36
    var cornerRadius: CGFloat = 10

    var body: some View {
        Group {
            if let img = Self.loadNSImage() {
                Image(nsImage: img)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
            } else {
                Image(systemName: "eye.fill")
                    .font(.system(size: size * 0.55, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
    }

    private static func loadNSImage() -> NSImage? {
        // Veil.app: build script copies Veil.png into Contents/Resources (flat).
        if let url = Bundle.main.url(forResource: "Veil", withExtension: "png"),
           let img = NSImage(contentsOf: url) {
            return img
        }
        if let url = Bundle.module.url(forResource: "Veil", withExtension: "png"),
           let img = NSImage(contentsOf: url) {
            return img
        }
        if let bundles = Bundle.main.urls(forResourcesWithExtension: "bundle", subdirectory: nil) {
            for b in bundles {
                let u = b.appendingPathComponent("Veil.png")
                if let img = NSImage(contentsOf: u) { return img }
            }
        }
        return nil
    }
}
