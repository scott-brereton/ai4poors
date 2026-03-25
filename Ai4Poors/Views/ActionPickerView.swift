// ActionPickerView.swift
// Ai4Poors - Action picker for screenshot and direct text analysis

import SwiftUI
import PhotosUI

struct ActionPickerView: View {
    @EnvironmentObject var appState: Ai4PoorsAppState
    @Environment(\.dismiss) private var dismiss

    @State private var selectedAction: Ai4PoorsAction
    @State private var customInstruction = ""
    @State private var inputText = ""
    @State private var selectedImage: PhotosPickerItem?
    @State private var loadedImage: UIImage?
    @State private var inputMode: InputMode
    @State private var pendingMode: InputMode?
    @State private var showModeSwitchAlert = false

    init(initialAction: Ai4PoorsAction = .summarize, initialInputMode: InputMode = .text) {
        _selectedAction = State(initialValue: initialAction)
        _inputMode = State(initialValue: initialInputMode)
    }

    enum InputMode: String, CaseIterable {
        case text = "Text"
        case image = "Image"
    }

    var body: some View {
        NavigationStack {
            Form {
                inputSection
                actionSection

                if selectedAction == .custom {
                    customInstructionSection
                        .transition(.opacity.combined(with: .move(edge: .top)))
                }

                if selectedAction == .translate {
                    languageSection
                        .transition(.opacity.combined(with: .move(edge: .top)))
                }

                analyzeButton
            }
            .animation(.spring(response: 0.3, dampingFraction: 0.8), value: selectedAction)
            .navigationTitle("Analyze")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .alert("Switch Input Mode?", isPresented: $showModeSwitchAlert) {
                Button("Switch") {
                    if let mode = pendingMode {
                        inputText = ""
                        loadedImage = nil
                        selectedImage = nil
                        inputMode = mode
                        pendingMode = nil
                    }
                }
                Button("Cancel", role: .cancel) { pendingMode = nil }
            } message: {
                Text("This will clear your current input.")
            }
        }
    }

    // MARK: - Input Section

    private var inputSection: some View {
        Section {
            Picker("Input", selection: Binding(
                get: { inputMode },
                set: { newMode in
                    let hasContent = (inputMode == .text && !inputText.isEmpty) ||
                                     (inputMode == .image && loadedImage != nil)
                    if hasContent && newMode != inputMode {
                        pendingMode = newMode
                        showModeSwitchAlert = true
                    } else {
                        inputMode = newMode
                    }
                }
            )) {
                ForEach(InputMode.allCases, id: \.self) { mode in
                    Text(mode.rawValue).tag(mode)
                }
            }
            .pickerStyle(.segmented)

            switch inputMode {
            case .text:
                TextEditor(text: $inputText)
                    .frame(minHeight: 100)
                    .overlay(alignment: .topLeading) {
                        if inputText.isEmpty {
                            Text("Paste or type text to analyze...")
                                .foregroundStyle(.tertiary)
                                .padding(.top, 8)
                                .padding(.leading, 4)
                                .allowsHitTesting(false)
                        }
                    }

                HStack {
                    Button("Paste from Clipboard") {
                        if let text = UIPasteboard.general.string {
                            inputText = text
                        }
                    }

                    Spacer()

                    Text("\(inputText.count) chars")
                        .font(.caption2)
                        .foregroundStyle(inputText.count > 10000 ? .red : .secondary)
                        .monospacedDigit()
                }

            case .image:
                if let loadedImage {
                    Image(uiImage: loadedImage)
                        .resizable()
                        .scaledToFit()
                        .frame(maxHeight: 200)
                        .clipShape(RoundedRectangle(cornerRadius: Ai4PoorsDesign.Radius.medium))
                }

                PhotosPicker(selection: $selectedImage, matching: .images) {
                    Label(
                        loadedImage == nil ? "Select Image" : "Change Image",
                        systemImage: "photo"
                    )
                }
                .onChange(of: selectedImage) { _, newItem in
                    loadImage(from: newItem)
                }
            }
        } header: {
            Text("Content")
        }
    }

    // MARK: - Action Section

    private var actionSection: some View {
        Section {
            ForEach(Ai4PoorsAction.allCases, id: \.self) { action in
                Button {
                    let generator = UISelectionFeedbackGenerator()
                    generator.selectionChanged()
                    selectedAction = action
                } label: {
                    HStack {
                        Image(systemName: action.iconName)
                            .frame(width: 24)
                        Text(action.displayName)
                        Spacer()
                        if selectedAction == action {
                            Image(systemName: "checkmark")
                                .foregroundStyle(.blue)
                        }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        } header: {
            Text("Action")
        }
    }

    // MARK: - Custom Instruction

    private var customInstructionSection: some View {
        Section {
            TextField("What do you want to know?", text: $customInstruction)
        } header: {
            Text("Custom Instruction")
        }
    }

    // MARK: - Language

    private var languageSection: some View {
        Section {
            Picker("Target Language", selection: Binding(
                get: { AppGroupConstants.preferredLanguage },
                set: { AppGroupConstants.preferredLanguage = $0 }
            )) {
                ForEach(SupportedLanguages.all, id: \.self) {
                    Text($0).tag($0)
                }
            }
        }
    }

    // MARK: - Analyze Button

    private var analyzeButton: some View {
        Section {
            Button {
                performAnalysis()
                dismiss()
            } label: {
                HStack {
                    Spacer()
                    Label("Analyze", systemImage: "sparkle")
                        .font(.headline)
                    Spacer()
                }
            }
            .disabled(!canAnalyze)
        }
    }

    // MARK: - Logic

    private var canAnalyze: Bool {
        switch inputMode {
        case .text: return !inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        case .image: return loadedImage != nil
        }
    }

    private func performAnalysis() {
        let instruction = selectedAction == .custom ? customInstruction : nil

        switch inputMode {
        case .text:
            appState.analyzeText(
                inputText,
                action: selectedAction,
                channel: .share,
                customInstruction: instruction
            )
        case .image:
            if let image = loadedImage {
                appState.analyzeScreenshot(
                    image: image,
                    action: selectedAction,
                    customInstruction: instruction
                )
            }
        }
    }

    private func loadImage(from item: PhotosPickerItem?) {
        guard let item else { return }
        Task {
            if let data = try? await item.loadTransferable(type: Data.self),
               let image = UIImage(data: data) {
                loadedImage = image
            }
        }
    }
}
