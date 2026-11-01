//
//  AppInfo.swift
//  HueBar · HueBar
//
//  App identity for the About panel: author, version, build date, license and repository.
//

import Foundation

/// Identity shown in the About section.
enum AppInfo {
    static let name = "HueBar"
    static let author = "Todd Dube"
    static let license = "MIT License · free and open source"
    static let repositoryURL = URL(string: "https://github.com/todddube/huelights")!
    static let licenseURL = URL(string: "https://github.com/todddube/huelights/blob/main/LICENSE")!

    /// Marketing version from the bundle; `swift run` has no Info.plist, so it falls back to a
    /// literal that must be kept in step with `MARKETING_VERSION` in `project.yml`.
    static var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0.0"
    }

    /// When this build was made: the `HueBuildDate` stamped by `scripts/build-app.sh`, else the
    /// executable's modification time (Xcode and `swift run` builds), else `nil`.
    ///
    /// Read once at launch, so it describes the running binary and costs nothing per render.
    static let buildDate: Date? = {
        if let stamp = Bundle.main.object(forInfoDictionaryKey: "HueBuildDate") as? String,
           let date = buildDate(fromStamp: stamp) {
            return date
        }
        guard let url = Bundle.main.executableURL,
              let values = try? url.resourceValues(forKeys: [.contentModificationDateKey]) else { return nil }
        return values.contentModificationDate
    }()

    /// Parses the ISO 8601 UTC stamp the build script writes, for example `2026-11-01T14:05:00Z`.
    static func buildDate(fromStamp stamp: String) -> Date? {
        try? Date(stamp, strategy: .iso8601)
    }

    /// `buildDate` formatted for display, for example "1 Nov 2026, 14:05".
    static let buildDateText: String? = buildDate?.formatted(date: .abbreviated, time: .shortened)

    /// The repository as shown in the UI, without the scheme.
    static var repositoryDisplay: String {
        (repositoryURL.host() ?? "") + repositoryURL.path()
    }

    /// Build number from the bundle, or `nil` under `swift run`.
    static var build: String? {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String
    }
}
