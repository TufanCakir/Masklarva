//
//  EditorInspectorPanel.swift
//  Masklarva
//
//  Created by Tufan Cakir on 24.09.26.
//

import SwiftUI

struct EditorInspectorPanel: View {
    @Binding var document: ModelDocument
    let selectedTool: EditorTool

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Label("Inspector", systemImage: "slider.horizontal.3")
                        .font(.headline)
                    Spacer()
                    Text(document.selectedObjectName)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                if document.selectedIndex != nil {
                    transformSection
                    materialSection
                    snappingSection
                } else {
                    ContentUnavailableView(
                        "Keine Auswahl",
                        systemImage: "cube.transparent"
                    )
                }
            }
            .padding(12)
        }
    }

    private var transformSection: some View {
        GroupBox {
            VStack(spacing: 8) {
                switch selectedTool {
                case .rotate:
                    valueRow(
                        title: "Rotation",
                        channels: [.rotationX, .rotationY, .rotationZ],
                        suffix: "°"
                    )
                case .scale:
                    valueRow(
                        title: "Skalierung",
                        channels: [.scaleX, .scaleY, .scaleZ]
                    )
                default:
                    valueRow(
                        title: "Position",
                        channels: [.positionX, .positionY, .positionZ]
                    )
                }
            }
        } label: {
            Label("Transform", systemImage: selectedTool.symbol)
        }
    }

    private func valueRow(
        title: String,
        channels: [InspectorChannel],
        suffix: String = ""
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            HStack(spacing: 6) {
                ForEach(channels) { channel in
                    VStack(spacing: 3) {
                        Text(channel.axis)
                            .font(.caption2.bold())
                            .foregroundStyle(channel.color)
                        TextField(
                            channel.axis,
                            value: channelBinding(channel),
                            format: .number.precision(.fractionLength(2))
                        )
                        .keyboardType(.numbersAndPunctuation)
                        .multilineTextAlignment(.center)
                        .textFieldStyle(.roundedBorder)
                        if !suffix.isEmpty {
                            Text(suffix)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
    }

    private var materialSection: some View {
        GroupBox {
            VStack(spacing: 10) {
                ColorPicker(
                    "Farbe",
                    selection: materialColorBinding,
                    supportsOpacity: false
                )
                inspectorSlider(
                    "Metall",
                    value: materialFloatBinding(\.metallic)
                )
                inspectorSlider(
                    "Rauheit",
                    value: materialFloatBinding(\.roughness)
                )
            }
        } label: {
            Label("Material", systemImage: "paintpalette.fill")
        }
    }

    private func inspectorSlider(
        _ title: String,
        value: Binding<Float>
    ) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack {
                Text(title)
                Spacer()
                Text(
                    value.wrappedValue,
                    format: .number.precision(.fractionLength(2))
                )
                .monospacedDigit()
            }
            .font(.caption)
            Slider(value: value, in: 0...1)
        }
    }

    private var snappingSection: some View {
        GroupBox {
            VStack(spacing: 8) {
                Toggle("Snapping", isOn: $document.snapEnabled)
                Picker("Position", selection: $document.moveSnap) {
                    Text("0,1").tag(Float(0.1))
                    Text("0,25").tag(Float(0.25))
                    Text("0,5").tag(Float(0.5))
                    Text("1").tag(Float(1))
                }
                Picker("Winkel", selection: $document.rotationSnapDegrees) {
                    Text("5°").tag(Float(5))
                    Text("15°").tag(Float(15))
                    Text("30°").tag(Float(30))
                    Text("45°").tag(Float(45))
                }
                Picker("Größe", selection: $document.scaleSnap) {
                    Text("0,05").tag(Float(0.05))
                    Text("0,1").tag(Float(0.1))
                    Text("0,25").tag(Float(0.25))
                    Text("0,5").tag(Float(0.5))
                }
            }
            .pickerStyle(.menu)
            .font(.caption)
        } label: {
            Label("Einrasten", systemImage: "dot.scope")
        }
    }

    private func channelBinding(_ channel: InspectorChannel) -> Binding<Float> {
        Binding {
            guard let index = document.selectedIndex else { return 0 }
            return channel.value(from: document.objects[index])
        } set: { newValue in
            guard let index = document.selectedIndex else { return }
            document.beginChange()
            channel.set(newValue, on: &document.objects[index])
            document.endChange()
        }
    }

    private var materialColorBinding: Binding<Color> {
        Binding {
            guard let index = document.selectedIndex else { return .white }
            return document.objects[index].material.color
        } set: { newValue in
            guard let index = document.selectedIndex else { return }
            document.beginChange()
            document.objects[index].material.color = newValue
            document.endChange()
        }
    }

    private func materialFloatBinding(
        _ keyPath: WritableKeyPath<EditorMaterial, Float>
    ) -> Binding<Float> {
        Binding {
            guard let index = document.selectedIndex else { return 0 }
            return document.objects[index].material[keyPath: keyPath]
        } set: { newValue in
            guard let index = document.selectedIndex else { return }
            document.beginChange()
            document.objects[index].material[keyPath: keyPath] = newValue
            document.endChange()
        }
    }
}

enum InspectorChannel: String, Identifiable {
    case positionX, positionY, positionZ
    case rotationX, rotationY, rotationZ
    case scaleX, scaleY, scaleZ

    var id: Self { self }
    var axis: String {
        switch self {
        case .positionX, .rotationX, .scaleX: "X"
        case .positionY, .rotationY, .scaleY: "Y"
        case .positionZ, .rotationZ, .scaleZ: "Z"
        }
    }
    var color: Color {
        switch self {
        case .positionX, .rotationX, .scaleX: .red
        case .positionY, .rotationY, .scaleY: .green
        case .positionZ, .rotationZ, .scaleZ: .blue
        }
    }

    func value(from object: SceneObject) -> Float {
        switch self {
        case .positionX: object.position.x
        case .positionY: object.position.y
        case .positionZ: object.position.z
        case .rotationX: object.rotation.x * 180 / .pi
        case .rotationY: object.rotation.y * 180 / .pi
        case .rotationZ: object.rotation.z * 180 / .pi
        case .scaleX: object.scale.x
        case .scaleY: object.scale.y
        case .scaleZ: object.scale.z
        }
    }

    func set(_ value: Float, on object: inout SceneObject) {
        switch self {
        case .positionX: object.position.x = value
        case .positionY: object.position.y = value
        case .positionZ: object.position.z = value
        case .rotationX: object.rotation.x = value * .pi / 180
        case .rotationY: object.rotation.y = value * .pi / 180
        case .rotationZ: object.rotation.z = value * .pi / 180
        case .scaleX: object.scale.x = max(0.01, value)
        case .scaleY: object.scale.y = max(0.01, value)
        case .scaleZ: object.scale.z = max(0.01, value)
        }
    }
}
