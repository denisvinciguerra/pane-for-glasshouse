import AppKit
import PaneKit
import SwiftUI

/// The add screen: the TVs found on the network, then an address or a dashboard link with its
/// token. It takes the width it is given (the popover's, or the preferences pane's).
struct AddTVView: View {
    let model: AppModel
    @State private var search: DiscoverySearch
    @State private var address = ""
    @State private var token = ""
    @State private var showsToken = false
    @State private var failure: ProbeOutcome?
    @State private var adding = false
    /// Add or Enter was pressed: only then is an unreadable address reported.
    @State private var submitted = false
    @State private var probeTask: Task<Void, Never>?
    @Environment(\.palette) private var palette

    init(model: AppModel) {
        self.model = model
        _search = State(initialValue: DiscoverySearch(model: model))
    }

    private var parsed: TVAddress? { TVAddress.parse(address) }
    private var unreadable: Bool {
        !address.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && parsed == nil
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            ForEach(search.results, id: \.host) { found in
                ResultRow(model: model, found: found) { fill(host: found.host) }
            }
            searchStatus
            Field(title: "Address or dashboard link", text: $address, prompt: String(localized: "192.168.1.20 or http://…/?k=…"))
                .padding(.top, 14)
            if showsToken {
                Field(title: "Token", text: $token, prompt: String(localized: "Optional"), secure: true)
                    .padding(.top, 12)
            }
            GHButton(adding ? "Connecting…" : "Add", action: add)
                .disabled(address.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || adding)
                .keyboardShortcut(.defaultAction)
                .padding(.top, 12)
            errorLine
        }
        .onAppear { search.start() }
        .onDisappear {
            search.cancel()
            probeTask?.cancel()
            adding = false
        }
        .onChange(of: address) {
            failure = nil
            submitted = false
        }
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            Text("On this network").sectionLabelStyle()
            Spacer(minLength: 8)
            Button("Search again") { search.start() }
                .buttonStyle(TextButtonStyle())
                .disabled(search.phase == .searching)
        }
        .padding(.bottom, 7)
    }

    @ViewBuilder private var searchStatus: some View {
        if search.phase == .denied || failure == .localNetworkDenied {
            // Once, whichever of the search or the manual probe met the refusal.
            LocalNetworkBlockedView().padding(.top, 12)
        } else {
            switch search.phase {
            case .searching:
                statusText("Searching…")
            case .finished where search.results.isEmpty:
                statusText("No TV found. Type its address below.")
            default:
                EmptyView()
            }
        }
    }

    private func statusText(_ text: LocalizedStringKey) -> some View {
        Text(text)
            .font(.manrope(10.5))
            .foregroundStyle(palette.label)
            .padding(.top, 8)
    }

    /// Keeps its height when empty, so the button does not jump.
    private var errorLine: some View {
        Group {
            Text(verbatim: errorText ?? " ")
                .font(.manrope(10.5))
                .foregroundStyle(palette.label)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, minHeight: 30, alignment: .leading)
    }

    private var errorText: String? {
        if submitted && unreadable { return String(localized: "Not an address") }
        switch failure {
        case .unreachable: return String(localized: "Can’t reach this address")
        case .notGlasshouse: return String(localized: "No Glasshouse server answered at this address")
        case .needsToken: return String(localized: "This TV needs its token")
        case .badToken: return String(localized: "Wrong or missing token")
        default: return nil
        }
    }

    /// "Token needed" on a result: its host goes in the address field (bare when on 8080).
    private func fill(host: String) {
        address = host
        showsToken = true
        failure = nil
    }

    private func add() {
        submitted = true
        guard let target = parsed, !adding else { return }
        let typed = token.trimmingCharacters(in: .whitespacesAndNewlines)
        let used = typed.isEmpty ? target.token : typed
        // Only the stored token of this very address is ever tried.
        let known = model.store.token(forHost: target.host, port: target.port).map { [$0] } ?? []
        adding = true
        failure = nil
        probeTask?.cancel()
        probeTask = Task {
            let outcome = await model.probe.probe(host: target.host, port: target.port, token: used, knownTokens: known)
            adding = false
            guard !Task.isCancelled else { return }
            switch outcome {
            case .found(let found):
                model.add(found)
                address = ""
                token = ""
                showsToken = false
            case .needsToken, .badToken:
                showsToken = true
                failure = outcome
            default:
                failure = outcome
            }
        }
    }
}

/// One TV found: its model and address, and what a click does.
private struct ResultRow: View {
    let model: AppModel
    let found: DiscoveredTV
    let askToken: () -> Void
    @Environment(\.palette) private var palette

    var body: some View {
        PreferencesRow {
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 1) {
                    switch found.outcome {
                    case .found(let tv):
                        if let name = tv.shortModel, !name.isEmpty {
                            Text(verbatim: name)
                        } else {
                            Text("Glasshouse TV")
                        }
                        Text(verbatim: "\(tv.host):\(tv.port)").font(.manrope(10.5)).foregroundStyle(palette.label)
                    default:
                        Text("Glasshouse TV")
                        Text(verbatim: "\(found.host):8080").font(.manrope(10.5)).foregroundStyle(palette.label)
                    }
                }
                .lineLimit(1)
                Spacer(minLength: 8)
                trailing
            }
            .padding(.vertical, 8)
        }
    }

    @ViewBuilder private var trailing: some View {
        switch found.outcome {
        case .found(let tv):
            switch state(of: tv) {
            case .add: GHButton("Add", height: 26) { model.add(tv) }.frame(width: 84)
            case .update: GHButton("Update", height: 26) { model.add(tv) }.frame(width: 84)
            case .added: Text("Added").font(.manrope(10.5)).foregroundStyle(palette.label)
            }
        case .needsToken:
            Button("Token needed", action: askToken).buttonStyle(TextButtonStyle())
        default:
            EmptyView()
        }
    }

    private enum RowState { case add, update, added }

    private func state(of tv: FoundTV) -> RowState {
        let store = model.store
        guard let match = store.match(tv) else { return .add }
        if match.host != tv.host || match.port != tv.port || store.token(for: match.id) != tv.token { return .update }
        return .added
    }
}

/// A labelled text field: square, a 1 pt edge, full strength while focused.
struct Field: View {
    let title: LocalizedStringKey
    @Binding var text: String
    let prompt: String
    var secure = false
    @Environment(\.palette) private var palette
    @FocusState private var focused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            SectionLabel(title)
            Group {
                if secure {
                    SecureField(text: $text, prompt: Text(verbatim: prompt).foregroundStyle(palette.fg.opacity(0.35))) {
                        Text(title)
                    }
                } else {
                    TextField(text: $text, prompt: Text(verbatim: prompt).foregroundStyle(palette.fg.opacity(0.35))) {
                        Text(title)
                    }
                }
            }
            .textFieldStyle(.plain)
            .font(.manrope(12))
            .foregroundStyle(palette.fg)
            .autocorrectionDisabled()
            .focused($focused)
            .focusEffectDisabled()
            .padding(.horizontal, 8)
            .frame(height: 30)
            .overlay(Rectangle().strokeBorder(focused ? palette.fg : palette.line, lineWidth: 1))
        }
    }
}
