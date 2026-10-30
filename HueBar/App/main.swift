//
//  main.swift
//  HueBar · HueBar
//
//  AppKit entry point. There is no SwiftUI App scene: the only UI is the status item's popover.
//

import AppKit

// A SwiftUI `App` needs at least one Scene, and an empty `Settings` scene gets shown as a
// blank window at launch when nothing else exists, so the app boots straight into AppKit.
let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()
