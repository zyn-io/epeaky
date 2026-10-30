import SwiftUI

/// The first screen: the terms once, then which den to open.
struct StartView: View {
    @ObservedObject var state: AppState
    @State private var typed = ""
    @FocusState private var typing: Bool

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                HStack(spacing: 12) {
                    Image("Mark").resizable().frame(width: 44, height: 44).clipShape(RoundedRectangle(cornerRadius: 10))
                    Text("Epeaky").font(.largeTitle.weight(.semibold))
                }
                .padding(.top, 36)

                Text("End-to-end encrypted chat. Each den is run by its host, who sees who is in which room and when, never the words.")
                    .font(.callout).foregroundStyle(.secondary)

                if !state.agreed {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("No objectionable content or abusive behaviour. You can report a message to a den's moderators and block a member; moderators act on reports.")
                            .font(.callout)
                            .accessibilityIdentifier("terms")
                        Link("Terms of use", destination: Epeaky.terms).font(.callout)
                    }
                    .padding(14)
                    .background(RoundedRectangle(cornerRadius: 12).fill(Color.white.opacity(0.06)))
                }

                Button {
                    state.agree()
                    state.open(DenLink(origin: Epeaky.defaultDen))
                } label: {
                    Text(state.agreed ? "Open gen-epeaky" : "Agree and open gen-epeaky").frame(maxWidth: .infinity).padding(.vertical, 6)
                }
                .buttonStyle(.borderedProminent)
                .accessibilityIdentifier("open-default")

                VStack(alignment: .leading, spacing: 8) {
                    Text("Another den").font(.headline)
                    TextField("Den address or invite link", text: $typed)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .keyboardType(.URL)
                        .submitLabel(.go)
                        .focused($typing)
                        .padding(12)
                        .background(RoundedRectangle(cornerRadius: 10).fill(Color.white.opacity(0.06)))
                        .onSubmit(openTyped)
                        .accessibilityIdentifier("den-address")
                    if let e = state.error { Text(e).font(.footnote).foregroundStyle(.red) }
                    Button(state.agreed ? "Open" : "Agree and open", action: openTyped)
                        .buttonStyle(.bordered)
                        .disabled(typed.trimmingCharacters(in: .whitespaces).isEmpty)
                        .accessibilityIdentifier("open-typed")
                }

                if !state.dens.isEmpty {
                    VStack(alignment: .leading, spacing: 0) {
                        Text("Your dens").font(.headline).padding(.bottom, 8)
                        ForEach(state.dens, id: \.self) { d in
                            Button { state.open(d) } label: {
                                HStack { Text(d.host).foregroundStyle(.primary); Spacer(); Image(systemName: "chevron.right").foregroundStyle(.secondary) }
                                    .padding(.vertical, 12)
                            }
                            .contextMenu { Button("Remove from this list", role: .destructive) { state.forget(d) } }
                            Divider()
                        }
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 40)
        }
        .scrollDismissesKeyboard(.interactively)
    }

    private func openTyped() {
        guard !typed.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        state.agree()
        state.open(text: typed)
    }
}
