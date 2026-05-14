import SwiftUI

struct HUDView: View {
    let image: NSImage
    @Binding var prompt: String
    let isLoading: Bool
    let responseText: String
    let showResponse: Bool
    let onPromptChanged: () -> Void
    let onAsk: () -> Void
    let onDismiss: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Image(nsImage: image)
                .resizable()
                .scaledToFit()
                .frame(maxWidth: .infinity)
                .frame(height: 170)
                .clipShape(RoundedRectangle(cornerRadius: 10))

            TextField("Ask about this screenshot", text: $prompt)
                .textFieldStyle(.plain)
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(
                    RoundedRectangle(cornerRadius: 10)
                        .fill(Color.white.opacity(0.08))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(Color.white.opacity(0.14), lineWidth: 1)
                )
                .onChange(of: prompt) { _, _ in
                    onPromptChanged()
                }
                .onSubmit {
                    onAsk()
                }
                .submitLabel(.send)

            if showResponse {
                Divider().overlay(Color.white.opacity(0.12))
                ScrollView {
                    Text(responseText.isEmpty ? "Thinking..." : responseText)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .foregroundStyle(.white.opacity(0.95))
                        .textSelection(.enabled)
                }
                .frame(minHeight: 160, maxHeight: 260)
            }

            HStack {
                Button("Dismiss", action: onDismiss)
                Spacer()
                Button(isLoading ? "Asking..." : "Ask AI", action: onAsk)
                    .disabled(prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isLoading)
            }
        }
        .padding(14)
        .frame(width: 460)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}
