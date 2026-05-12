import SwiftUI

struct PreferencesView: View {
    @ObservedObject var settings: AppSettings

    var body: some View {
        Form {
            Section("Groq") {
                TextField("API Key", text: $settings.apiKey)
                    .onChange(of: settings.apiKey) { _, _ in
                        settings.saveAPIKey()
                    }
                TextField("Vision model", text: $settings.selectedModel)
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
        .padding(16)
        .frame(width: 460)
    }
}
