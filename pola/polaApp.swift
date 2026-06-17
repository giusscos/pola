//
//  polaApp.swift
//  pola
//
//  Created by Giuseppe Cosenza on 08/06/2026.
//

import SwiftUI

@main
struct polaApp: App {
    @State private var languageManager: LanguageManager
    @AppStorage("hasSeenOnboarding") private var hasSeenOnboarding = false

    init() {
        // Access the singleton HERE, before any SwiftUI view renders,
        // so Bundle swizzling is in place for the very first frame.
        let lm = LanguageManager.shared
        _languageManager = State(wrappedValue: lm)
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(PremiumManager.shared)
                .environment(languageManager)
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
    }
}
