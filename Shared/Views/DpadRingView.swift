import PaneKit
import SwiftUI

/// The ring d-pad (mockups/2026-11-21-finition, piste C): four quarter rings around the OK disc, each
/// a key of its own, made by `key` from its part, its shape and the point its key tiles go by (its
/// chevron's top right corner: the square's falls out of the ring), all five laid in one `diameter`
/// square. The shape is the key's face, its chosen edge and its pressed fill, and all it can be
/// clicked, right-clicked (Mac) or found by VoiceOver in: the square's corners, out of the circle, are
/// no key's. The view draws, under the keys, the only lines: the outer circle at `line`, OK's a little
/// stronger, none between the directions; in iOS's light theme, a white plate under all five, their
/// own faces left clear so that no seam shows between them. On the Mac, the part under the pointer
/// lights up, and no other. VoiceOver reads up, left, OK, right, down.
struct DpadRingView<Key: View>: View {
    let diameter: CGFloat
    private let key: (RingPart, AnyShape, CGPoint) -> Key
    @Environment(\.palette) private var palette
    @Environment(\.isEnabled) private var isEnabled
    /// The part under the pointer (Mac).
    @State private var hovered: RingPart?

    init(diameter: CGFloat, @ViewBuilder key: @escaping (RingPart, AnyShape, CGPoint) -> Key) {
        self.diameter = diameter
        self.key = key
    }

    var body: some View {
        let ring = DpadRing(diameter: diameter)
        ZStack {
            // OK last, on top: its edge's half pixel over the directions' inner edge is OK's.
            ForEach(RingPart.allCases, id: \.self) { part in
                let shape = AnyShape(RingPartShape(part: part))
                key(part, shape, tileAnchor(part, ring))
                    .contentShape(.accessibility, shape)
                    .accessibilitySortPriority(part.readingPriority)
                    .environment(\.keyHover, hovered == part)
            }
            .environment(\.palette, palette.ringKeys)
        }
        // VoiceOver reads the parts as the cross did, not in the drawing order.
        .accessibilityElement(children: .contain)
        .frame(width: diameter, height: diameter)
        .background { plate(ring) }
        #if os(macOS)
        .onContinuousHover { phase in
            switch phase {
            case .active(let location): hovered = ring.part(at: location)
            case .ended: hovered = nil
            }
        }
        #endif
    }

    /// The plate, the part under the pointer and the two circles, under the keys and their edges.
    private func plate(_ ring: DpadRing) -> some View {
        ZStack {
            Circle().fill(palette.key)
            if isEnabled, let hovered {
                RingPartShape(part: hovered).fill(palette.fg.opacity(0.04))
            }
            Circle().strokeBorder(palette.line, lineWidth: 1)
            Circle().strokeBorder(palette.fg.opacity(palette.lineOpacity * 1.6), lineWidth: 1)
                .frame(width: ring.okRadius * 2, height: ring.okRadius * 2)
        }
        // Greyed with the keys.
        .opacity(isEnabled ? 1 : 0.35)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    /// The top right corner of the part's chevron, or of the square inscribed in OK's disc.
    private func tileAnchor(_ part: RingPart, _ ring: DpadRing) -> CGPoint {
        let center = ring.iconCenter(part)
        let half = part == .ok ? ring.okRadius / 2.squareRoot() : Metrics.ringArrowIcon / 2
        return CGPoint(x: center.x + half, y: center.y - half)
    }
}

private extension RingPart {
    /// Its place in VoiceOver's reading, highest first: up, left, OK, right, down, as the cross read.
    var readingPriority: Double {
        switch self {
        case .up: 5
        case .left: 4
        case .ok: 3
        case .right: 2
        case .down: 1
        }
    }
}

/// A part of the ring d-pad as a shape: its outline from `DpadRing`, for a ring as wide as the
/// rect's shorter side, centred in it.
struct RingPartShape: Shape {
    let part: RingPart

    func path(in rect: CGRect) -> Path {
        let side = min(rect.width, rect.height)
        return Path(DpadRing(diameter: side).path(part))
            .offsetBy(dx: rect.midX - side / 2, dy: rect.midY - side / 2)
    }
}
