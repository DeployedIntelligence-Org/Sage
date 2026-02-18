import SwiftUI

/// App settings screen — currently focused on Anthropic API key management.
struct SettingsView: View {

    @StateObject private var vm = SettingsViewModel()
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                apiKeySection
                aboutSection
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .alert("Saved", isPresented: $vm.showSavedConfirmation) {
                Button("OK", role: .cancel) {}
            } message: {
                Text("Your API key has been saved securely in the Keychain.")
            }
            .alert("Error", isPresented: $vm.showError) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(vm.errorMessage ?? "An unknown error occurred.")
            }
        }
    }

    // MARK: - API Key Section

    private var apiKeySection: some View {
        Section {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Label("Anthropic API Key", systemImage: "key.fill")
                        .font(.subheadline)
                        .fontWeight(.medium)

                    Spacer()

                    // Status indicator
                    if vm.isKeyStored {
                        Label("Saved", systemImage: "checkmark.circle.fill")
                            .font(.caption)
                            .foregroundStyle(.green)
                    } else {
                        Label("Not set", systemImage: "exclamationmark.circle")
                            .font(.caption)
                            .foregroundStyle(.orange)
                    }
                }

                SecureField("sk-ant-api03-...", text: $vm.apiKeyDraft)
                    .textFieldStyle(.plain)
                    .font(.system(.body, design: .monospaced))
                    .padding(10)
                    .background(Color(.secondarySystemBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .textContentType(.password)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)

                HStack(spacing: 10) {
                    Button(action: vm.saveKey) {
                        Label("Save", systemImage: "square.and.arrow.down")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(vm.apiKeyDraft.trimmingCharacters(in: .whitespaces).isEmpty)

                    if vm.isKeyStored {
                        Button(role: .destructive, action: vm.deleteKey) {
                            Label("Remove", systemImage: "trash")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                    }
                }
                .controlSize(.small)
            }
            .padding(.vertical, 4)
        } header: {
            Text("Claude API")
        } footer: {
            Text("Your key is stored securely in the iOS Keychain and never leaves this device. Get a key at console.anthropic.com.")
        }
    }

    // MARK: - About Section

    private var aboutSection: some View {
        Section("About") {
            LabeledContent("Version", value: Bundle.main.appVersionString)
            LabeledContent("Model", value: Config.Claude.defaultModel)
        }
    }
}

// MARK: - Bundle Helper

private extension Bundle {
    var appVersionString: String {
        let version = infoDictionary?["CFBundleShortVersionString"] as? String ?? "—"
        let build   = infoDictionary?["CFBundleVersion"] as? String ?? "—"
        return "\(version) (\(build))"
    }
}

#Preview {
    SettingsView()
}
