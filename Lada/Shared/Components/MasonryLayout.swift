import SwiftUI

/// Packs panels of different heights into columns without gaps: each subview, in order, goes into
/// the column that is currently shortest. The number of columns follows the available width, so
/// panels sit side by side on a wide window and stack on a narrow one.
public struct MasonryLayout: Layout {
    public var minColumnWidth: CGFloat
    public var maxColumns: Int
    public var spacing: CGFloat

    public init(minColumnWidth: CGFloat = 380, maxColumns: Int = 2, spacing: CGFloat = 14) {
        self.minColumnWidth = minColumnWidth
        self.maxColumns = maxColumns
        self.spacing = spacing
    }

    /// Where each subview goes, plus the total height. Pure, so it's unit-tested without views.
    public struct Placement: Equatable {
        public var frames: [CGRect]
        public var height: CGFloat
    }

    public func columnCount(for width: CGFloat) -> Int {
        guard width.isFinite, width > 0 else { return 1 }
        let fitting = Int((width + spacing) / (minColumnWidth + spacing))
        return min(max(1, fitting), max(1, maxColumns))
    }

    /// `heightForWidth` measures one subview at the column width.
    public func place(count: Int, width: CGFloat, heightForWidth: (Int, CGFloat) -> CGFloat) -> Placement {
        let columns = columnCount(for: width)
        let columnWidth = max(0, (width - spacing * CGFloat(columns - 1)) / CGFloat(columns))
        var columnHeights = Array(repeating: CGFloat(0), count: columns)
        var frames: [CGRect] = []
        for index in 0..<count {
            // Shortest column; ties go to the leftmost so the first panels read left to right.
            let column = columnHeights.indices.min { columnHeights[$0] < columnHeights[$1] } ?? 0
            let y = columnHeights[column] == 0 ? 0 : columnHeights[column] + spacing
            let height = heightForWidth(index, columnWidth)
            frames.append(CGRect(x: CGFloat(column) * (columnWidth + spacing), y: y, width: columnWidth, height: height))
            columnHeights[column] = y + height
        }
        return Placement(frames: frames, height: columnHeights.max() ?? 0)
    }

    private func placement(for proposal: ProposedViewSize, subviews: Subviews) -> Placement {
        let width = proposal.width ?? minColumnWidth * CGFloat(maxColumns) + spacing * CGFloat(maxColumns - 1)
        return place(count: subviews.count, width: width) { index, columnWidth in
            subviews[index].sizeThatFits(ProposedViewSize(width: columnWidth, height: nil)).height
        }
    }

    public func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let result = placement(for: proposal, subviews: subviews)
        let width = proposal.width ?? (result.frames.map(\.maxX).max() ?? 0)
        return CGSize(width: width, height: result.height)
    }

    public func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = placement(for: ProposedViewSize(width: bounds.width, height: nil), subviews: subviews)
        for (index, frame) in result.frames.enumerated() {
            subviews[index].place(
                at: CGPoint(x: bounds.minX + frame.minX, y: bounds.minY + frame.minY),
                anchor: .topLeading,
                proposal: ProposedViewSize(width: frame.width, height: frame.height)
            )
        }
    }
}
