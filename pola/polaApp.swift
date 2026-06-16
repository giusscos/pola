//
//  polaApp.swift
//  pola
//
//  Created by Giuseppe Cosenza on 08/06/2026.
//

import SwiftUI
import SwiftData

@main
struct polaApp: App {
    var sharedModelContainer: ModelContainer = {
        let schema = Schema([
            Item.self,
        ])
        let modelConfiguration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)

        do {
            return try ModelContainer(for: schema, configurations: [modelConfiguration])
        } catch {
            fatalError("Could not create ModelContainer: \(error)")
        }
    }()

    @AppStorage("hasSeenOnboarding") private var hasSeenOnboarding = false

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(PremiumManager.shared)
                .fullScreenCover(isPresented: Binding(
                    get: { !hasSeenOnboarding },
                    set: { if !$0 { hasSeenOnboarding = true } }
                )) {
                    OnboardingView(hasSeenOnboarding: $hasSeenOnboarding)
                        .environment(PremiumManager.shared)
                }
        }
        .modelContainer(sharedModelContainer)
    }
}
