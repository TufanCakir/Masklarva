//
//  OnboardingView.swift
//  Masklarva
//
//  Created by Tufan Cakir on 24.09.26.
//

import SwiftUI

struct OnboardingView: View {
    @State private var viewModel = OnboardingViewModel()
    let onCompletion: () -> Void

    var body: some View {
        VStack(spacing: 20) {
            HStack {
                Spacer()
                Button("Überspringen") {
                    onCompletion()
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
            }

            TabView(selection: $viewModel.selectedPage) {
                ForEach(viewModel.pages) { page in
                    VStack(spacing: 28) {
                        Spacer()

                        Group {
                            switch page.artwork {
                            case .asset(let name):
                                Image(name)
                                    .resizable()
                                    .scaledToFit()
                            case .symbol(let name):
                                Image(systemName: name)
                                    .resizable()
                                    .scaledToFit()
                                    .symbolRenderingMode(.hierarchical)
                                    .foregroundStyle(.tint)
                            }
                        }
                        .frame(width: 150, height: 150)
                        .accessibilityHidden(true)

                        VStack(spacing: 12) {
                            Text(page.title)
                                .font(.largeTitle.bold())
                                .multilineTextAlignment(.center)
                            Text(page.message)
                                .font(.body)
                                .foregroundStyle(.secondary)
                                .multilineTextAlignment(.center)
                                .frame(maxWidth: 320)
                        }

                        Spacer()
                    }
                    .padding(.horizontal, 24)
                    .tag(page.id)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .always))

            Button(viewModel.isLastPage ? "3D-Editor öffnen" : "Weiter") {
                withAnimation(.snappy) {
                    viewModel.continueAction(onCompletion: onCompletion)
                }
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .frame(maxWidth: .infinity)
        }
        .padding(24)
        .background(Color.editorBackground.ignoresSafeArea())
        .preferredColorScheme(.dark)
    }
}
