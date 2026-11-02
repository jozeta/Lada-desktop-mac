import SwiftUI
import Charts

/// A hollow pie chart with a value in the middle and a legend beside it (dashboard disk style).
public struct NordicDonutChart: View {
    public struct Slice: Identifiable, Equatable {
        public var id: String { label }
        public let label: String
        public let bytes: Int64
        public let color: Color

        public init(label: String, bytes: Int64, color: Color) {
            self.label = label
            self.bytes = bytes
            self.color = color
        }
    }

    let slices: [Slice]
    let centerValue: String
    let centerCaption: String
    let title: String
    let size: CGFloat

    public init(slices: [Slice], centerValue: String, centerCaption: String, title: String, size: CGFloat = 110) {
        self.slices = slices
        self.centerValue = centerValue
        self.centerCaption = centerCaption
        self.title = title
        self.size = size
    }

    public var body: some View {
        HStack(alignment: .center, spacing: NordicTheme.Spacing.l) {
            Chart(slices) { slice in
                SectorMark(
                    angle: .value("Bytes", max(slice.bytes, 0)),
                    innerRadius: .ratio(0.68),
                    angularInset: 1.2
                )
                .cornerRadius(3)
                .foregroundStyle(slice.color)
            }
            .chartLegend(.hidden)
            .frame(width: size, height: size)
            .overlay {
                VStack(spacing: 1) {
                    Text(centerValue)
                        .font(.system(size: 14, weight: .semibold).monospacedDigit())
                        .foregroundStyle(NordicTheme.primaryText)
                    Text(centerCaption)
                        .font(.system(size: 11))
                        .foregroundStyle(NordicTheme.secondaryText)
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("\(title): " + slices.map { "\($0.label) \(NordicFormat.bytes(fromByteCount: $0.bytes, countStyle: .file))" }.joined(separator: ", "))

            VStack(alignment: .leading, spacing: 5) {
                Text(title)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(NordicTheme.primaryText)
                ForEach(slices) { slice in
                    HStack(spacing: 6) {
                        Circle().fill(slice.color).frame(width: 8, height: 8)
                        Text(slice.label)
                            .font(.system(size: 12))
                            .foregroundStyle(NordicTheme.primaryText)
                        Spacer()
                        Text(NordicFormat.bytes(fromByteCount: slice.bytes, countStyle: .file))
                            .font(.system(size: 12).monospacedDigit())
                            .foregroundStyle(NordicTheme.secondaryText)
                    }
                }
            }
        }
    }
}
