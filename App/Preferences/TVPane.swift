import PaneKit
import SwiftUI

/// Preferences › TV: the TVs, each used, renamed, re-addressed or removed, then the add screen.
struct TVPane: View {
    let model: AppModel
    /// Only one row is open at a time.
    @State private var editing: UUID?
    @Environment(\.palette) private var palette

    var body: some View {
        PreferencesScroll {
            VStack(alignment: .leading, spacing: 0) {
                SectionLabel("TVs")
                if model.store.tvs.isEmpty { PreferencesNote("No TV yet.") }
                ForEach(model.store.tvs) { tv in
                    TVRow(model: model, tv: tv, editing: $editing)
                }
            }
            VStack(alignment: .leading, spacing: 0) {
                SectionLabel("Add a TV")
                AddTVView(model: model)
            }
        }
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

    private var isActive: Bool { model.store.activeID == tv.id }
    private var isOpen: Bool { editing == tv.id }
    private var addressText: String { "\(tv.host):\(tv.port)" }

    var body: some View {
        PreferencesRow {
            VStack(alignment: .leading, spacing: 0) {
                line
                if isOpen { editor }
            }
        }
        .confirmationDialog(String(localized: "Remove \(tv.name)?"), isPresented: $confirmsRemoval) {
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
            Text(verbatim: tv.name).font(.manrope(12)).lineLimit(1)
            Text(verbatim: addressText).font(.manrope(10.5)).foregroundStyle(palette.label).lineLimit(1)
            Spacer(minLength: 8)
            Group {
                if !isActive { Button("Use") { model.activate(tv.id) } }
                Button("Edit") { isOpen ? close() : open() }
            }
            .buttonStyle(TextButtonStyle())
        }
        .frame(minHeight: 34)
    }

    private var editor: some View {
        VStack(alignment: .leading, spacing: 0) {
            Field(title: "Name", text: $name, prompt: "")
            Field(title: "Address", text: $address, prompt: "192.168.1.20")
                .padding(.top, 12)
            Field(title: "Token", text: $token, prompt: String(localized: "Optional"), secure: true)
                .padding(.top, 12)
            Text(verbatim: problem ?? " ")
                .font(.manrope(10.5))
                .foregroundStyle(palette.label)
                .padding(.top, 8)
            HStack(spacing: 14) {
                GHButton("Save", height: 26, action: save).frame(minWidth: 120, maxWidth: 140)
                Button("Cancel", action: close)
                Spacer(minLength: 8)
                Button("Remove…") { confirmsRemoval = true }
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
