//
//  OnboardingModels.swift
//  Masklarva
//
//  Created by Tufan Cakir on 24.09.26.
//

import Foundation

enum OnboardingArtwork: Equatable {
    case asset(String)
    case symbol(String)
}

struct OnboardingPage: Identifiable, Equatable {
    let id: Int
    let title: String
    let message: String
    let artwork: OnboardingArtwork

    static let pages: [OnboardingPage] = [
        OnboardingPage(
            id: 0,
            title: "Clay Studio",
            message: "Dein mobiler 3D-Editor für Modelle, Spiele und Apps.",
            artwork: .asset("m_logo")
        ),
        OnboardingPage(
            id: 1,
            title: "Direkt modellieren",
            message:
                "Objekte bewegen, drehen, skalieren und einzelne Mesh-Punkte bearbeiten.",
            artwork: .symbol("move.3d")
        ),
        OnboardingPage(
            id: 2,
            title: "Materialien gestalten",
            message:
                "Farben und Oberflächen erstellen und direkt auf deine Objekte ziehen.",
            artwork: .symbol("paintpalette.fill")
        ),
        OnboardingPage(
            id: 3,
            title: "Für deine Projekte",
            message:
                "Szenen als USDZ, USDA, Reality oder SCN exportieren und nativ teilen.",
            artwork: .symbol("shippingbox.fill")
        ),
    ]
}
