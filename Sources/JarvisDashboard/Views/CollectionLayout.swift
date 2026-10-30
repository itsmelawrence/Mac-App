import SwiftUI

/// How a long collection is shown: one item per row, or tiles in up to three columns.
enum CollectionLayout: String, CaseIterable, Identifiable {
    case list, grid

    var id: Self { self }

    var title: String {
        switch self {
        case .list: "List"
        case .grid: "Grid"
        }
    }

    var systemImage: String {
        switch self {
        case .list: "list.bullet"
        case .grid: "square.grid.3x2"
        }
    }

    /// Three columns in a full-width window, fewer as it narrows.
    static let gridColumns = [GridItem(.adaptive(minimum: 300), spacing: 12, alignment: .top)]
}

/// The list/grid switch shown above a collection.
struct CollectionLayoutPicker: View {
    @Binding var layout: CollectionLayout

    var body: some View {
        Picker("Layout", selection: $layout) {
            ForEach(CollectionLayout.allCases) { item in
                Image(systemName: item.systemImage).help(item.title).tag(item)
            }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .fixedSize()
        .help("Show as a list or as tiles")
        .accessibilityLabel("Layout")
    }
}
