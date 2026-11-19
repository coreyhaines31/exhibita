import ExhibitEditor
import SwiftUI

/// The mark on a toolbar key, in the key's one ink. An SF Symbol where one draws the mark exactly; drawn shapes for
/// blur (a mosaic) and blur secrets (a password field's dots), which no symbol shows.
enum KeyIcon: Equatable {
    case symbol(String)
    /// Blur: a 3 by 3 checker of squares, how a pixelated region reads at a glance.
    case mosaic
    /// Blur secrets: three dots in a field, as a password reads.
    case secret

    static func tool(_ tool: EditorTool) -> KeyIcon {
        switch tool {
        case .select: .symbol("cursorarrow")
        case .arrow: .symbol("arrow.up.right")
        case .circle: .symbol("circle")
        case .blur: .mosaic
        case .highlight: .symbol("highlighter")
        case .text: .symbol("character.cursor.ibeam")
        case .box: .symbol("rectangle")
        case .step: .symbol("1.circle")
        }
    }

    static let dictate = KeyIcon.symbol("mic")
    static let type = KeyIcon.symbol("keyboard")
    static let blurSecrets = KeyIcon.secret
}

/// Draws a `KeyIcon` at `size` points square, in the foreground style.
struct KeyIconView: View {
    let icon: KeyIcon
    var size: CGFloat = 13

    var body: some View {
        switch icon {
        case .symbol(let name):
            Image(systemName: name)
                .font(.system(size: size * 0.92, weight: .semibold))
                .frame(width: size, height: size)
        case .mosaic:
            Mosaic().frame(width: size * 0.84, height: size * 0.84).frame(width: size, height: size)
        case .secret:
            SecretField().frame(width: size * 1.15, height: size * 0.62).frame(width: size, height: size)
        }
    }
}

/// Alternate squares of a 3 by 3 grid, one ink, no steps of opacity.
private struct Mosaic: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let cell = min(rect.width, rect.height) / 3
        for row in 0..<3 {
            for column in 0..<3 where (row + column).isMultiple(of: 2) {
                path.addRect(CGRect(x: rect.minX + CGFloat(column) * cell, y: rect.minY + CGFloat(row) * cell,
                                    width: cell, height: cell))
            }
        }
        return path
    }
}

/// A rounded field outline with three dots inside.
private struct SecretField: View {
    var body: some View {
        GeometryReader { proxy in
            let height = proxy.size.height
            let dot = height * 0.32
            ZStack {
                RoundedRectangle(cornerRadius: height * 0.28)
                    .strokeBorder(lineWidth: max(1.2, height * 0.13))
                HStack(spacing: dot * 0.55) {
                    ForEach(0..<3, id: \.self) { _ in Circle().frame(width: dot, height: dot) }
                }
            }
        }
    }
}
