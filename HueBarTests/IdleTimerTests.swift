//
//  IdleTimerTests.swift
//  HueBarTests · HueBar
//
//  Timing checks for the popup idle timeout, using millisecond-scale intervals.
//

import Foundation
import Testing

@testable import HueBar

@MainActor
struct IdleTimerTests {
    /// Counts expirations; a class so the timer's closure can mutate it.
    private final class Counter { var value = 0 }

    @Test func firesOnceAfterTheInterval() async throws {
        let counter = Counter()
        let timer = IdleTimer { counter.value += 1 }
        timer.arm(after: 0.05)
        try await Task.sleep(for: .milliseconds(300))
        #expect(counter.value == 1)
    }

    @Test func rearmingPostponesExpiry() async throws {
        let counter = Counter()
        let timer = IdleTimer { counter.value += 1 }
        timer.arm(after: 0.6)
        try await Task.sleep(for: .milliseconds(300))
        timer.arm(after: 0.6)
        try await Task.sleep(for: .milliseconds(300))
        #expect(counter.value == 0)
        try await Task.sleep(for: .milliseconds(700))
        #expect(counter.value == 1)
    }

    @Test func stopPreventsExpiry() async throws {
        let counter = Counter()
        let timer = IdleTimer { counter.value += 1 }
        timer.arm(after: 0.05)
        timer.stop()
        try await Task.sleep(for: .milliseconds(250))
        #expect(counter.value == 0)
    }

    @Test func stopRightAtExpiryStillPreventsTheCallback() async {
        // Cancelling in the same main-actor turn the timer fires in must still win.
        for _ in 0..<20 {
            let counter = Counter()
            let timer = IdleTimer { counter.value += 1 }
            timer.arm(after: 0.001)
            try? await Task.sleep(for: .milliseconds(1))
            timer.stop()
            let afterStop = counter.value
            try? await Task.sleep(for: .milliseconds(20))
            #expect(counter.value == afterStop)
        }
    }

    @Test func zeroMeansNever() async throws {
        let counter = Counter()
        let timer = IdleTimer { counter.value += 1 }
        timer.arm(after: 0)
        try await Task.sleep(for: .milliseconds(150))
        #expect(counter.value == 0)
    }

    @Test func defaultTimeoutIsOfferedInTheMenu() {
        #expect(PopoverTimeout.choices.contains { $0.seconds == PopoverTimeout.defaultSeconds })
        #expect(PopoverTimeout.choices.contains { $0.seconds == 0 })
    }
}
