//
//  PomodoroPupApp.swift
//  PomodoroPup
//
//  Created by 轶微 on 2025/11/20.
//

import SwiftUI

@main
struct PomodoroPupApp: App {
    let persistenceController = PersistenceController.shared

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(\.managedObjectContext, persistenceController.container.viewContext)
        }
    }
}
