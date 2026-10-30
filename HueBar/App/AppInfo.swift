//
//  AppInfo.swift
//  HueBar · HueBar
//
//  Static facts about the app shown in the About panel: author, version, license and repository.
//

import Foundation

/// Identity shown in the About section.
enum AppInfo {
    static let name = "HueBar"
    static let author = "Todd Dube"
    static let license = "MIT License · free and open source"
    static let repositoryURL = URL(string: "https://github.com/todddube/huelights")!
    static let licenseURL = URL(string: "https://github.com/todddube/huelights/blob/main/LICENSE")!

    /// Marketing version from the bundle, falling back to the package version for `swift run`.
    static var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0.0"
    }

    static var build: String? {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String
    }
}
