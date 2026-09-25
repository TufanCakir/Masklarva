//
//  MasklarvaApp.swift
//  Masklarva
//
//  Created by Tufan Cakir on 24.09.26.
//

import SwiftUI

@main
struct MasklarvaApp: App {
    @AppStorage("hasCompletedOnboarding")
    private var hasCompletedOnboarding = false

    var body: some Scene {
        WindowGroup {
            if hasCompletedOnboarding {
                HomeView()
                    .transition(.opacity)
            } else {
                OnboardingView {
                    hasCompletedOnboarding = true
                }
                .transition(.opacity)
            }
        }
    }
}
