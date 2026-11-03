import PaneKit
import SwiftUI

/// Settings › TVs: each TV used, renamed, re-addressed or removed, then the way to the add screen.
/// The Mac's Preferences › TV, for touch.
struct TVListView: View {
    let model: AppModel
    /// Only one row is open at a time.
    @State private var editing: UUID?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            SectionLabel("TVs")
            if model.store.tvs.isEmpty { SettingsNote("No TV yet.") }
            ForEach(model.store.tvs) { tv in
                TVRow(model: model, tv: tv, editing: $editing)
            }
            NavigationLink {
                AddTVScreen(model: model)
            } label: {
                HStack {
                    Text("Add a TV")
                    Spacer(minLength: 8)
                    Image(systemName: "chevron.right").font(.system(size: 11, weight: .semibold))
                }
                .font(.manrope(12))
                .frame(minHeight: 44)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
    }
}

/// The add screen on its own page: the search runs only while it is shown.
private struct AddTVScreen: View {
    let model: AppModel
    @Environment(\.palette) private var palette

    var body: some View {
        ScrollView {
            AddTVView(model: model).padding(Metrics.gutter)
        }
        .background(palette.bg)
        .navigationTitle(Text("Add a TV"))
        .navigationBarTitleDisplayMode(.inline)
    }
}

/// One TV: its line, and under it the editor when it is the open one.
private struct TVRow: View {
    let model: AppModel
    let tv: TVConfig
    @Binding var editing: UUID?
    @State private var name = ""
    @State private var address = ""
    @State private var token = ""
    @State private var originalToken = ""
    @State private var originalAddress = ""
    @State private var problem: String?
    @State private var confirmsRemoval = false
    @Environment(\.palette) private var palette

    /// During the demo, no saved TV is the active one.
    private var isActive: Bool { model.activeID == tv.id }
    private var isOpen: Bool { editing == tv.id }
    private var addressText: String { "\(tv.host):\(tv.port)" }

    var body: some View {
        PreferencesRow {
            VStack(alignment: .leading, spacing: 0) {
                line
                if isOpen { editor }
            }
        }
        .confirmationDialog(String(localized: "Remove \(tv.name)?"), isPresented: $confirmsRemoval, titleVisibility: .visible) {
            Button("Remove", role: .destructive) {
                editing = nil
                model.remove(tv.id)
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Its pinned buttons and custom actions go with it.")
        }
    }

    private var line: some View {
        HStack(spacing: 10) {
            ZStack { if isActive { OnDot(size: 6) } }.frame(width: 6)
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: tv.name).font(.manrope(12)).lineLimit(1)
                Text(verbatim: addressText).font(.manrope(10.5)).foregroundStyle(palette.label).lineLimit(1)
            }
            Spacer(minLength: 8)
            Group {
                if !isActive { Button("Use") { model.activate(tv.id) } }
                Button("Edit") { isOpen ? close() : open() }
            }
            .buttonStyle(TextButtonStyle())
            .frame(minWidth: 44, minHeight: 44)
        }
        .frame(minHeight: 52)
    }

    private var editor: some View {
        VStack(alignment: .leading, spacing: 0) {
            Field(title: "Name", text: $name, prompt: "")
            Field(title: "Address", text: $address, prompt: "192.168.1.20")
                .keyboardType(.URL)
                .textInputAutocapitalization(.never)
                .padding(.top, 12)
            Field(title: "Token", text: $token, prompt: String(localized: "Optional"), secure: true)
                .padding(.top, 12)
            NavigationLink {
                TVFinder(model: model, tv: tv)
            } label: {
                HStack {
                    Text("Find it on this network")
                    Spacer(minLength: 8)
                    Image(systemName: "chevron.right").font(.system(size: 11, weight: .semibold))
                }
                .font(.manrope(11))
                .frame(minHeight: 44)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .padding(.top, 6)
            Text(verbatim: problem ?? " ")
                .font(.manrope(10.5))
                .foregroundStyle(palette.label)
                .padding(.top, 8)
            HStack(spacing: 14) {
                GHButton("Save", action: save).frame(minWidth: 120, maxWidth: 140)
                Button("Cancel", action: close).frame(minHeight: 44)
                Spacer(minLength: 8)
                Button("Remove…") { confirmsRemoval = true }.frame(minHeight: 44)
            }
            .buttonStyle(TextButtonStyle())
            .padding(.top, 6)
            .padding(.bottom, 12)
        }
        .onChange(of: address) { problem = nil }
        .onChange(of: addressText) { if isOpen { close() } }
    }

    private func open() {
        name = tv.name
        address = addressText
        originalAddress = addressText
        originalToken = model.store.token(for: tv.id) ?? ""
        token = originalToken
        problem = nil
        editing = tv.id
    }

    private func close() {
        editing = nil
        problem = nil
    }

    /// One `edit`: the name, the address (refused when another TV has it; a link's token comes with
    /// it), and the token only if its trimmed value differs from the original (empty deletes it).
    private func save() {
        let newName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let newAddress = address.trimmingCharacters(in: .whitespacesAndNewlines)
        var parsed: TVAddress?
        if newAddress != originalAddress {
            guard let value = TVAddress.parse(newAddress) else {
                problem = String(localized: "Not an address")
                return
            }
            if let other = model.store.owner(host: value.host, port: value.port, excluding: tv.id) {
                problem = String(localized: "\(other.name) already uses this address")
                return
            }
            parsed = value
        }
        let newToken = token.trimmingCharacters(in: .whitespacesAndNewlines)
        let changed = newToken != originalToken.trimmingCharacters(in: .whitespacesAndNewlines)
        model.edit(tv.id, name: newName, address: parsed, token: changed ? .some(newToken.isEmpty ? nil : newToken) : nil)
        close()
    }
}

// MARK: Finding a TV

/// The search by hand for a TV that is no longer at its address: the Glasshouse servers on this
/// network, where a touch gives the TV that address. Its token, if it has one, goes to the new
/// address only then, by the user's choice: the search itself sends it nowhere new.
struct TVFinder: View {
    let model: AppModel
    let tv: TVConfig
    @State private var search: DiscoverySearch
    @Environment(\.palette) private var palette
    /// Back to the TV list, or the sheet closed, once the TV has its new address.
    @Environment(\.dismiss) private var dismiss

    init(model: AppModel, tv: TVConfig) {
        self.model = model
        self.tv = tv
        _search = State(initialValue: DiscoverySearch(model: model))
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                Text(verbatim: tv.name).font(.manrope(19, .light)).padding(.bottom, 4)
                SettingsNote("Saved at \(tv.host):\(String(tv.port)). Touch the server that is this TV to give it its new address.")
                    .padding(.bottom, 18)
                HStack(alignment: .firstTextBaseline) {
                    Text("On this network").sectionLabelStyle()
                    Spacer(minLength: 8)
                    Button("Search again") { search.start() }
                        .buttonStyle(TextButtonStyle())
                        .frame(minHeight: 44)
                        .disabled(search.phase == .searching)
                }
                ForEach(candidates) { candidate in
                    FinderRow(model: model, tv: tv, candidate: candidate) {
                        model.edit(tv.id, name: "", address: TVAddress(host: candidate.host, port: candidate.port, token: nil),
                                   token: nil)
                        dismiss()
                    }
                }
                status
            }
            .padding(Metrics.gutter)
        }
        .background(palette.bg)
        .navigationTitle(Text("Find \(tv.name)"))
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { search.start() }
        .onChange(of: model.foregroundReturns) { search.retryAfterReturn() }
        .onDisappear { search.cancel() }
    }

    /// The Glasshouse servers found, at the port they answered on; not the TV's own address.
    private var candidates: [Candidate] {
        search.results.compactMap { found in
            let candidate: Candidate
            switch found.outcome {
            case .found(let server): candidate = Candidate(host: server.host, port: server.port, model: server.shortModel)
            // The search asks the default port.
            case .needsToken, .badToken: candidate = Candidate(host: found.host, port: TVAddress.defaultPort, model: nil)
            default: return nil
            }
            return candidate.host == tv.host && candidate.port == tv.port ? nil : candidate
        }
    }

    @ViewBuilder private var status: some View {
        switch search.phase {
        case .denied:
            LocalNetworkBlockedView().padding(.top, 12)
        case .searching:
            SettingsNote("Searching…").padding(.top, 10)
        case .finished where candidates.isEmpty:
            SettingsNote("No other Glasshouse server found. Check that the TV is on and search again, or type its new address in Settings › TVs.")
                .padding(.top, 10)
        default:
            EmptyView()
        }
    }
}

/// A Glasshouse server the search found.
private struct Candidate: Identifiable {
    let host: String
    let port: Int
    let model: String?
    var id: String { host }
}

/// A server found: its model and address, and Use, unless another saved TV has that address.
private struct FinderRow: View {
    let model: AppModel
    let tv: TVConfig
    let candidate: Candidate
    let use: () -> Void
    @Environment(\.palette) private var palette

    var body: some View {
        let owner = model.store.owner(host: candidate.host, port: candidate.port, excluding: tv.id)
        PreferencesRow {
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 2) {
                    if let name = candidate.model {
                        Text(verbatim: name).font(.manrope(12))
                    } else {
                        Text("Glasshouse TV").font(.manrope(12))
                    }
                    Text(verbatim: "\(candidate.host):\(String(candidate.port))")
                        .font(.manrope(10.5))
                        .foregroundStyle(palette.label)
                }
                .lineLimit(1)
                Spacer(minLength: 8)
                if let owner {
                    Text(verbatim: owner.name).font(.manrope(10.5)).foregroundStyle(palette.label)
                } else {
                    GHButton("Use", action: use).frame(width: 96)
                }
            }
            .padding(.vertical, 6)
        }
    }
}

/// The search by hand, from Remote, in its own sheet.
struct TVFinderSheet: View {
    let model: AppModel
    let tv: TVConfig
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let palette = Palette.of(colorScheme)
        NavigationStack {
            TVFinder(model: model, tv: tv)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") { dismiss() }.font(.manrope(13))
                    }
                }
        }
        .font(.manrope(11))
        .foregroundStyle(palette.fg)
        .tint(palette.fg)
        .environment(\.palette, palette)
        .presentationBackground(palette.bg)
        .preferredColorScheme(model.theme.colorScheme)
    }
}
