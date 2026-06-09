//
//  DragDropApp.swift
//  DragDrop
//
//  Created by hc on 3/10/26.
//

import SwiftUI

@main
struct DragDropApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        Settings {
            appDelegate.makePreferencesView()
        }
    }
}
