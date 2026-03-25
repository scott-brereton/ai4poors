// ShareViewController.swift
// Ai4PoorsShareExtension - Receives shared text/images from any app
//
// When users share content (text, URLs, images) from any app,
// this extension sends it to Ai4Poors for AI analysis.

import UIKit
import SwiftUI
import UniformTypeIdentifiers

class ShareViewController: UIViewController {

    private var hostingController: UIHostingController<ShareExtensionView>?
    private let viewModel = ShareExtensionViewModel()

    override func viewDidLoad() {
        super.viewDidLoad()
        extractSharedContent()
        setupUI()
    }

    private func setupUI() {
        let shareView = ShareExtensionView(
            viewModel: viewModel,
            onAnalyze: { [weak self] action, instruction in
                self?.performAnalysis(action: action, customInstruction: instruction)
            },
            onDismiss: { [weak self] in
                self?.extensionContext?.completeRequest(returningItems: nil)
            }
        )

        let host = UIHostingController(rootView: shareView)
        addChild(host)
        view.addSubview(host.view)
        host.view.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            host.view.topAnchor.constraint(equalTo: view.topAnchor),
            host.view.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            host.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            host.view.trailingAnchor.constraint(equalTo: view.trailingAnchor)
        ])
        host.didMove(toParent: self)
        hostingController = host
    }

    // MARK: - Content Extraction

    private func extractSharedContent() {
        guard let items = extensionContext?.inputItems as? [NSExtensionItem] else { return }

        for item in items {
            guard let attachments = item.attachments else { continue }

            for attachment in attachments {
                // Text content
                if attachment.hasItemConformingToTypeIdentifier(UTType.plainText.identifier) {
                    attachment.loadItem(forTypeIdentifier: UTType.plainText.identifier) { [weak self] data, _ in
                        if let text = data as? String {
                            DispatchQueue.main.async {
                                self?.viewModel.sharedText = text
                                self?.viewModel.contentType = .text
                            }
                        }
                    }
                    return
                }

                // URL content
                if attachment.hasItemConformingToTypeIdentifier(UTType.url.identifier) {
                    attachment.loadItem(forTypeIdentifier: UTType.url.identifier) { [weak self] data, _ in
                        if let url = data as? URL {
                            DispatchQueue.main.async {
                                self?.viewModel.sharedText = url.absoluteString
                                self?.viewModel.contentType = .url
                            }
                        }
                    }
                    return
                }

                // Image content
                if attachment.hasItemConformingToTypeIdentifier(UTType.image.identifier) {
                    attachment.loadItem(forTypeIdentifier: UTType.image.identifier) { [weak self] data, _ in
                        var image: UIImage?
                        if let imageData = data as? Data {
                            image = UIImage(data: imageData)
                        } else if let url = data as? URL,
                                  let imageData = try? Data(contentsOf: url) {
                            image = UIImage(data: imageData)
                        } else if let img = data as? UIImage {
                            image = img
                        }

                        if let image {
                            DispatchQueue.main.async {
                                self?.viewModel.sharedImage = image
                                self?.viewModel.contentType = .image
                            }
                        }
                    }
                    return
                }
            }
        }
    }

    // MARK: - Analysis

    private func performAnalysis(action: Ai4PoorsAction, customInstruction: String?) {
        viewModel.isAnalyzing = true
        viewModel.result = nil
        viewModel.error = nil

        let instruction = customInstruction ?? action.defaultInstruction

        Task {
            do {
                let result: String

                switch viewModel.contentType {
                case .text, .url:
                    result = try await OpenRouterService.shared.analyzeText(
                        text: viewModel.sharedText,
                        instruction: instruction
                    )
                case .image:
                    guard let image = viewModel.sharedImage else {
                        throw Ai4PoorsError.imageEncodingFailed
                    }
                    result = try await OpenRouterService.shared.analyzeImage(
                        image: image,
                        instruction: instruction
                    )
                case .none:
                    throw Ai4PoorsError.invalidResponse
                }

                let shareChannel: Ai4PoorsChannel = viewModel.contentType == .image ? .screenshot : .share
                HistoryService.save(
                    channel: shareChannel,
                    action: action,
                    inputPreview: viewModel.contentType == .image ? "[Shared Image]" : viewModel.sharedText,
                    result: result,
                    model: OpenRouterService.routeModel(for: instruction),
                    customInstruction: customInstruction
                )

                await MainActor.run {
                    viewModel.result = result
                    viewModel.isAnalyzing = false
                }
            } catch {
                await MainActor.run {
                    viewModel.error = error.localizedDescription
                    viewModel.isAnalyzing = false
                }
            }
        }
    }
}

// MARK: - View Model

class ShareExtensionViewModel: ObservableObject {
    @Published var sharedText = ""
    @Published var sharedImage: UIImage?
    @Published var contentType: SharedContentType?
    @Published var isAnalyzing = false
    @Published var result: String?
    @Published var error: String?

    enum SharedContentType {
        case text, url, image
    }
}

// MARK: - Share Extension SwiftUI View

struct ShareExtensionView: View {
    @ObservedObject var viewModel: ShareExtensionViewModel

    let onAnalyze: (Ai4PoorsAction, String?) -> Void
    let onDismiss: () -> Void

    @State private var selectedAction: Ai4PoorsAction = .summarize
    @State private var customInstruction = ""
    @State private var copied = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    contentPreview
                    actionPicker

                    if selectedAction == .custom {
                        TextField("Custom instruction...", text: $customInstruction)
                            .textFieldStyle(.roundedBorder)
                            .padding(.horizontal)
                    }

                    if viewModel.isAnalyzing {
                        ProgressView("Analyzing...")
                            .padding()
                    }

                    if let result = viewModel.result {
                        resultSection(result)
                    }

                    if let error = viewModel.error {
                        Text(error)
                            .font(.caption)
                            .foregroundStyle(.red)
                            .padding()
                    }

                    if viewModel.result == nil && !viewModel.isAnalyzing {
                        Button {
                            let instruction = selectedAction == .custom ? customInstruction : nil
                            onAnalyze(selectedAction, instruction)
                        } label: {
                            Label("Analyze", systemImage: "sparkle")
                                .font(.headline)
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(viewModel.contentType == nil)
                        .padding(.horizontal)
                    }
                }
                .padding(.vertical)
            }
            .navigationTitle("Ai4Poors")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close", action: onDismiss)
                }
            }
        }
    }

    private var contentPreview: some View {
        Group {
            switch viewModel.contentType {
            case .text, .url:
                Text(viewModel.sharedText)
                    .font(.caption)
                    .lineLimit(5)
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color(UIColor.secondarySystemGroupedBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .padding(.horizontal)

            case .image:
                if let image = viewModel.sharedImage {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFit()
                        .frame(maxHeight: 150)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                        .padding(.horizontal)
                }

            case .none:
                Text("No content detected")
                    .foregroundStyle(.secondary)
                    .padding()
            }
        }
    }

    private var actionPicker: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach([Ai4PoorsAction.summarize, .translate, .explain, .extract, .improve, .custom], id: \.self) { action in
                    Button {
                        selectedAction = action
                    } label: {
                        Label(action.displayName, systemImage: action.iconName)
                            .font(.caption)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(selectedAction == action ? Color.blue : Color(UIColor.secondarySystemGroupedBackground))
                            .foregroundStyle(selectedAction == action ? .white : .primary)
                            .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal)
        }
    }

    private func resultSection(_ result: String) -> some View {
        VStack(spacing: 8) {
            MarkdownText(result, font: .subheadline)
                .textSelection(.enabled)
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(UIColor.secondarySystemGroupedBackground))
                .clipShape(RoundedRectangle(cornerRadius: 8))

            HStack(spacing: 12) {
                Button {
                    UIPasteboard.general.string = result
                    copied = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2) { copied = false }
                } label: {
                    Label(copied ? "Copied" : "Copy", systemImage: copied ? "checkmark" : "doc.on.doc")
                }
                .buttonStyle(.bordered)

                Button("Done", action: onDismiss)
                    .buttonStyle(.borderedProminent)
            }
        }
        .padding(.horizontal)
    }
}
