import SwiftUI

struct RadarFace: View {
    // Scale the reference iPhone widget's outer frame and its cards together.
    static let width: CGFloat = 378
    static let height: CGFloat = 176
    static let casing = Color(radarRGB: 0x111917)
    let snapshot: RadarSnapshot?
    var tinted = false

    var body: some View {
        GeometryReader { geometry in
            let scale = min(geometry.size.width / Self.width, geometry.size.height / Self.height)
            face
                .frame(width: Self.width, height: Self.height)
                .scaleEffect(scale)
                .position(x: geometry.size.width / 2, y: geometry.size.height / 2)
        }
    }

    private var face: some View {
        VStack(spacing: 0) {
            HStack {
                RadarWordmark()
                    .accessibilityLabel("Codex Radar")
                Spacer()
                if let fetchedAt = snapshot?.fetchedAt {
                    Text(RadarData.timestamp(fetchedAt))
                        .font(.system(size: 10, weight: .medium, design: .monospaced))
                        .foregroundStyle(Color(radarRGB: 0xBDD0C1))
                        .monospacedDigit()
                        .accessibilityLabel("上次取数 \(RadarData.timestamp(fetchedAt))")
                }
            }
            .frame(height: 18)
            .padding(.horizontal, 22)
            .padding(.top, 9)
            .padding(.bottom, 5)

            if let snapshot {
                VStack(spacing: 6) {
                    ForEach(0..<2) { row in
                        HStack(spacing: 8) {
                            ForEach(0..<2) { column in
                                let index = row * 2 + column
                                RadarTile(
                                    leader: index < snapshot.leaders.count ? snapshot.leaders[index] : nil,
                                    leading: index == 0,
                                    tinted: tinted
                                )
                            }
                        }
                    }
                }
            } else {
                Text("暂时取不到榜单")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Color(radarRGB: 0xE9F0E8))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            Spacer(minLength: 0)
        }
    }
}

private struct RadarTile: View {
    let leader: RadarLeader?
    let leading: Bool
    let tinted: Bool
    private var ink: Color { tinted ? .white : Color(radarRGB: 0x14251C) }
    private var secondaryInk: Color { tinted ? .white.opacity(0.82) : Color(radarRGB: 0x2D4437) }

    var body: some View {
        ZStack {
            if tinted {
                RoundedRectangle(cornerRadius: 9)
                    .strokeBorder(Color.white.opacity(leading ? 0.8 : 0.5), lineWidth: 1)
                    .overlay {
                        RoundedRectangle(cornerRadius: 7)
                            .strokeBorder(Color.white.opacity(0.26), lineWidth: 0.7)
                            .padding(2)
                    }
                    .accessibilityHidden(true)
            } else {
                RadarPanel(leading: leading)
                    .accessibilityHidden(true)
            }
            if let leader {
                VStack(spacing: 6) {
                    HStack(spacing: 4) {
                        Text(leader.model)
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(ink)
                        Spacer(minLength: 0)
                        Text(leader.effort)
                            .font(.system(size: 9, weight: .medium, design: .monospaced))
                            .foregroundStyle(secondaryInk)
                    }
                    HStack(alignment: .bottom, spacing: 3) {
                        RadarScore(value: leader.score, tinted: tinted)
                        Text("/150")
                            .font(.system(size: 8, weight: .medium, design: .monospaced))
                            .foregroundStyle(secondaryInk)
                        Spacer(minLength: 4)
                        Text(leader.cost)
                            .font(.system(size: 12, weight: .semibold, design: .monospaced))
                            .foregroundStyle(ink)
                    }
                }
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .padding(.horizontal, 9)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("\(leader.model)，\(leader.effort)，\(leader.score) 分，估算成本 \(leader.cost)")
            } else {
                Text("—")
                    .font(.system(size: 13, weight: .medium, design: .monospaced))
                    .foregroundStyle(secondaryInk)
                    .accessibilityHidden(true)
            }
        }
        .frame(width: 173, height: 62)
    }
}

private struct RadarPanel: View {
    let leading: Bool

    var body: some View {
        Canvas { context, size in
            let layers: [(CGFloat, UInt32)] = [
                (0, 0x53665C), (0.9, leading ? 0xD3E4B7 : 0xC4D4CA),
                (2.2, 0x4D6155), (3.4, leading ? 0xB1C498 : 0x9FB4A6)
            ]
            for (inset, color) in layers {
                let panel = CGRect(origin: .zero, size: size).insetBy(dx: inset, dy: inset)
                context.fill(Path(roundedRect: panel, cornerRadius: 9 - inset), with: .color(Color(radarRGB: color)))
            }
            for y in stride(from: CGFloat(8), to: size.height - 7, by: 2) {
                let line = CGRect(x: 6, y: y, width: size.width - 12, height: 0.35)
                context.fill(Path(line), with: .color(Color(radarRGB: 0x30463A).opacity(0.06)))
            }
        }
    }
}

private struct RadarWordmark: View {
    private typealias Stroke = (CGFloat, CGFloat, CGFloat, CGFloat)
    private static let glyphs: [Character: (width: CGFloat, strokes: [Stroke])] = [
        "C": (11, [(2.4, 1, 10, 1), (1, 2.5, 1, 11.5), (2.4, 13, 10, 13)]),
        "o": (9, [(2.3, 5, 6.7, 5), (8, 6.4, 8, 11.6), (6.7, 13, 2.3, 13), (1, 11.6, 1, 6.4)]),
        "d": (9, [(2.4, 5, 6.6, 5), (8, 1, 8, 12), (6.6, 13, 2.4, 13), (1, 11.6, 1, 6.4)]),
        "e": (9, [(2.4, 5, 6.6, 5), (8, 6.4, 8, 8.7), (6.7, 9, 2.3, 9), (1, 6.4, 1, 11.6), (2.3, 13, 7.8, 13)]),
        "x": (9, [(1, 5, 3.5, 7.9), (5.5, 10.1, 8, 13), (8, 5, 5.5, 7.9), (3.5, 10.1, 1, 13)]),
        "R": (11, [(2.4, 1, 8.6, 1), (10, 2.5, 10, 6.5), (8.6, 8, 2.4, 8), (1, 2.5, 1, 13), (5.8, 9.5, 10, 13)]),
        "a": (9, [(1.9, 5, 6.7, 5), (8, 6.4, 8, 12), (6.7, 13, 2.3, 13), (1, 11.6, 1, 10.3), (2.3, 9, 6.7, 9)]),
        "r": (7, [(1, 5.9, 1, 13), (2.4, 5, 6.1, 5)])
    ]

    var body: some View {
        Canvas { context, size in
            let scale: CGFloat = 0.82
            let top = (size.height - 16 * scale) / 2
            var x: CGFloat = 1
            var path = Path()
            for character in "Codex Radar" {
                guard let glyph = Self.glyphs[character] else {
                    x += 6.4
                    continue
                }
                for (x1, y1, x2, y2) in glyph.strokes {
                    path.move(to: CGPoint(x: (x + x1) * scale, y: top + (1 + y1) * scale))
                    path.addLine(to: CGPoint(x: (x + x2) * scale, y: top + (1 + y2) * scale))
                }
                x += glyph.width + 1.45
            }
            context.stroke(path, with: .color(Color(radarRGB: 0xDCEADD)), lineWidth: 1.85 * scale)
        }
        .frame(width: 96, height: 18)
    }
}

private struct RadarScore: View {
    let value: String
    let tinted: Bool
    private var ink: Color { tinted ? .white : Color(radarRGB: 0x14251C) }
    private var inactive: Color { tinted ? .white.opacity(0.11) : Color(radarRGB: 0x253A2C).opacity(0.11) }
    private static let digits = ["abcdef", "bc", "abdeg", "abcdg", "bcfg", "acdfg", "acdefg", "abc", "abcdefg", "abcdfg"]
    private static let polygons: [(Character, [CGPoint])] = [
        ("a", horizontal(0)), ("b", vertical(9.5, 1.7)),
        ("c", vertical(9.5, 11.7)), ("d", horizontal(19.1)),
        ("e", vertical(0, 11.7)), ("f", vertical(0, 1.7)),
        ("g", horizontal(9.55))
    ]

    var body: some View {
        if RadarData.validLCDScore(value) && value.count <= 9 {
            let width = value.reduce(CGFloat(0)) { $0 + ($1 == "." ? 5.5 : 14) }
            let scale = min(1, 77 / width)
            Canvas { context, size in
                let baseline = size.height - 22 * scale
                var x: CGFloat = 0
                for character in value {
                    if character == "." {
                        let dot = CGRect(x: x * scale, y: baseline + 19 * scale, width: 2.3 * scale, height: 2.3 * scale)
                        context.fill(Path(dot), with: .color(ink))
                        x += 5.5
                    } else if let digit = character.wholeNumberValue, Self.digits.indices.contains(digit) {
                        let active = Self.digits[digit]
                        for (name, points) in Self.polygons {
                            var path = Path()
                            path.addLines(points.map { CGPoint(x: (x + $0.x) * scale, y: baseline + $0.y * scale) })
                            path.closeSubpath()
                            context.fill(path, with: .color(active.contains(name) ? ink : inactive))
                        }
                        x += 14
                    }
                }
            }
            .frame(width: ceil(width * scale), height: 22)
        } else {
            Text(value)
                .font(.system(size: 19, weight: .medium, design: .monospaced))
                .foregroundStyle(ink)
                .lineLimit(1)
                .minimumScaleFactor(0.55)
        }
    }

    private static func horizontal(_ y: CGFloat) -> [CGPoint] {
        [(2, y), (9.2, y), (10.4, y + 1.2), (9.2, y + 2.4), (2, y + 2.4), (0.8, y + 1.2)]
            .map { CGPoint(x: $0.0, y: $0.1) }
    }

    private static func vertical(_ x: CGFloat, _ y: CGFloat) -> [CGPoint] {
        [(x, y + 1.2), (x + 1.2, y), (x + 2.4, y + 1.2),
         (x + 2.4, y + 6.2), (x + 1.2, y + 7.4), (x, y + 6.2)]
            .map { CGPoint(x: $0.0, y: $0.1) }
    }
}

private extension Color {
    init(radarRGB: UInt32) {
        self.init(red: Double((radarRGB >> 16) & 255) / 255,
                  green: Double((radarRGB >> 8) & 255) / 255,
                  blue: Double(radarRGB & 255) / 255)
    }
}
