import SwiftUI

/// Node Graph's state, kept in `AppState` so an arrangement survives leaving the page.
@MainActor
public final class NodeGraphState: ObservableObject {
    @Published var layout: GraphLayout = .force
    @Published var positions: [String: CGPoint] = [:]
    /// Nodes the user dragged keep their place when the graph changes.
    @Published var pinned: Set<String> = []
    @Published var hiddenKinds: Set<ResourceGraph.Kind> = []
    @Published var selectedID: String?
    @Published var zoom: CGFloat = 1
    @Published var pan: CGSize = .zero
    var laidOutIDs: Set<String> = []
    var worldSize: CGSize = .zero

    // Built once per inventory change (and per type filter), not on every hover or drag frame.
    private var cachedSignature: Int?
    private var cachedFull = ResourceGraph()
    private var cachedFilterKey: Set<ResourceGraph.Kind>?
    private var cachedShown = ResourceGraph()
    private(set) var adjacency: [String: Set<String>] = [:]

    public init() {}

    /// The full graph and the shown (filtered) one for the current inventories.
    func graphs(for appState: AppState) -> (full: ResourceGraph, shown: ResourceGraph) {
        var hasher = Hasher()
        for c in appState.containers {
            hasher.combine(c.id); hasher.combine(c.state.rawValue); hasher.combine(c.imageReference)
            hasher.combine(c.networks.map(\.ipv4Address)); hasher.combine(c.configuration.mounts.map(\.source))
            hasher.combine(c.configuration.publishedPorts.map(\.hostPort))
        }
        for i in appState.images { hasher.combine(i.id) }
        for n in appState.networks { hasher.combine(n.id); hasher.combine(n.ipv4Subnet) }
        for v in appState.volumes { hasher.combine(v.id) }
        for m in appState.machines { hasher.combine(m.id); hasher.combine(m.status.rawValue); hasher.combine(m.ipAddress) }
        for r in appState.registries { hasher.combine(r.hostname); hasher.combine(r.isAuthenticated) }
        let signature = hasher.finalize()
        if signature != cachedSignature {
            cachedSignature = signature
            cachedFull = ResourceGraph.build(containers: appState.containers, images: appState.images, networks: appState.networks,
                                             volumes: appState.volumes, machines: appState.machines, registries: appState.registries)
            cachedFilterKey = nil
        }
        if cachedFilterKey != hiddenKinds {
            cachedFilterKey = hiddenKinds
            cachedShown = cachedFull.filtered(to: Set(ResourceGraph.Kind.allCases).subtracting(hiddenKinds))
            var adj: [String: Set<String>] = [:]
            for e in cachedShown.edges {
                adj[e.from, default: []].insert(e.to)
                adj[e.to, default: []].insert(e.from)
            }
            adjacency = adj
        }
        return (cachedFull, cachedShown)
    }

    /// Lays out `graph`. With `keepPinned`, dragged nodes stay where they are.
    func arrange(_ graph: ResourceGraph, viewport: CGSize, keepPinned: Bool) {
        let n = CGFloat(max(1, graph.nodes.count))
        // Room grows with the number of nodes so chips don't pile up.
        worldSize = CGSize(width: max(viewport.width, sqrt(n) * 230), height: max(viewport.height, sqrt(n) * 150))
        var fresh = layout.positions(for: graph, in: worldSize, focus: selectedID)
        if keepPinned {
            for id in pinned { if let p = positions[id], fresh[id] != nil { fresh[id] = p } }
        } else {
            pinned = []
        }
        positions = fresh
        laidOutIDs = Set(graph.nodes.map(\.id))
    }

    func fit(viewport: CGSize) {
        guard worldSize.width > 0, worldSize.height > 0 else { return }
        zoom = min(1.4, max(0.3, min(viewport.width / worldSize.width, viewport.height / worldSize.height)))
        pan = CGSize(width: (viewport.width - worldSize.width * zoom) / 2, height: (viewport.height - worldSize.height * zoom) / 2)
    }
}

/// Every resource as a node, connected by how they relate. Nodes can be dragged, the whole graph
/// re-arranged with a layout algorithm, and hovering a node shows its configuration.
public struct NodeGraphView: View {
    @ObservedObject var appState: AppState
    @ObservedObject private var state: NodeGraphState
    @State private var hoveredID: String?
    @State private var dragOrigin: CGPoint?
    @State private var panOrigin: CGSize?
    @State private var zoomOrigin: CGFloat?
    @State private var viewport: CGSize = .zero

    public init(appState: AppState) {
        self.appState = appState
        self.state = appState.nodeGraph
    }

    private var accent: Color { NordicTheme.accent(for: appState.preferences.accentThemeChoice) }

    public var body: some View {
        let (full, graph) = state.graphs(for: appState)
        VStack(spacing: 0) {
            header(full: full, shown: graph)
            GeometryReader { geo in
                ZStack(alignment: .topLeading) {
                    canvasBackground
                        .contentShape(Rectangle())
                        .gesture(panGesture)
                    edgesLayer(graph)
                        .allowsHitTesting(false)
                    ForEach(graph.nodes) { node in
                        nodeChip(node)
                    }
                    if let id = state.selectedID, let node = graph.nodes.first(where: { $0.id == id }) {
                        selectionBadge(node)
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                            .padding(NordicTheme.Spacing.m)
                    }
                    if let id = hoveredID ?? state.selectedID, let node = graph.nodes.first(where: { $0.id == id }) {
                        hoverCard(node, graph: graph, viewport: geo.size)
                            .allowsHitTesting(false)
                    }
                    legend(full: full)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
                        .padding(NordicTheme.Spacing.m)
                    zoomControls
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                        .padding(NordicTheme.Spacing.m)
                }
                .clipped()
                .contentShape(Rectangle())
                .gesture(zoomGesture)
                // Esc clears the selection.
                .focusable()
                .focusEffectDisabled()
                .onExitCommand { state.selectedID = nil }
                .onAppear {
                    viewport = geo.size
                    relayoutIfNeeded(graph, force: state.positions.isEmpty)
                }
                .onChange(of: geo.size) { old, size in
                    viewport = size
                    // The first size SwiftUI reports can be a placeholder; lay out and fit again
                    // once the real canvas size is known.
                    if state.positions.isEmpty || old.width < Self.minimumViewport || old.height < Self.minimumViewport {
                        relayoutIfNeeded(graph, force: true)
                    }
                }
                .onChange(of: graph.nodes.map(\.id)) { _, _ in relayoutIfNeeded(graph, force: false) }
            }
            .overlay {
                if full.nodes.isEmpty {
                    NordicEmptyState(icon: .nodeGraph, title: "Nothing to Show Yet",
                                     description: "Containers, images, networks, volumes and machines appear here with the links between them.")
                }
            }
        }
    }

    // MARK: - Header

    private func header(full: ResourceGraph, shown: ResourceGraph) -> some View {
        VStack(alignment: .leading, spacing: NordicTheme.Spacing.m) {
            HStack(alignment: .firstTextBaseline, spacing: NordicTheme.Spacing.s) {
                Text("Node Graph")
                    .font(NordicTheme.titleFont)
                    .foregroundStyle(NordicTheme.primaryText)
                Text("Every resource and how they connect: what runs what, which networks, addresses, storage and ports they use.")
                    .font(.system(size: 12))
                    .foregroundStyle(NordicTheme.secondaryText)
                    .lineLimit(2)
            }
            HStack(spacing: NordicTheme.Spacing.m) {
                Text("\(shown.nodes.count) nodes · \(shown.edges.count) links")
                    .font(.system(size: 12).monospacedDigit())
                    .foregroundStyle(NordicTheme.secondaryText)
                Spacer()
                Picker("Layout", selection: Binding(get: { state.layout }, set: { newLayout in
                    state.layout = newLayout
                    arrange(shown, keepPinned: false)
                })) {
                    ForEach(GraphLayout.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.menu)
                .fixedSize()
                .controlSize(.small)
                .accessibilityIdentifier("lada.nodeGraph.layout")
                NordicInfoTip(state.layout.explanation, title: state.layout.rawValue)
                Button {
                    arrange(shown, keepPinned: false)
                } label: {
                    Label("Re-arrange", systemImage: "wand.and.rays")
                }
                .controlSize(.small)
                .help("Run the layout again; nodes you moved are placed too")
                .accessibilityIdentifier("lada.nodeGraph.rearrange")
            }
        }
        .padding(.horizontal, NordicTheme.Spacing.l)
        .padding(.vertical, NordicTheme.Spacing.m)
        .nordicBar()
        .overlay(alignment: .bottom) { Divider().overlay(NordicTheme.borderSubtle) }
    }

    // MARK: - Canvas

    private var canvasBackground: some View {
        // A faint dot grid that pans and zooms with the graph.
        Canvas { context, size in
            let spacing = 28 * state.zoom
            guard spacing > 6 else { return }
            let dot = Path(ellipseIn: CGRect(x: 0, y: 0, width: 1.6, height: 1.6))
            let startX = state.pan.width.truncatingRemainder(dividingBy: spacing)
            let startY = state.pan.height.truncatingRemainder(dividingBy: spacing)
            var y = startY
            while y < size.height {
                var x = startX
                while x < size.width {
                    context.fill(dot.offsetBy(dx: x, dy: y), with: .color(NordicTheme.secondaryText.opacity(0.18)))
                    x += spacing
                }
                y += spacing
            }
        }
    }

    private func screen(_ p: CGPoint) -> CGPoint {
        CGPoint(x: p.x * state.zoom + state.pan.width, y: p.y * state.zoom + state.pan.height)
    }

    private var focusID: String? { hoveredID ?? state.selectedID }

    private func edgesLayer(_ graph: ResourceGraph) -> some View {
        let focus = focusID
        return Canvas { context, _ in
            for edge in graph.edges {
                guard let a = state.positions[edge.from], let b = state.positions[edge.to] else { continue }
                let p1 = screen(a), p2 = screen(b)
                let touchesFocus = focus == nil || edge.from == focus || edge.to == focus
                var path = Path()
                path.move(to: p1)
                // A gentle curve, so parallel links stay apart.
                let mid = CGPoint(x: (p1.x + p2.x) / 2, y: (p1.y + p2.y) / 2)
                let normal = CGPoint(x: -(p2.y - p1.y) * 0.08, y: (p2.x - p1.x) * 0.08)
                path.addQuadCurve(to: p2, control: CGPoint(x: mid.x + normal.x, y: mid.y + normal.y))
                let color = Self.color(for: edge.relation)
                context.stroke(
                    path,
                    with: .color(color.opacity(touchesFocus ? (focus == nil ? 0.55 : 0.95) : 0.12)),
                    style: StrokeStyle(lineWidth: touchesFocus && focus != nil ? 2 : 1.2, lineCap: .round,
                                       dash: edge.relation == .similar ? [4, 4] : [])
                )
                if focus != nil && touchesFocus && state.zoom > 0.6 {
                    context.draw(
                        Text(edge.relation.rawValue).font(.system(size: 10, weight: .medium)).foregroundStyle(color),
                        at: CGPoint(x: mid.x + normal.x * 0.5, y: mid.y + normal.y * 0.5 - 8)
                    )
                }
            }
        }
    }

    private func nodeChip(_ node: ResourceGraph.Node) -> some View {
        let focus = focusID
        let related = focus == nil || focus == node.id || (state.adjacency[focus!]?.contains(node.id) ?? false)
        return NodeChipView(
            node: node,
            position: screen(state.positions[node.id] ?? .zero),
            scale: min(1.15, max(0.55, state.zoom)),
            isSelected: state.selectedID == node.id,
            isHovered: hoveredID == node.id,
            isDimmed: !related,
            onHover: { inside in hoveredID = inside ? node.id : (hoveredID == node.id ? nil : hoveredID) },
            onDrag: { translation in
                if dragOrigin == nil { dragOrigin = state.positions[node.id] }
                guard let origin = dragOrigin else { return }
                state.positions[node.id] = CGPoint(x: origin.x + translation.width / state.zoom,
                                                   y: origin.y + translation.height / state.zoom)
                state.pinned.insert(node.id)
            },
            onDragEnded: { dragOrigin = nil },
            onTap: { state.selectedID = state.selectedID == node.id ? nil : node.id },
            onOpen: { if let destination = node.destination { appState.open(destination) } }
        )
        .equatable()
    }

    private func selectionBadge(_ node: ResourceGraph.Node) -> some View {
        HStack(spacing: 6) {
            LadaIcon(Self.icon(for: node.kind), size: 12).foregroundStyle(Self.color(for: node.kind))
            Text(node.title).font(.system(size: 11.5, weight: .semibold)).lineLimit(1)
            Button {
                state.selectedID = nil
            } label: {
                Image(systemName: "xmark.circle.fill").foregroundStyle(NordicTheme.secondaryText)
            }
            .buttonStyle(.plain)
            .help("Clear selection (Esc, or click empty space)")
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .nordicSurface(cornerRadius: 12)
        .accessibilityIdentifier("lada.nodeGraph.selection")
    }

    private func hoverCard(_ node: ResourceGraph.Node, graph: ResourceGraph, viewport: CGSize) -> some View {
        let anchor = screen(state.positions[node.id] ?? .zero)
        let links = graph.edges.filter { $0.from == node.id || $0.to == node.id }
        let width: CGFloat = 290
        let x = min(max(anchor.x + 110, width / 2 + 8), viewport.width - width / 2 - 8)
        let y = min(max(anchor.y, 120), viewport.height - 140)
        return VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                LadaIcon(Self.icon(for: node.kind), size: 15).foregroundStyle(Self.color(for: node.kind))
                Text(node.title).font(.system(size: 13, weight: .semibold)).lineLimit(1)
                Spacer()
                Text(node.kind.rawValue)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(NordicTheme.secondaryText)
                    .padding(.horizontal, 6).padding(.vertical, 1)
                    .nordicChip(cornerRadius: 4)
            }
            if !node.info.isEmpty {
                Grid(alignment: .leading, horizontalSpacing: 10, verticalSpacing: 4) {
                    ForEach(Array(node.info.enumerated()), id: \.offset) { _, field in
                        GridRow {
                            Text(field.label).foregroundStyle(NordicTheme.secondaryText)
                            Text(field.value).foregroundStyle(NordicTheme.primaryText).lineLimit(2).truncationMode(.middle)
                        }
                    }
                }
                .font(.system(size: 11))
            }
            if !links.isEmpty {
                Divider().overlay(NordicTheme.borderSubtle)
                Text("\(links.count) link\(links.count == 1 ? "" : "s"): " + Set(links.map(\.relation.rawValue)).sorted().joined(separator: ", "))
                    .font(.system(size: 11))
                    .foregroundStyle(NordicTheme.secondaryText)
            }
            if node.destination != nil {
                Text("Double-click to open")
                    .font(.system(size: 10.5))
                    .foregroundStyle(NordicTheme.secondaryText.opacity(0.8))
            }
        }
        .padding(12)
        .frame(width: width, alignment: .leading)
        .nordicSurface()
        .position(x: x, y: y)
        .transition(.opacity)
    }

    private func legend(full: ResourceGraph) -> some View {
        let counts = Dictionary(grouping: full.nodes, by: \.kind).mapValues(\.count)
        return VStack(alignment: .leading, spacing: 4) {
            Text("Show")
                .font(.system(size: 10.5, weight: .semibold))
                .foregroundStyle(NordicTheme.secondaryText)
            ForEach(ResourceGraph.Kind.allCases.filter { counts[$0] != nil }, id: \.self) { kind in
                let hidden = state.hiddenKinds.contains(kind)
                Button {
                    if hidden { state.hiddenKinds.remove(kind) } else { state.hiddenKinds.insert(kind) }
                } label: {
                    HStack(spacing: 6) {
                        LadaIcon(Self.icon(for: kind), size: 12).foregroundStyle(hidden ? NordicTheme.secondaryText : Self.color(for: kind))
                        Text(kind.rawValue).font(.system(size: 11)).foregroundStyle(hidden ? NordicTheme.secondaryText : NordicTheme.primaryText)
                        Spacer(minLength: 8)
                        Text("\(counts[kind] ?? 0)").font(.system(size: 10.5).monospacedDigit()).foregroundStyle(NordicTheme.secondaryText)
                    }
                    .opacity(hidden ? 0.55 : 1)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help(hidden ? "Show \(kind.rawValue.lowercased()) nodes" : "Hide \(kind.rawValue.lowercased()) nodes")
            }
        }
        .padding(10)
        .frame(width: 160)
        .nordicSurface()
        .accessibilityIdentifier("lada.nodeGraph.legend")
    }

    private var zoomControls: some View {
        HStack(spacing: 2) {
            Button { zoom(by: 1 / 1.2) } label: { Image(systemName: "minus") }.help("Zoom out")
            Text("\(Int((state.zoom * 100).rounded()))%")
                .font(.system(size: 11).monospacedDigit())
                .foregroundStyle(NordicTheme.secondaryText)
                .frame(width: 42)
            Button { zoom(by: 1.2) } label: { Image(systemName: "plus") }.help("Zoom in")
            Divider().frame(height: 14).padding(.horizontal, 4)
            Button { state.fit(viewport: viewport) } label: { Image(systemName: "arrow.up.left.and.arrow.down.right") }
                .help("Fit the whole graph in view")
        }
        .buttonStyle(.borderless)
        .controlSize(.small)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .nordicSurface()
    }

    // MARK: - Gestures & layout

    /// Dragging the background pans; a click on it (barely any movement) clears the selection.
    private var panGesture: some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                if panOrigin == nil { panOrigin = state.pan }
                state.pan = CGSize(width: panOrigin!.width + value.translation.width, height: panOrigin!.height + value.translation.height)
            }
            .onEnded { value in
                if hypot(value.translation.width, value.translation.height) < 4 {
                    state.selectedID = nil
                }
                panOrigin = nil
            }
    }

    private var zoomGesture: some Gesture {
        MagnifyGesture()
            .onChanged { value in
                if zoomOrigin == nil { zoomOrigin = state.zoom }
                setZoom(zoomOrigin! * value.magnification)
            }
            .onEnded { _ in zoomOrigin = nil }
    }

    private func zoom(by factor: CGFloat) {
        withAnimation(NordicTheme.Motion.quick) { setZoom(state.zoom * factor) }
    }

    /// Zooms around the middle of the view.
    private func setZoom(_ newZoom: CGFloat) {
        let clamped = min(2.5, max(0.25, newZoom))
        let center = CGPoint(x: viewport.width / 2, y: viewport.height / 2)
        let world = CGPoint(x: (center.x - state.pan.width) / state.zoom, y: (center.y - state.pan.height) / state.zoom)
        state.zoom = clamped
        state.pan = CGSize(width: center.x - world.x * clamped, height: center.y - world.y * clamped)
    }

    private func arrange(_ graph: ResourceGraph, keepPinned: Bool) {
        withAnimation(.spring(duration: 0.6)) {
            state.arrange(graph, viewport: viewport, keepPinned: keepPinned)
            state.fit(viewport: viewport)
        }
    }

    /// Lays out when the set of nodes changed (new or removed resources); dragged nodes stay put.
    private func relayoutIfNeeded(_ graph: ResourceGraph, force: Bool) {
        let ids = Set(graph.nodes.map(\.id))
        guard force || ids != state.laidOutIDs,
              viewport.width >= Self.minimumViewport, viewport.height >= Self.minimumViewport else { return }
        arrange(graph, keepPinned: !force)
    }

    /// Smaller sizes are layout placeholders, not the real canvas.
    static let minimumViewport: CGFloat = 200

    // MARK: - Style

    static func icon(for kind: ResourceGraph.Kind) -> LadaIconKind {
        switch kind {
        case .stack: return .stacks
        case .container: return .containers
        case .machine: return .machines
        case .image: return .images
        case .network: return .networks
        case .ipAddress: return .ipAddress
        case .subnet: return .subnet
        case .volume: return .volumes
        case .hostFolder: return .hostFolder
        case .port: return .port
        case .registry: return .registries
        }
    }

    /// Nordic tones per type, distinct in both appearances.
    static func color(for kind: ResourceGraph.Kind) -> Color {
        switch kind {
        case .stack: return Color(red: 0.71, green: 0.56, blue: 0.68)       // aurora purple
        case .container: return NordicTheme.accent()
        case .machine: return Color(red: 0.37, green: 0.51, blue: 0.67)     // deep fjord
        case .image: return Color(red: 0.53, green: 0.75, blue: 0.82)       // frost
        case .network: return Color(red: 0.56, green: 0.74, blue: 0.73)     // teal
        case .ipAddress: return Color(red: 0.51, green: 0.63, blue: 0.76)
        case .subnet: return Color(red: 0.43, green: 0.58, blue: 0.70)
        case .volume: return NordicTheme.statusGreen
        case .hostFolder: return NordicTheme.statusAmber
        case .port: return Color(red: 0.82, green: 0.53, blue: 0.44)        // aurora orange
        case .registry: return NordicTheme.secondaryText
        }
    }

    static func color(for relation: ResourceGraph.Relation) -> Color {
        switch relation {
        case .memberOf: return color(for: .stack)
        case .runs: return color(for: .image)
        case .attachedTo: return color(for: .network)
        case .hasAddress, .inSubnet: return color(for: .ipAddress)
        case .mounts: return color(for: .volume)
        case .publishes: return color(for: .port)
        case .pulledFrom: return color(for: .registry)
        case .similar: return NordicTheme.secondaryText
        }
    }
}


/// One node on the canvas. Equatable, so moving or hovering one node redraws only the chips whose
/// inputs changed. Drawn with a light translucent fill instead of a blur material and shadow per
/// chip, which got slow with many overlapping nodes.
private struct NodeChipView: View, Equatable {
    let node: ResourceGraph.Node
    let position: CGPoint
    let scale: CGFloat
    let isSelected: Bool
    let isHovered: Bool
    let isDimmed: Bool
    let onHover: (Bool) -> Void
    let onDrag: (CGSize) -> Void
    let onDragEnded: () -> Void
    let onTap: () -> Void
    let onOpen: () -> Void

    nonisolated static func == (a: NodeChipView, b: NodeChipView) -> Bool {
        a.node == b.node && a.position == b.position && a.scale == b.scale && a.isSelected == b.isSelected
            && a.isHovered == b.isHovered && a.isDimmed == b.isDimmed
    }

    var body: some View {
        let color = NodeGraphView.color(for: node.kind)
        let shape = RoundedRectangle(cornerRadius: 13, style: .continuous)
        HStack(spacing: 8) {
            ZStack {
                Circle().fill(color.opacity(0.18))
                LadaIcon(NodeGraphView.icon(for: node.kind), size: 14).foregroundStyle(color)
            }
            .frame(width: 26, height: 26)
            VStack(alignment: .leading, spacing: 1) {
                Text(node.title)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(NordicTheme.primaryText)
                    .lineLimit(1)
                Text(node.subtitle.isEmpty ? node.kind.rawValue : "\(node.kind.rawValue) · \(node.subtitle)")
                    .font(.system(size: 10))
                    .foregroundStyle(NordicTheme.secondaryText)
                    .lineLimit(1)
            }
        }
        .padding(.leading, 6)
        .padding(.trailing, 10)
        .padding(.vertical, 5)
        .frame(maxWidth: 190)
        .fixedSize()
        .background(shape.fill(Color(nsColor: .windowBackgroundColor).opacity(0.78)))
        .overlay(shape.strokeBorder(isSelected ? color : (isHovered ? color.opacity(0.6) : NordicTheme.borderSubtle), lineWidth: isSelected ? 1.8 : 1))
        .opacity((isDimmed ? 0.28 : 1) * (node.isActive ? 1 : 0.7))
        .scaleEffect(scale)
        .position(position)
        .onHover(perform: onHover)
        .gesture(
            DragGesture(minimumDistance: 3)
                .onChanged { onDrag($0.translation) }
                .onEnded { _ in onDragEnded() }
        )
        // Single and double click without the double-click delay on single clicks.
        .simultaneousGesture(TapGesture(count: 2).onEnded(onOpen))
        .simultaneousGesture(TapGesture(count: 1).onEnded(onTap))
        .help(node.destination == nil ? node.title : "Double-click to open \(node.title)")
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(node.kind.rawValue) \(node.title)")
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }
}
