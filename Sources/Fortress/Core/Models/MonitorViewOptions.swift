import Foundation

/// User-facing filters and presentation modes for the Fortress sidebar.
public struct MonitorViewOptions: Equatable, Sendable {
    public enum ListMode: String, CaseIterable, Identifiable, Sendable {
        case grouped
        case flat

        public var id: String { rawValue }

        public var label: String {
            switch self {
            case .grouped: return L10n.grouped
            case .flat: return L10n.flat
            }
        }
    }

    public var listMode: ListMode
    public var hideHelpers: Bool
    public var hideSystem: Bool
    public var activeOnly: Bool
    public var searchText: String

    public static let `default` = MonitorViewOptions(
        listMode: .grouped,
        hideHelpers: true,
        hideSystem: true,
        activeOnly: false,
        searchText: ""
    )

    public init(
        listMode: ListMode = .grouped,
        hideHelpers: Bool = true,
        hideSystem: Bool = true,
        activeOnly: Bool = false,
        searchText: String = ""
    ) {
        self.listMode = listMode
        self.hideHelpers = hideHelpers
        self.hideSystem = hideSystem
        self.activeOnly = activeOnly
        self.searchText = searchText
    }
}
