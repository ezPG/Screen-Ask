import SwiftUI

struct HUDView: View {
    let image: NSImage
    @Binding var prompt: String
    let isLoading: Bool
    let chatMessages: [HUDState.ChatMessage]
    let onPromptChanged: () -> Void
    let onAsk: () -> Void
    let onDismiss: () -> Void

    @FocusState private var isPromptFocused: Bool
    private var hasConversation: Bool { !chatMessages.isEmpty }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Button {
                    onDismiss()
                } label: {
                    Image(systemName: "xmark")
                }
                .buttonStyle(.plain)
                .help("Close")

                Spacer()

                SettingsLink {
                    Image(systemName: "gearshape")
                }
                .buttonStyle(.plain)
                .help("Open Settings")
            }

            Image(nsImage: image)
                .resizable()
                .scaledToFit()
                .frame(maxWidth: .infinity)
                .frame(height: 170)
                .clipShape(RoundedRectangle(cornerRadius: 10))

            if hasConversation {
                Divider().overlay(Color.white.opacity(0.12))

                ScrollViewReader { proxy in
                    ScrollView {
                        VStack(alignment: .leading, spacing: 10) {
                            ForEach(chatMessages) { message in
                                HStack {
                                    if message.role == "assistant" { Spacer(minLength: 24) }
                                    Text(message.text.isEmpty && message.role == "assistant" ? "Thinking..." : message.text)
                                        .padding(.horizontal, 12)
                                        .padding(.vertical, 10)
                                        .foregroundStyle(.white.opacity(0.96))
                                        .background(
                                            RoundedRectangle(cornerRadius: 12)
                                                .fill(message.role == "assistant" ? Color.white.opacity(0.10) : Color.blue.opacity(0.35))
                                        )
                                        .textSelection(.enabled)
                                    if message.role == "user" { Spacer(minLength: 24) }
                                }
                                .id(message.id)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .frame(minHeight: 160, maxHeight: 260)
                    .onChange(of: chatMessages.count) { _, _ in
                        if let lastID = chatMessages.last?.id {
                            withAnimation(.easeOut(duration: 0.2)) {
                                proxy.scrollTo(lastID, anchor: .bottom)
                            }
                        }
                    }
                }
            }

            HStack {
                Button("Dismiss", action: onDismiss)
                Spacer()
                HStack(spacing: 8) {
                    TextField("Ask about this screenshot", text: $prompt)
                        .textFieldStyle(.plain)
                        .focused($isPromptFocused)
                        .onChange(of: prompt) { _, _ in
                            onPromptChanged()
                        }
                        .onSubmit {
                            onAsk()
                        }
                        .submitLabel(.send)

                    Button(action: onAsk) {
                        Image(systemName: "arrow.up.circle.fill")
                            .font(.system(size: 20))
                    }
                    .buttonStyle(.plain)
                    .disabled(prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isLoading)
                }
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
                .frame(maxWidth: 350)
            }
        }
        .padding(14)
        .frame(width: 460)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .onAppear {
            isPromptFocused = true
        }
        .onExitCommand {
            onDismiss()
        }
    }
}
