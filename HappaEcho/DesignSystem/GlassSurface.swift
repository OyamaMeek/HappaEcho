import SwiftUI
struct GlassSurface<Content: View>: View { @Environment(\.accessibilityReduceTransparency) private var reduce; @ViewBuilder var content: Content; var body: some View { content.padding(12).background(reduce ? AnyShapeStyle(Color.happaSurface) : AnyShapeStyle(.ultraThinMaterial), in: RoundedRectangle(cornerRadius: 16, style: .continuous)) } }
