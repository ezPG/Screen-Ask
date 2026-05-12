import SwiftUI

struct HUDView: View {
    let image: NSImage
    @Binding var prompt: String
    let isLoading: Bool
    let onPromptChanged: () -> Void
    let onAsk: () -> Void
    let onDismiss: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Image(nsImage: image)
                .resizable()
                .scaledToFit()
                .frame(width: 280, height: 160)
                .clipShape(RoundedRectangle(cornerRadius: 8))

            TextField("Ask about this screenshot", text: $prompt)
                .textFieldStyle(.roundedBorder)
                .onChange(of: prompt) { _, _ in
                    onPromptChanged()
                }

            HStack {
                Button("Dismiss", action: onDismiss)
                Spacer()
                Button(isLoading ? "Asking..." : "Ask AI", action: onAsk)
                    .disabled(prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isLoading)
            }
        }
        .padding(14)
        .frame(width: 320)
    }
}
