import PaneKit
import SwiftUI

/// Makes or changes a custom action of the active TV: its title, then its steps in order, each a
/// kind, a target and, for a setting or the sleep timer, a value, then, once a step launches an
/// app, whether its pin shows that app's icon or the title. It edits its own copy: nothing
/// is stored before Save. The menus come from what the TV offers; Picture, Audio, Game and HDMI
/// are read when it appears. On iOS it fills its own sheet: it scrolls, Cancel and Save stand in
/// the navigation bar, Delete at the end; it has no global shortcut, iOS having none.
struct ActionEditorView: View {
    let model: AppModel
    private let draft: CustomAction
    private let onDone: () -> Void
    @State private var title: String
    @State private var steps: [StepDraft]
    /// `nil` until a choice is clicked: the default then follows the steps.
    @State private var tile: CustomAction.Tile?
    /// What the menus offer, kept here and replaced only when it changes: the editor never reads
    /// the session in its body, which each poll would draw again, rebuilding an open menu (on iOS
    /// it went back to its top every couple of seconds).
    @State private var menus: EditorMenus
    @Environment(\.palette) private var palette
    @FocusState private var titleFocused: Bool

    init(model: AppModel, draft: CustomAction, onDone: @escaping () -> Void) {
        self.model = model
        self.draft = draft
        self.onDone = onDone
        _title = State(initialValue: draft.title)
        _steps = State(initialValue: draft.steps.map(StepDraft.init))
        _tile = State(initialValue: draft.tile)
        // Empty until the reader fills it, as it appears: reading the session here would tie the
        // body that builds the editor to each poll.
        _menus = State(initialValue: EditorMenus(ActionContext(stats: nil, rows: [])))
    }

    /// Not stored yet for the active TV: it is pinned when saved, and cannot be deleted.
    private var isNew: Bool {
        guard let tv = model.activeID else { return true }
        return !model.actions.actions(for: tv).contains { $0.id == draft.id }
    }

    /// The steps, once each one has what it needs.
    private var completeSteps: [ActionStep]? {
        let list = steps.compactMap(\.step)
        return list.count == steps.count && !list.isEmpty ? list : nil
    }

    var body: some View {
        #if os(iOS)
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                form
                if !isNew {
                    GHButton("Delete") {
                        model.deleteAction(draft.id)
                        onDone()
                    }
                    .padding(.top, 6)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, Metrics.gutter)
            .padding(.vertical, 20)
        }
        .scrollDismissesKeyboard(.interactively)
        .navigationTitle(isNew ? Text("New action") : Text("Edit action"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel", action: onDone).font(.manrope(13))
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") { save() }
                    .font(.manrope(13, .semibold))
                    .disabled(completeSteps == nil)
            }
        }
        .background(EditorMenus.Reader(model: model) { menus = $0 })
        .task { await readSettings() }
        #else
        VStack(alignment: .leading, spacing: 0) {
            CappedScroll { form }
            HStack(spacing: 6) {
                if !isNew {
                    GHButton("Delete", height: 28) {
                        model.deleteAction(draft.id)
                        onDone()
                    }
                }
                GHButton("Cancel", height: 28, action: onDone)
                GHButton("Save", height: 28) { save() }
                    .disabled(completeSteps == nil)
            }
            .padding(.top, 14)
        }
        .background(EditorMenus.Reader(model: model) { menus = $0 })
        .task { await readSettings() }
        #endif
    }

    /// The title, the steps, the tile.
    private var form: some View {
        #if os(iOS)
        let spacing: CGFloat = 24
        #else
        let spacing: CGFloat = 14
        #endif
        return VStack(alignment: .leading, spacing: spacing) {
            titleField
            VStack(alignment: .leading, spacing: 0) {
                SectionLabel("Steps")
                ForEach($steps) { $step in
                    let number = (steps.firstIndex { $0.id == step.id } ?? 0) + 1
                    StepEditor(number: number, draft: $step, menus: menus) {
                        steps.removeAll { $0.id == step.id }
                    }
                    Hairline().opacity(0.6)
                }
                GHButton("+ Step", dashed: true, height: 28) { steps.append(StepDraft()) }
                    .padding(.top, 8)
            }
            tileChoice
        }
    }

    private var titleField: some View {
        let fallback = CustomAction.defaultTitle(steps.compactMap(\.step), sources: menus.sources)
        return VStack(alignment: .leading, spacing: 0) {
            #if os(macOS)
            // On iOS, the navigation bar's title.
            Group {
                if isNew { Text("New action") } else { Text("Edit action") }
            }
            .font(.manrope(13))
            .padding(.bottom, 10)
            #endif
            SectionLabel("Title")
            // A plain text field: the keys typed in it never reach the TV.
            TextField(text: $title, prompt: Text(verbatim: fallback).foregroundStyle(palette.fg.opacity(0.35))) {
                Text("Title")
            }
            .textFieldStyle(.plain)
            .font(.manrope(12))
            .foregroundStyle(palette.fg)
            .autocorrectionDisabled()
            .focused($titleFocused)
            .focusEffectDisabled()
            .padding(.horizontal, 8)
            #if os(iOS)
            .submitLabel(.done)
            .frame(height: Metrics.minTouch)
            #else
            .frame(height: 30)
            #endif
            .overlay(Rectangle().strokeBorder(titleFocused ? palette.fg : palette.line, lineWidth: 1))
        }
    }

    /// Icon or text, once a step launches an app.
    @ViewBuilder private var tileChoice: some View {
        let preview = CustomAction(title: title, steps: steps.compactMap(\.step), tile: tile)
        if preview.iconAppID != nil {
            VStack(alignment: .leading, spacing: 0) {
                SectionLabel("Tile")
                HStack(spacing: 6) {
                    GHButton("tile.icon", selected: preview.shownTile == .icon, height: 28) { tile = .icon }
                    GHButton("tile.text", selected: preview.shownTile == .text, height: 28) { tile = .text }
                }
            }
        }
    }

    private func save() {
        guard let list = completeSteps else { return }
        var action = draft
        action.title = title
        action.steps = list
        action.tile = tile
        model.save(action, pin: isNew)
        onDone()
    }

    /// The rows the setting menus offer: the tabs that are not shown are read too.
    private func readSettings() async {
        guard let session = model.session else { return }
        async let picture: Void = session.refresh(.picture)
        async let audio: Void = session.refresh(.audio)
        async let game: Void = session.refresh(.game)
        async let hdmi: Void = session.refresh(.hdmi)
        _ = await (picture, audio, game, hdmi)
    }
}

// MARK: - Step

/// What a step does, as the editor's first menu offers it.
private enum StepKind: String, CaseIterable {
    case button, input, app, pictureMode, setting, screenOff, screenOn, sleepTimer

    init(_ step: ActionStep) {
        switch step {
        case .button(let id): self = id.sourceID == nil ? .button : .input
        case .launchApp: self = .app
        case .pictureMode: self = .pictureMode
        case .setting: self = .setting
        case .screenOff: self = .screenOff
        case .screenOn: self = .screenOn
        case .sleepTimer: self = .sleepTimer
        }
    }

    var title: String {
        switch self {
        case .button: String(localized: "Remote button")
        case .input: String(localized: "Input")
        case .app: String(localized: "App")
        case .pictureMode: String(localized: "Picture mode")
        case .setting: String(localized: "Setting")
        case .screenOff: String(localized: "Screen off")
        case .screenOn: String(localized: "Screen on")
        case .sleepTimer: String(localized: "Sleep timer")
        }
    }

    /// The step of a kind that needs nothing more.
    var fixedStep: ActionStep? {
        switch self {
        case .screenOff: .screenOff
        case .screenOn: .screenOn
        default: nil
        }
    }
}

/// The tabs whose rows a setting step can set, and the server's sections behind each.
private enum SettingSection: String, CaseIterable {
    case picture, audio, game, hdmi

    init?(serverSection: String) {
        guard let found = Self.allCases.first(where: { $0.serverSections.contains(serverSection) }) else { return nil }
        self = found
    }

    var serverSections: [String] {
        switch self {
        case .picture: ["picture"]
        case .audio: ["sound"]
        case .game: ["game"]
        case .hdmi: ["hdmi", "devices"]
        }
    }

    var title: String {
        switch self {
        case .picture: String(localized: "Picture")
        case .audio: String(localized: "Audio")
        case .game: String(localized: "Game")
        case .hdmi: String(localized: "HDMI")
        }
    }

    /// Its rows, once each.
    func rows(_ menus: EditorMenus) -> [SettingRow] {
        var seen = Set<String>()
        return serverSections.flatMap(menus.rows(section:)).filter { seen.insert($0.id).inserted }
    }
}

/// What the TV offers the editor's menus: its inputs, its apps, its picture modes and the rows of
/// each setting section, their values included. Equatable, so that a poll that changes none of
/// it (most of them) does not draw the editor again.
private struct EditorMenus: Equatable {
    let sources: [Source]
    let apps: [Stats.App]
    let pictureModes: [Choice]?
    private let rowsBySection: [String: [SettingRow]]

    init(_ context: ActionContext) {
        sources = context.sources
        apps = context.apps
        pictureModes = context.pictureModes
        let sections = SettingSection.allCases.flatMap(\.serverSections)
        rowsBySection = Dictionary(sections.map { ($0, context.rows(section: $0)) }, uniquingKeysWith: { first, _ in first })
    }

    @MainActor init(model: AppModel) {
        self.init(model.session?.actionContext ?? ActionContext(stats: nil, rows: []))
    }

    func rows(section: String) -> [SettingRow] { rowsBySection[section] ?? [] }

    /// Reads the session, at each poll, and hands the menus on only when they changed: the
    /// observation of the session stays in this empty view.
    struct Reader: View {
        let model: AppModel
        let changed: (EditorMenus) -> Void

        var body: some View {
            Color.clear.onChange(of: EditorMenus(model: model), initial: true) { _, menus in changed(menus) }
        }
    }
}

/// A step being edited: its kind, then what it needs. `step` stays nil until it is complete.
private struct StepDraft: Identifiable {
    let id = UUID()
    var kind: StepKind?
    /// A setting's tab, chosen before its row.
    var section: SettingSection?
    var step: ActionStep?

    init() {}

    init(_ step: ActionStep) {
        kind = StepKind(step)
        if case .setting(_, let section, _, _, _) = step { self.section = SettingSection(serverSection: section) }
        self.step = step
    }

    mutating func choose(_ kind: StepKind) {
        guard kind != self.kind else { return }
        self.kind = kind
        section = nil
        step = kind.fixedStep
    }
}

/// One numbered step: the kind's menu and "×" on the first line, the target and the value under it.
private struct StepEditor: View {
    let number: Int
    @Binding var draft: StepDraft
    let menus: EditorMenus
    let onRemove: () -> Void
    @Environment(\.palette) private var palette

    private static let sleepValues = ["off", "10", "30", "60", "90", "120"]
    /// A menu's height: a finger's on iOS.
    #if os(iOS)
    fileprivate static let controlHeight: CGFloat = Metrics.minTouch
    #else
    fileprivate static let controlHeight: CGFloat = SettingMetrics.controlHeight
    #endif

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Text(verbatim: "\(number)")
                .font(.manrope(11, .light))
                .monospacedDigit()
                .foregroundStyle(palette.label)
                .frame(width: 14, height: Self.controlHeight, alignment: .leading)
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    menu(value: draft.kind?.rawValue ?? "",
                         choices: StepKind.allCases.map { Choice(value: $0.rawValue, label: $0.title) },
                         title: draft.kind == nil ? choose : nil) { raw in
                        if let kind = StepKind(rawValue: raw) { draft.choose(kind) }
                    }
                    Spacer(minLength: 0)
                    Button(action: onRemove) {
                        Text(verbatim: "×")
                            .font(.manrope(14, .light))
                            .foregroundStyle(palette.label)
                            #if os(iOS)
                            .frame(width: Metrics.minTouch, height: Self.controlHeight)
                            #else
                            .frame(width: 22, height: Self.controlHeight)
                            #endif
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(Text("Remove step"))
                }
                target
            }
        }
        .padding(.vertical, 6)
    }

    private var choose: String { String(localized: "Choose…") }

    @ViewBuilder private var target: some View {
        switch draft.kind {
        case .button:
            let current = draft.step?.button
            menu(value: current?.rawValue ?? "",
                 choices: ButtonID.remote.map { Choice(value: $0.rawValue, label: $0.fixedTitle ?? $0.rawValue) },
                 title: current.map { $0.title(sources: [], actions: []) } ?? choose) {
                draft.step = .button(ButtonID(rawValue: $0))
            }
        case .input:
            let current = draft.step?.button?.sourceID
            let sources = menus.sources
            menu(value: current ?? "", choices: sources.map { Choice(value: $0.id, label: $0.label) },
                 title: current.map { id in sources.first { $0.id == id }?.label ?? id } ?? choose) {
                draft.step = .button(.source($0))
            }
        case .app:
            let current = draft.step?.app
            let apps = menus.apps
            menu(value: current?.id ?? "", choices: apps.map { Choice(value: $0.id, label: $0.title) },
                 title: current?.title ?? choose) { id in
                if let app = apps.first(where: { $0.id == id }) { draft.step = .launchApp(id: app.id, title: app.title) }
            }
        case .pictureMode:
            let current = draft.step?.mode
            let modes = menus.pictureModes ?? []
            menu(value: current?.value ?? "", choices: modes, title: current?.label ?? choose) { value in
                if let mode = modes.first(where: { $0.value == value }) { draft.step = .pictureMode(value: mode.value, label: mode.label) }
            }
        case .setting:
            settingTarget
        case .sleepTimer:
            let current = draft.step?.sleep
            let choices = Self.sleepValues.map { Choice(value: $0, label: Self.sleepLabel($0)) }
            menu(value: current ?? "", choices: choices, title: current.map(Self.sleepLabel) ?? choose) {
                draft.step = .sleepTimer($0)
            }
        case .screenOff, .screenOn, nil:
            EmptyView()
        }
    }

    private static func sleepLabel(_ value: String) -> String {
        value == "off" ? String(localized: "Off") : String(localized: "\(value) min")
    }

    // MARK: Setting

    @ViewBuilder private var settingTarget: some View {
        let current = draft.step?.setting
        let rows = draft.section?.rows(menus) ?? []
        VStack(alignment: .leading, spacing: 6) {
            #if os(iOS)
            // One under the other: a phone's line is too narrow for both.
            VStack(alignment: .leading, spacing: 6) { settingMenus(current, rows: rows) }
            #else
            HStack(spacing: 8) { settingMenus(current, rows: rows) }
            #endif
            if let current {
                if let row = rows.first(where: { $0.id == current.id }) {
                    valueControl(row, current: current.value)
                } else {
                    // The row is not read (yet): its value as it was saved.
                    Text(verbatim: current.valueLabel)
                        .font(.manrope(10.5))
                        .foregroundStyle(palette.label)
                        .frame(height: Self.controlHeight)
                }
            }
        }
    }

    /// The tab's menu, then, once it is chosen, its rows'.
    @ViewBuilder private func settingMenus(_ current: (id: String, title: String, value: SettingValue, valueLabel: String)?,
                                           rows: [SettingRow]) -> some View {
        menu(value: draft.section?.rawValue ?? "",
             choices: SettingSection.allCases.map { Choice(value: $0.rawValue, label: $0.title) },
             title: draft.section == nil ? choose : nil) { raw in
            guard let section = SettingSection(rawValue: raw), section != draft.section else { return }
            draft.section = section
            draft.step = nil
        }
        if draft.section != nil {
            menu(value: current?.id ?? "", choices: rows.map { Choice(value: $0.id, label: $0.title) },
                 title: current?.title ?? choose) { id in
                if let picked = rows.first(where: { $0.id == id }) { draft.step = ActionStep(currentValueOf: picked) }
            }
        }
    }

    @ViewBuilder private func valueControl(_ row: SettingRow, current: SettingValue) -> some View {
        switch row.kind {
        case .toggle:
            menu(value: current == .bool(true) ? "on" : "off",
                 choices: [Choice(value: "on", label: "ON"), Choice(value: "off", label: "OFF")], title: nil) {
                draft.step = ActionStep(row: row, value: .bool($0 == "on"))
            }
        case .choice(_, let choices):
            menu(value: current.string ?? "", choices: choices, title: nil) {
                draft.step = ActionStep(row: row, value: .string($0))
            }
        case .number(_, let min, let max):
            NumberField(value: current.number ?? min, range: min...max, row: row) { n in
                draft.step = ActionStep(row: row, value: .number(n))
            }
        case .unsupported:
            EmptyView()
        }
    }

    /// A server menu, as wide as its current label.
    private func menu(value: String, choices: [Choice], title: String?, onSelect: @escaping (String) -> Void) -> some View {
        ChoiceMenu(value: value, choices: choices, title: title, onSelect: onSelect)
            .fixedSize()
            .disabled(choices.isEmpty)
    }
}

/// A number typed in a ruled box, and the range after it. Each keystroke that makes a number
/// hands it on, rounded and kept within the range, so Save always gets what is typed even
/// without Return; the box shows that value again on Return or when it loses the focus.
private struct NumberField: View {
    let value: Double
    let range: ClosedRange<Double>
    let row: SettingRow
    let onChange: (Double) -> Void
    @State private var text = ""
    @Environment(\.palette) private var palette
    @FocusState private var focused: Bool

    var body: some View {
        HStack(spacing: 8) {
            TextField(text: $text, prompt: nil) { Text("Value") }
                .textFieldStyle(.plain)
                .font(.manrope(11))
                .monospacedDigit()
                .foregroundStyle(palette.fg)
                .autocorrectionDisabled()
                .focused($focused)
                .focusEffectDisabled()
                .padding(.horizontal, 6)
                #if os(iOS)
                // A minus sign too: some ranges go below zero.
                .keyboardType(.numbersAndPunctuation)
                .frame(width: 80, height: StepEditor.controlHeight)
                #else
                .frame(width: 64, height: StepEditor.controlHeight)
                #endif
                .overlay(Rectangle().strokeBorder(focused ? palette.fg : palette.line, lineWidth: 1))
                .onAppear { text = Self.text(value) }
                .onChange(of: text) { _, typed in
                    if let n = RowLayout.typedNumber(typed, row: row), n != value { onChange(n) }
                }
                .onSubmit { text = Self.text(value) }
                .onChange(of: focused) { _, now in if !now { text = Self.text(value) } }
                // Another row picked for this step: its value.
                .onChange(of: value) { _, new in if !focused { text = Self.text(new) } }
            Text(verbatim: "\(RowLayout.valueText(row, value: range.lowerBound)) … \(RowLayout.valueText(row, value: range.upperBound))")
                .font(.manrope(9.5))
                .foregroundStyle(palette.label)
        }
    }

    private static func text(_ value: Double) -> String { String(Int(value.rounded())) }
}

// MARK: - Reading a step

private extension ActionStep {
    var button: ButtonID? {
        if case .button(let id) = self { return id }
        return nil
    }

    var app: (id: String, title: String)? {
        if case .launchApp(let id, let title) = self { return (id, title) }
        return nil
    }

    var mode: (value: String, label: String)? {
        if case .pictureMode(let value, let label) = self { return (value, label) }
        return nil
    }

    var setting: (id: String, title: String, value: SettingValue, valueLabel: String)? {
        if case .setting(let id, _, let title, let value, let valueLabel) = self { return (id, title, value, valueLabel) }
        return nil
    }

    var sleep: String? {
        if case .sleepTimer(let value) = self { return value }
        return nil
    }
}

private extension SettingValue {
    var string: String? {
        if case .string(let s) = self { return s }
        return nil
    }

    var number: Double? {
        if case .number(let n) = self { return n }
        return nil
    }
}
