//
//  polaApp.swift
//  pola
//
//  Created by Giuseppe Cosenza on 08/06/2026.
//

import SwiftData
import SwiftUI

@main
struct polaApp: App {
    @State private var languageManager: LanguageManager
    @State private var store = PhotoStore()
    @AppStorage("hasSeenOnboarding") private var hasSeenOnboarding = false

    let container: ModelContainer

    init() {
        let lm = LanguageManager.shared
        _languageManager = State(wrappedValue: lm)

        do {
            let config = ModelConfiguration(
                schema: Schema([PolaroidEntry.self]),
                cloudKitDatabase: .automatic
            )
            container = try ModelContainer(for: PolaroidEntry.self, configurations: config)
        } catch {
            // Fall back to local-only storage if CloudKit is unavailable
            container = try! ModelContainer(for: PolaroidEntry.self)
        }
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(PremiumManager.shared)
                .environment(languageManager)
                .environment(store)
                .id(languageManager.languageRefreshID)
                .fullScreenCover(isPresented: Binding(
                    get: { !hasSeenOnboarding },
                    set: { if !$0 { hasSeenOnboarding = true } }
                )) {
                    OnboardingView(hasSeenOnboarding: $hasSeenOnboarding)
                        .environment(PremiumManager.shared)
                        .environment(languageManager)
                }
        }
        .modelContainer(container)
    }
}
