import ExhibitEditor
import SwiftUI

/// The mark on a toolbar key, in the key's one ink. An SF Symbol where one draws the mark exactly; a drawn shape for
/// blur (a mosaic), which no symbol shows.
enum KeyIcon: Equatable {
    case symbol(String)
    /// Blur: a 3 by 3 checker of squares, how a pixelated region reads at a glance.
    case mosaic

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
