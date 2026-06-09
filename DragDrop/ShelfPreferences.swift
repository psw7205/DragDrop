import Combine
import Foundation

enum ShelfRetentionOption: String, CaseIterable, Identifiable, Hashable {
    case oneDay
    case sevenDays
    case thirtyDays
    case forever
    case custom

    var id: String { rawValue }

    var title: String {
        switch self {
        case .oneDay:
            "1 Day"
        case .sevenDays:
            "7 Days"
        case .thirtyDays:
            "30 Days"
        case .forever:
            "Forever"
        case .custom:
            "Custom"
        }
    }
}

enum ShelfSizeLimitOption: String, CaseIterable, Identifiable, Hashable {
    case off
    case mb512
    case gb1
    case custom

    var id: String { rawValue }

    var title: String {
        switch self {
        case .off:
            "Off"
        case .mb512:
            "512 MB"
        case .gb1:
            "1 GB"
        case .custom:
            "Custom"
        }
    }
}

final class ShelfPreferences: ObservableObject {
    enum Keys {
        static let retentionOption = "ShelfPreferences.retentionOption"
        static let customRetentionDays = "ShelfPreferences.customRetentionDays"
        static let sizeLimitOption = "ShelfPreferences.sizeLimitOption"
        static let customSizeLimitMB = "ShelfPreferences.customSizeLimitMB"
    }

    static let minimumCustomRetentionDays = 1
    static let maximumCustomRetentionDays = 3650
    static let minimumCustomSizeLimitMB = 1
    static let maximumCustomSizeLimitMB = 1_000_000

    @Published private var storedRetentionOption: ShelfRetentionOption
    @Published private var storedCustomRetentionDays: Int
    @Published private var storedSizeLimitOption: ShelfSizeLimitOption
    @Published private var storedCustomSizeLimitMB: Int

    private let defaults: UserDefaults

    var retentionOption: ShelfRetentionOption {
        get { storedRetentionOption }
        set {
            guard storedRetentionOption != newValue else { return }
            storedRetentionOption = newValue
            defaults.set(newValue.rawValue, forKey: Keys.retentionOption)
        }
    }

    var customRetentionDays: Int {
        get { storedCustomRetentionDays }
        set {
            let clampedValue = Self.clampedCustomRetentionDays(newValue)
            guard storedCustomRetentionDays != clampedValue else { return }
            storedCustomRetentionDays = clampedValue
            defaults.set(clampedValue, forKey: Keys.customRetentionDays)
        }
    }

    var sizeLimitOption: ShelfSizeLimitOption {
        get { storedSizeLimitOption }
        set {
            guard storedSizeLimitOption != newValue else { return }
            storedSizeLimitOption = newValue
            defaults.set(newValue.rawValue, forKey: Keys.sizeLimitOption)
        }
    }

    var customSizeLimitMB: Int {
        get { storedCustomSizeLimitMB }
        set {
            let clampedValue = Self.clampedCustomSizeLimitMB(newValue)
            guard storedCustomSizeLimitMB != clampedValue else { return }
            storedCustomSizeLimitMB = clampedValue
            defaults.set(clampedValue, forKey: Keys.customSizeLimitMB)
        }
    }

    var cleanupPolicy: ShelfCleanupPolicy {
        ShelfCleanupPolicy(
            maximumAge: maximumAge,
            maximumTotalBytes: maximumTotalBytes
        )
    }

    var cleanupDescription: String {
        switch (maximumAge, maximumTotalBytes) {
        case (nil, nil):
            "This cleanup policy is currently disabled because retention is Forever and the size limit is Off."
        case (let age?, nil):
            "This removes shelf items older than \(Self.days(from: age)) day(s)."
        case (nil, let bytes?):
            "This removes the oldest shelf items if stored files exceed \(Self.formatBytes(bytes))."
        case (let age?, let bytes?):
            "This removes shelf items older than \(Self.days(from: age)) day(s), then removes the oldest remaining items if stored files exceed \(Self.formatBytes(bytes))."
        }
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults

        storedRetentionOption = Self.storedRetentionOption(in: defaults)
        storedCustomRetentionDays = Self.storedCustomRetentionDays(in: defaults)
        storedSizeLimitOption = Self.storedSizeLimitOption(in: defaults)
        storedCustomSizeLimitMB = Self.storedCustomSizeLimitMB(in: defaults)
    }

    private var maximumAge: TimeInterval? {
        switch retentionOption {
        case .oneDay:
            Self.daysToSeconds(1)
        case .sevenDays:
            Self.daysToSeconds(7)
        case .thirtyDays:
            Self.daysToSeconds(30)
        case .forever:
            nil
        case .custom:
            Self.daysToSeconds(customRetentionDays)
        }
    }

    private var maximumTotalBytes: Int64? {
        switch sizeLimitOption {
        case .off:
            nil
        case .mb512:
            512_000_000
        case .gb1:
            1_000_000_000
        case .custom:
            Int64(customSizeLimitMB) * 1_000_000
        }
    }

    private static func storedRetentionOption(in defaults: UserDefaults) -> ShelfRetentionOption {
        guard let rawValue = defaults.string(forKey: Keys.retentionOption),
              let option = ShelfRetentionOption(rawValue: rawValue) else {
            return .thirtyDays
        }
        return option
    }

    private static func storedCustomRetentionDays(in defaults: UserDefaults) -> Int {
        let stored = defaults.integer(forKey: Keys.customRetentionDays)
        return clampedCustomRetentionDays(stored == 0 ? 30 : stored)
    }

    private static func storedSizeLimitOption(in defaults: UserDefaults) -> ShelfSizeLimitOption {
        guard let rawValue = defaults.string(forKey: Keys.sizeLimitOption),
              let option = ShelfSizeLimitOption(rawValue: rawValue) else {
            return .gb1
        }
        return option
    }

    private static func storedCustomSizeLimitMB(in defaults: UserDefaults) -> Int {
        let stored = defaults.integer(forKey: Keys.customSizeLimitMB)
        return clampedCustomSizeLimitMB(stored == 0 ? 1000 : stored)
    }

    private static func clampedCustomRetentionDays(_ days: Int) -> Int {
        min(max(days, minimumCustomRetentionDays), maximumCustomRetentionDays)
    }

    private static func clampedCustomSizeLimitMB(_ megabytes: Int) -> Int {
        min(max(megabytes, minimumCustomSizeLimitMB), maximumCustomSizeLimitMB)
    }

    private static func daysToSeconds(_ days: Int) -> TimeInterval {
        TimeInterval(days * 24 * 60 * 60)
    }

    private static func days(from seconds: TimeInterval) -> Int {
        Int(seconds / 24 / 60 / 60)
    }

    private static func formatBytes(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter.string(fromByteCount: bytes)
    }
}
