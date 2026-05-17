import SwiftUI

struct PreferencesView: View {
    @ObservedObject var settings: AppSettings

    @State private var revealAPIKey: Bool = false
    @State private var customModelInput: String = ""
    @State private var showCustomModelInput: Bool = false
    @State private var lastNonAddModelSelection: String = ""

    private let addModelOption = "__add_model_option__"

    var body: some View {
        VStack(spacing: 0) {
            Form {
                Section("Groq") {
                    HStack(alignment: .center, spacing: 8) {
                        Group {
                            if revealAPIKey {
                                TextField("API Key", text: $settings.apiKey)
                            } else {
                                SecureField("API Key", text: $settings.apiKey)
                            }
                        }
                        .textFieldStyle(.roundedBorder)

                        Button {
                            revealAPIKey.toggle()
                        } label: {
                            Image(systemName: revealAPIKey ? "eye.slash" : "eye")
                        }
                        .buttonStyle(.borderless)
                        .help(revealAPIKey ? "Hide API key" : "Show API key")
                    }
                    .onChange(of: settings.apiKey) { _, _ in
                        settings.saveAPIKey()
                    }

                    HStack {
                        Text("Need a key?")
                            .foregroundStyle(.secondary)
                        Button("Get API key") {
                            if let url = URL(string: "https://console.groq.com/keys") {
                                NSWorkspace.shared.open(url)
                            }
                        }
                        .buttonStyle(.link)
                    }

                    Picker("Vision model", selection: $settings.selectedModel) {
                        ForEach(settings.availableModels, id: \.self) { model in
                            Text(model).tag(model)
                        }
                        Divider()
                        Text("Add model…").tag(addModelOption)
                    }
                    .onChange(of: settings.selectedModel) { _, value in
                        if value == addModelOption {
                            showCustomModelInput = true
                            let fallback = lastNonAddModelSelection.isEmpty
                                ? (settings.availableModels.first ?? "")
                                : lastNonAddModelSelection
                            DispatchQueue.main.async {
                                settings.selectedModel = fallback
                            }
                        } else {
                            lastNonAddModelSelection = value
                        }
                    }

                    if showCustomModelInput {
                        HStack {
                            TextField("Paste model name", text: $customModelInput)
                            Button("Add") {
                                let previous = settings.availableModels.first ?? ""
                                settings.addModel(customModelInput)
                                if settings.selectedModel != addModelOption {
                                    showCustomModelInput = false
                                    customModelInput = ""
                                } else {
                                    settings.selectedModel = previous
                                }
                            }
                            .disabled(customModelInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                            Button("Cancel") {
                                showCustomModelInput = false
                                customModelInput = ""
                                settings.selectedModel = settings.availableModels.first ?? ""
                            }
                        }
                    }
                }

                Section("Behavior") {
                    TextField("Watch folder", text: $settings.watchFolderPath)
                    Button("Grant Folder Access") {
                        _ = settings.requestWatchFolderAccess()
                    }
                    Picker("HUD position", selection: Binding(
                        get: { settings.hudPosition },
                        set: { settings.hudPosition = $0 }
                    )) {
                        ForEach(HUDPosition.allCases) { position in
                            Text(position.title).tag(position)
                        }
                    }
                    HStack {
                        Text("Auto-dismiss seconds")
                        Slider(value: $settings.autoDismissSeconds, in: 2...20, step: 1)
                        Text("\(Int(settings.autoDismissSeconds))")
                            .frame(width: 30)
                    }
                }
            }
            .formStyle(.grouped)

            Divider()

            HStack {
                Spacer()
                Button("Quit Service") {
                    NSApplication.shared.terminate(nil)
                }
                .keyboardShortcut("q", modifiers: [.command])
            }
            .padding(12)
        }
        .padding(16)
        .frame(width: 520)
        .onAppear {
            if settings.selectedModel != addModelOption {
                lastNonAddModelSelection = settings.selectedModel
            }
        }
    }
}
