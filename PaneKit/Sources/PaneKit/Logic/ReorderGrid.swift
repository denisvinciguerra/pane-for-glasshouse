import Foundation

/// Equal cells in rows, filled across then down: where a slot stands, how tall a number of them
/// is, and which slot a point is nearest. The pins' grid while a finger reorders them on iOS.
public struct ReorderGrid: Equatable, Sendable {
    public let columns: Int
    /// The whole row, spacing included.
    public let width: CGFloat
    public let cellHeight: CGFloat
    public let columnSpacing: CGFloat
    public let rowSpacing: CGFloat

    public init(columns: Int, width: CGFloat, cellHeight: CGFloat, columnSpacing: CGFloat, rowSpacing: CGFloat) {
        self.columns = max(1, columns)
        self.width = width
        self.cellHeight = cellHeight
        self.columnSpacing = columnSpacing
        self.rowSpacing = rowSpacing
    }

    public var cellWidth: CGFloat {
        max(0, (width - CGFloat(columns - 1) * columnSpacing) / CGFloat(columns))
    }

    /// The top left corner of the slot's cell.
    public func origin(of slot: Int) -> CGPoint {
        CGPoint(x: CGFloat(slot % columns) * (cellWidth + columnSpacing),
                y: CGFloat(slot / columns) * (cellHeight + rowSpacing))
    }

    /// The height of `count` cells' rows.
    public func height(for count: Int) -> CGFloat {
        guard count > 0 else { return 0 }
        let rows = (count + columns - 1) / columns
        return CGFloat(rows) * cellHeight + CGFloat(rows - 1) * rowSpacing
    }

    /// The slot, among the first `count`, whose cell's centre is nearest the point: beyond the
    /// last item, the last one.
    public func slot(nearest point: CGPoint, count: Int) -> Int {
        let column = Int(((point.x - cellWidth / 2) / (cellWidth + columnSpacing)).rounded())
        let row = Int(((point.y - cellHeight / 2) / (cellHeight + rowSpacing)).rounded())
        let slot = max(0, row) * columns + min(max(0, column), columns - 1)
        return max(0, min(slot, count - 1))
    }
}

extension Array {
    /// The array with the element at `from` moved to index `to` (within the array), the others
    /// making room; unchanged when `from` is not an index.
    public func moving(from: Int, to: Int) -> [Element] {
        guard indices.contains(from) else { return self }
        var list = self
        let element = list.remove(at: from)
        list.insert(element, at: Swift.max(0, Swift.min(to, list.count)))
        return list
    }
}
