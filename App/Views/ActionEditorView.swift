import PaneKit
import SwiftUI

/// Makes or changes a custom action of the active TV: its title, then its steps in order, each a
/// kind, a target and, for a setting or the sleep timer, a value, then, once a step launches an
/// app, whether its pin shows that app's icon or the title. It edits its own copy: nothing
/// is stored before Save. The menus come from what the TV offers; Picture, Audio, Game and HDMI
/// are read when it appears.
struct ActionEditorView: View {
    let model: AppModel
    private let draft: CustomAction
    private let onDone: () -> Void
    @State private var title: String
    @State private var steps: [StepDraft]
    /// `nil` until a choice is clicked: the default then follows the steps.
    @State private var tile: CustomAction.Tile?
    @Environment(\.palette) private var palette
    @FocusState private var titleFocused: Bool

    init(model: AppModel, draft: CustomAction, onDone: @escaping () -> Void) {
        self.model = model
        self.draft = draft
        self.onDone = onDone
        _title = State(initialValue: draft.title)
        _steps = State(initialValue: draft.steps.map(StepDraft.init))
        _tile = State(initialValue: draft.tile)
    }

    /// Not stored yet for the active TV: it is pinned when saved, and cannot be deleted.
    private var isNew: Bool {
        guard let tv = model.store.activeID else { return true }
        return !model.actions.actions(for: tv).contains { $0.id == draft.id }
    }

    private var context: ActionContext { model.session?.actionContext ?? ActionContext(stats: nil, rows: []) }

    /// The steps, once each one has what it needs.
    private var completeSteps: [ActionStep]? {
        let list = steps.compactMap(\.step)
        return list.count == steps.count && !list.isEmpty ? list : nil
    }

    var body: some View {
        let context = context
        VStack(alignment: .leading, spacing: 0) {
            CappedScroll {
                VStack(alignment: .leading, spacing: 14) {
                    titleField(context)
                    VStack(alignment: .leading, spacing: 0) {
                        SectionLabel("Steps")
                        ForEach($steps) { $step in
                            let number = (steps.firstIndex { $0.id == step.id } ?? 0) + 1
                            StepEditor(number: number, draft: $step, context: context) {
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
        .task { await readSettings() }
    }

    private func titleField(_ context: ActionContext) -> some View {
        let fallback = CustomAction.defaultTitle(steps.compactMap(\.step), sources: context.sources)
        return VStack(alignment: .leading, spacing: 0) {
            Group {
                if isNew { Text("New action") } else { Text("Edit action") }
            }
            .font(.manrope(13))
            .padding(.bottom, 10)
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
            .frame(height: 30)
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
    func rows(_ context: ActionContext) -> [SettingRow] {
        var seen = Set<String>()
        return serverSections.flatMap(context.rows(section:)).filter { seen.insert($0.id).inserted }
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
    let context: ActionContext
    let onRemove: () -> Void
    @Environment(\.palette) private var palette

    private static let sleepValues = ["off", "10", "30", "60", "90", "120"]

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Text(verbatim: "\(number)")
                .font(.manrope(11, .light))
                .monospacedDigit()
                .foregroundStyle(palette.label)
                .frame(width: 14, height: SettingMetrics.controlHeight, alignment: .leading)
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
                            .frame(width: 22, height: SettingMetrics.controlHeight)
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
            let sources = context.sources
            menu(value: current ?? "", choices: sources.map { Choice(value: $0.id, label: $0.label) },
                 title: current.map { id in sources.first { $0.id == id }?.label ?? id } ?? choose) {
                draft.step = .button(.source($0))
            }
        case .app:
            let current = draft.step?.app
            let apps = context.apps
            menu(value: current?.id ?? "", choices: apps.map { Choice(value: $0.id, label: $0.title) },
                 title: current?.title ?? choose) { id in
                if let app = apps.first(where: { $0.id == id }) { draft.step = .launchApp(id: app.id, title: app.title) }
            }
        case .pictureMode:
            let current = draft.step?.mode
            let modes = context.pictureModes ?? []
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
        let rows = draft.section?.rows(context) ?? []
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
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
            if let current {
                if let row = rows.first(where: { $0.id == current.id }) {
                    valueControl(row, current: current.value)
                } else {
                    // The row is not read (yet): its value as it was saved.
                    Text(verbatim: current.valueLabel)
                        .font(.manrope(10.5))
                        .foregroundStyle(palette.label)
                        .frame(height: SettingMetrics.controlHeight)
                }
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
                .frame(width: 64, height: SettingMetrics.controlHeight)
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
