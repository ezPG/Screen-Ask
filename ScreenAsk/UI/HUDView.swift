import SwiftUI

struct HUDView: View {
    let images: [URL: NSImage]
    let contextURLs: [URL]
    @Binding var prompt: String
    let isLoading: Bool
    let chatMessages: [HUDState.ChatMessage]
    let onPromptChanged: () -> Void
    let onAsk: () -> Void
    let onDismiss: () -> Void
    let onRemoveImage: (URL) -> Void
    let onDeleteImage: (URL) -> Void

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

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(contextURLs, id: \.self) { url in
                        if let img = images[url] {
                            ZStack(alignment: .topTrailing) {
                                Image(nsImage: img)
                                    .resizable()
                                    .scaledToFit()
                                    .frame(height: 170)
                                    .clipShape(RoundedRectangle(cornerRadius: 10))
                                
                                Button {
                                    onRemoveImage(url)
                                } label: {
                                    Image(systemName: "xmark.circle.fill")
                                        .foregroundStyle(.white, .black.opacity(0.6))
                                        .font(.system(size: 20))
                                }
                                .buttonStyle(.plain)
                                .padding(6)
                                .help("Remove from context")
                                
                                VStack {
                                    Spacer()
                                    HStack {
                                        Spacer()
                                        Button {
                                            onDeleteImage(url)
                                        } label: {
                                            Image(systemName: "trash.circle.fill")
                                                .foregroundStyle(.red, .black.opacity(0.6))
                                                .font(.system(size: 20))
                                        }
                                        .buttonStyle(.plain)
                                        .padding(6)
                                        .help("Delete image file")
                                    }
                                }
                            }
                        }
                    }
                }
            }
            .frame(height: 170)

            if hasConversation {
                Divider().overlay(Color.white.opacity(0.12))

                ScrollViewReader { proxy in
                    ScrollView {
                        VStack(alignment: .leading, spacing: 10) {
                            ForEach(chatMessages) { message in
                                HStack {
                                    if message.role == "assistant" { Spacer(minLength: 24) }
                                    VStack(alignment: message.role == "assistant" ? .trailing : .leading, spacing: 4) {
                                        Text(try! AttributedString(markdown: message.text.isEmpty && message.role == "assistant" ? "Thinking..." : message.text, options: AttributedString.MarkdownParsingOptions(interpretedSyntax: .inlineOnlyPreservingWhitespace)))
                                            .padding(.horizontal, 12)
                                            .padding(.vertical, 10)
                                            .foregroundStyle(.white.opacity(0.96))
                                            .background(
                                                RoundedRectangle(cornerRadius: 12)
                                                    .fill(message.role == "assistant" ? Color.white.opacity(0.10) : Color.blue.opacity(0.35))
                                            )
                                            .textSelection(.enabled)
                                            .tint(.blue) // Ensure links are blue and clickable
                                        
                                        if message.role == "assistant" && !message.text.isEmpty {
                                            Button {
                                                NSPasteboard.general.clearContents()
                                                NSPasteboard.general.setString(message.text, forType: .string)
                                            } label: {
                                                Image(systemName: "doc.on.doc")
                                                    .font(.system(size: 11))
                                                    .foregroundStyle(.white.opacity(0.6))
                                            }
                                            .buttonStyle(.plain)
                                            .padding(.trailing, 4)
                                            .help("Copy Response")
                                        }
                                    }
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
