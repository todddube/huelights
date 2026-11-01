//
//  AppInfoTests.swift
//  HueBarTests · HueBar
//
//  Checks for the identity facts shown in the About panel.
//

import Foundation
import Testing

@testable import HueBar

struct AppInfoTests {
    @Test func repositoryLinksPointAtGitHub() {
        #expect(AppInfo.repositoryURL.host == "github.com")
        #expect(AppInfo.licenseURL.absoluteString.hasPrefix(AppInfo.repositoryURL.absoluteString))
    }

    @Test func versionIsNeverEmpty() {
        #expect(!AppInfo.version.isEmpty)
    }

    @Test func parsesTheBuildScriptStamp() {
        #expect(AppInfo.buildDate(fromStamp: "2026-11-01T14:05:00Z") == Date(timeIntervalSince1970: 1_793_541_900))
        #expect(AppInfo.buildDate(fromStamp: "2026-11-01 14:05") == nil)
        #expect(AppInfo.buildDate(fromStamp: "") == nil)
    }

    @Test func repositoryDisplayDropsTheScheme() {
        #expect(AppInfo.repositoryDisplay == "github.com/todddube/huelights")
    }

    @Test func buildDateFallsBackToTheExecutableAndIsNotInTheFuture() throws {
        // Under `swift test` Bundle.main is the test runner: no HueBuildDate key, so this only
        // proves the executable-mtime fallback yields a sane date.
        let date = try #require(AppInfo.buildDate)
        #expect(date <= Date().addingTimeInterval(60))
        #expect(AppInfo.buildDateText?.isEmpty == false)
    }
}
