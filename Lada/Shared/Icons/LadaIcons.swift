import SwiftUI

/// Centralized Technical Nordic thin-outline vector icon family for Låda.
public enum LadaIconKind: String, CaseIterable, Sendable {
    case appIdentity
    case overview
    case containers
    case stacks
    case images
    case imageLibrary
    case dockerfileEditor
    case builds
    case networks
    case volumes
    case machines
    case registries
    case runtimeHealth
    case setupDiagnostics
    case activity
    case settings
}

public struct LadaIcon: View {
    public let kind: LadaIconKind
    public var size: CGFloat
    public var strokeWidth: CGFloat

    public init(_ kind: LadaIconKind, size: CGFloat = 16, strokeWidth: CGFloat = 1.45) {
        self.kind = kind
        self.size = size
        self.strokeWidth = strokeWidth
    }

    public var body: some View {
        Canvas { context, canvasSize in
            let w = canvasSize.width
            let h = canvasSize.height
            let pad = strokeWidth
            let rect = CGRect(x: pad, y: pad, width: max(1, w - pad * 2), height: max(1, h - pad * 2))
            let style = StrokeStyle(lineWidth: strokeWidth, lineCap: .round, lineJoin: .round)

            var path = Path()
            switch kind {
            case .appIdentity:
                // Nordic precision crate ("Låda" = drawer/box in Swedish)
                let r = min(rect.width, rect.height) * 0.14
                path.addRoundedRect(in: rect, cornerSize: CGSize(width: r, height: r))
                let midY = rect.minY + rect.height * 0.42
                path.move(to: CGPoint(x: rect.minX, y: midY))
                path.addLine(to: CGPoint(x: rect.maxX, y: midY))
                // Drawer handle / technical slot
                let slotW = rect.width * 0.34
                path.move(to: CGPoint(x: rect.midX - slotW / 2, y: rect.minY + rect.height * 0.70))
                path.addLine(to: CGPoint(x: rect.midX + slotW / 2, y: rect.minY + rect.height * 0.70))
                // Top compartment divider
                path.move(to: CGPoint(x: rect.midX, y: rect.minY))
                path.addLine(to: CGPoint(x: rect.midX, y: midY))

            case .overview:
                // 4-pane asymmetric Nordic instrument grid
                let gap = rect.width * 0.12
                let halfW = (rect.width - gap) / 2
                let halfH = (rect.height - gap) / 2
                path.addRect(CGRect(x: rect.minX, y: rect.minY, width: halfW, height: halfH))
                path.addRect(CGRect(x: rect.minX + halfW + gap, y: rect.minY, width: halfW, height: halfH))
                path.addRect(CGRect(x: rect.minX, y: rect.minY + halfH + gap, width: halfW, height: halfH))
                path.addRect(CGRect(x: rect.minX + halfW + gap, y: rect.minY + halfH + gap, width: halfW, height: halfH))

            case .containers:
                // Isometric technical cube with vertical ribs
                let cx = rect.midX
                let topY = rect.minY
                let botY = rect.maxY
                let upperY = rect.minY + rect.height * 0.27
                let lowerY = rect.maxY - rect.height * 0.27
                // Outer hexagon
                path.move(to: CGPoint(x: cx, y: topY))
                path.addLine(to: CGPoint(x: rect.maxX, y: upperY))
                path.addLine(to: CGPoint(x: rect.maxX, y: lowerY))
                path.addLine(to: CGPoint(x: cx, y: botY))
                path.addLine(to: CGPoint(x: rect.minX, y: lowerY))
                path.addLine(to: CGPoint(x: rect.minX, y: upperY))
                path.closeSubpath()
                // Inner Y seams
                let center = CGPoint(x: cx, y: rect.midY)
                path.move(to: CGPoint(x: rect.minX, y: upperY))
                path.addLine(to: center)
                path.addLine(to: CGPoint(x: rect.maxX, y: upperY))
                path.move(to: center)
                path.addLine(to: CGPoint(x: cx, y: botY))

            case .images:
                // Stacked OCI manifest layers (3 diamond planes)
                let cx = rect.midX
                let layerH = rect.height * 0.26
                for (index, yOffset) in [0.0, 0.28, 0.56].enumerated() {
                    let top = rect.minY + rect.height * yOffset
                    let mid = top + layerH
                    let bot = top + layerH * 2
                    if index == 0 {
                        path.move(to: CGPoint(x: cx, y: top))
                        path.addLine(to: CGPoint(x: rect.maxX, y: mid))
                        path.addLine(to: CGPoint(x: cx, y: bot))
                        path.addLine(to: CGPoint(x: rect.minX, y: mid))
                        path.closeSubpath()
                    } else {
                        path.move(to: CGPoint(x: rect.minX, y: mid))
                        path.addLine(to: CGPoint(x: cx, y: bot))
                        path.addLine(to: CGPoint(x: rect.maxX, y: mid))
                    }
                }

            case .builds:
                // Blueprint frame with assembly arrow / crane
                let box = CGRect(x: rect.minX, y: rect.minY + rect.height * 0.34, width: rect.width, height: rect.height * 0.66)
                path.addRect(box)
                path.move(to: CGPoint(x: box.minX, y: box.midY))
                path.addLine(to: CGPoint(x: box.maxX, y: box.midY))
                // Top downward build indicator
                path.move(to: CGPoint(x: rect.midX, y: rect.minY))
                path.addLine(to: CGPoint(x: rect.midX, y: box.minY - 1))
                path.move(to: CGPoint(x: rect.midX - rect.width * 0.18, y: box.minY - rect.height * 0.14))
                path.addLine(to: CGPoint(x: rect.midX, y: box.minY - 1))
                path.addLine(to: CGPoint(x: rect.midX + rect.width * 0.18, y: box.minY - rect.height * 0.14))

            case .networks:
                // Three topology nodes with bridge links
                let r = rect.width * 0.15
                let topCenter = CGPoint(x: rect.midX, y: rect.minY + r)
                let leftCenter = CGPoint(x: rect.minX + r, y: rect.maxY - r)
                let rightCenter = CGPoint(x: rect.maxX - r, y: rect.maxY - r)
                path.addEllipse(in: CGRect(x: topCenter.x - r, y: topCenter.y - r, width: r * 2, height: r * 2))
                path.addEllipse(in: CGRect(x: leftCenter.x - r, y: leftCenter.y - r, width: r * 2, height: r * 2))
                path.addEllipse(in: CGRect(x: rightCenter.x - r, y: rightCenter.y - r, width: r * 2, height: r * 2))
                path.move(to: CGPoint(x: topCenter.x - r * 0.6, y: topCenter.y + r * 0.8))
                path.addLine(to: CGPoint(x: leftCenter.x + r * 0.5, y: leftCenter.y - r * 0.8))
                path.move(to: CGPoint(x: topCenter.x + r * 0.6, y: topCenter.y + r * 0.8))
                path.addLine(to: CGPoint(x: rightCenter.x - r * 0.5, y: rightCenter.y - r * 0.8))
                path.move(to: CGPoint(x: leftCenter.x + r, y: leftCenter.y))
                path.addLine(to: CGPoint(x: rightCenter.x - r, y: rightCenter.y))

            case .volumes:
                // Persistent storage cylinder (ext4 sparse disk)
                let ellipseH = rect.height * 0.28
                let topEllipse = CGRect(x: rect.minX, y: rect.minY, width: rect.width, height: ellipseH)
                path.addEllipse(in: topEllipse)
                path.move(to: CGPoint(x: rect.minX, y: topEllipse.midY))
                path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY - ellipseH / 2))
                path.addArc(
                    center: CGPoint(x: rect.midX, y: rect.maxY - ellipseH / 2),
                    radius: rect.width / 2,
                    startAngle: .degrees(180),
                    endAngle: .degrees(0),
                    clockwise: true
                )
                path.addLine(to: CGPoint(x: rect.maxX, y: topEllipse.midY))
                // Mid band
                let midY = rect.midY + ellipseH * 0.1
                path.move(to: CGPoint(x: rect.minX, y: midY))
                path.addQuadCurve(
                    to: CGPoint(x: rect.maxX, y: midY),
                    control: CGPoint(x: rect.midX, y: midY + ellipseH * 0.55)
                )

            case .machines:
                // Linux environment machine chassis with `>_` shell prompt
                let r = rect.width * 0.12
                let screenRect = CGRect(x: rect.minX, y: rect.minY, width: rect.width, height: rect.height * 0.76)
                path.addRoundedRect(in: screenRect, cornerSize: CGSize(width: r, height: r))
                // Prompt `>_`
                let px = screenRect.minX + screenRect.width * 0.24
                let py = screenRect.minY + screenRect.height * 0.34
                path.move(to: CGPoint(x: px, y: py))
                path.addLine(to: CGPoint(x: px + screenRect.width * 0.16, y: screenRect.midY))
                path.addLine(to: CGPoint(x: px, y: screenRect.maxY - screenRect.height * 0.30))
                path.move(to: CGPoint(x: screenRect.midX, y: screenRect.maxY - screenRect.height * 0.30))
                path.addLine(to: CGPoint(x: screenRect.maxX - screenRect.width * 0.22, y: screenRect.maxY - screenRect.height * 0.30))
                // Base stand
                path.move(to: CGPoint(x: rect.midX - rect.width * 0.28, y: rect.maxY))
                path.addLine(to: CGPoint(x: rect.midX + rect.width * 0.28, y: rect.maxY))
                path.move(to: CGPoint(x: rect.midX, y: screenRect.maxY))
                path.addLine(to: CGPoint(x: rect.midX, y: rect.maxY))

            case .registries:
                // Distribution vault / cloud-arch with upward/downward sync line
                let topArch = CGRect(x: rect.minX + rect.width * 0.1, y: rect.minY, width: rect.width * 0.8, height: rect.height * 0.5)
                path.addRoundedRect(in: topArch, cornerSize: CGSize(width: 2, height: 2))
                let botArch = CGRect(x: rect.minX, y: rect.midY + 1, width: rect.width, height: rect.height * 0.45)
                path.addRoundedRect(in: botArch, cornerSize: CGSize(width: 2, height: 2))
                // Indicator dots
                path.move(to: CGPoint(x: topArch.minX + 3, y: topArch.midY))
                path.addLine(to: CGPoint(x: topArch.minX + 4, y: topArch.midY))
                path.move(to: CGPoint(x: botArch.minX + 3, y: botArch.midY))
                path.addLine(to: CGPoint(x: botArch.minX + 4, y: botArch.midY))

            case .runtimeHealth:
                // Precision pulse line inside rounded frame
                let r = rect.width * 0.15
                path.addRoundedRect(in: rect, cornerSize: CGSize(width: r, height: r))
                let y = rect.midY
                path.move(to: CGPoint(x: rect.minX + rect.width * 0.12, y: y))
                path.addLine(to: CGPoint(x: rect.minX + rect.width * 0.32, y: y))
                path.addLine(to: CGPoint(x: rect.minX + rect.width * 0.44, y: rect.minY + rect.height * 0.24))
                path.addLine(to: CGPoint(x: rect.minX + rect.width * 0.58, y: rect.maxY - rect.height * 0.24))
                path.addLine(to: CGPoint(x: rect.minX + rect.width * 0.68, y: y))
                path.addLine(to: CGPoint(x: rect.maxX - rect.width * 0.12, y: y))

            case .setupDiagnostics:
                // Shield / checklist badge
                path.move(to: CGPoint(x: rect.midX, y: rect.minY))
                path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY + rect.height * 0.22))
                path.addLine(to: CGPoint(x: rect.maxX, y: rect.midY + rect.height * 0.1))
                path.addQuadCurve(to: CGPoint(x: rect.midX, y: rect.maxY), control: CGPoint(x: rect.maxX, y: rect.maxY - 2))
                path.addQuadCurve(to: CGPoint(x: rect.minX, y: rect.midY + rect.height * 0.1), control: CGPoint(x: rect.minX, y: rect.maxY - 2))
                path.addLine(to: CGPoint(x: rect.minX, y: rect.minY + rect.height * 0.22))
                path.closeSubpath()
                // Checkmark inside
                path.move(to: CGPoint(x: rect.minX + rect.width * 0.30, y: rect.midY))
                path.addLine(to: CGPoint(x: rect.midX - rect.width * 0.04, y: rect.midY + rect.height * 0.16))
                path.addLine(to: CGPoint(x: rect.maxX - rect.width * 0.26, y: rect.midY - rect.height * 0.14))

            case .activity:
                // Timeline list lines
                for factor in [0.22, 0.50, 0.78] {
                    let y = rect.minY + rect.height * factor
                    path.move(to: CGPoint(x: rect.minX, y: y))
                    path.addLine(to: CGPoint(x: rect.minX + 1.5, y: y))
                    path.move(to: CGPoint(x: rect.minX + rect.width * 0.28, y: y))
                    path.addLine(to: CGPoint(x: rect.maxX, y: y))
                }

            case .imageLibrary:
                // Globe / catalog grid representing Docker Hub repository library
                path.addEllipse(in: rect)
                path.move(to: CGPoint(x: rect.minX, y: rect.midY))
                path.addLine(to: CGPoint(x: rect.maxX, y: rect.midY))
                path.move(to: CGPoint(x: rect.midX, y: rect.minY))
                path.addLine(to: CGPoint(x: rect.midX, y: rect.maxY))
                let meridianRect = CGRect(
                    x: rect.minX + rect.width * 0.24,
                    y: rect.minY,
                    width: rect.width * 0.52,
                    height: rect.height
                )
                path.addEllipse(in: meridianRect)

            case .dockerfileEditor:
                // Technical document with code brackets `< >`
                let docRect = CGRect(x: rect.minX + 1, y: rect.minY, width: rect.width - 2, height: rect.height)
                path.addRoundedRect(in: docRect, cornerSize: CGSize(width: 2, height: 2))
                // Left chevron `<`
                path.move(to: CGPoint(x: docRect.midX - 1.5, y: docRect.midY - 3))
                path.addLine(to: CGPoint(x: docRect.minX + 3, y: docRect.midY))
                path.addLine(to: CGPoint(x: docRect.midX - 1.5, y: docRect.midY + 3))
                // Right chevron `>`
                path.move(to: CGPoint(x: docRect.midX + 1.5, y: docRect.midY - 3))
                path.addLine(to: CGPoint(x: docRect.maxX - 3, y: docRect.midY))
                path.addLine(to: CGPoint(x: docRect.midX + 1.5, y: docRect.midY + 3))

            case .stacks:
                // Multi-container stack blocks connected vertically
                let hBox = rect.height * 0.25
                for idx in 0..<3 {
                    let y = rect.minY + CGFloat(idx) * (hBox + rect.height * 0.12)
                    let box = CGRect(x: rect.minX + 1, y: y, width: rect.width - 2, height: hBox)
                    path.addRoundedRect(in: box, cornerSize: CGSize(width: 1.5, height: 1.5))
                }

            case .settings:
                // Sliders / tuning controls
                for (idx, factor) in [0.25, 0.50, 0.75].enumerated() {
                    let y = rect.minY + rect.height * factor
                    path.move(to: CGPoint(x: rect.minX, y: y))
                    path.addLine(to: CGPoint(x: rect.maxX, y: y))
                    let knobX = idx == 1 ? rect.minX + rect.width * 0.68 : rect.minX + rect.width * 0.32
                    path.move(to: CGPoint(x: knobX, y: y - 2.2))
                    path.addLine(to: CGPoint(x: knobX, y: y + 2.2))
                }
            }

            context.stroke(path, with: .foreground, style: style)
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}
