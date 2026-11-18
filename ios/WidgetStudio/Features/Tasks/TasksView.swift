import Observation
import SwiftUI
import UIKit
import WidgetKit
import WidgetKitCore

/// The Tasks tab's data (ADR-028): Apple Reminders through `TaskStore`.
@MainActor
@Observable
final class TasksModel {
    private(set) var tasks: [TaskItem] = []
    private(set) var isAuthorized = TaskStore.isAuthorized
    private(set) var isDenied = TaskStore.isDenied
    /// Set when saving or deleting failed.
    var failed = false
    @ObservationIgnored private let store = TaskStore()

    func reload() async {
        isAuthorized = TaskStore.isAuthorized
        isDenied = TaskStore.isDenied
        tasks = await store.load()
    }

    /// The one time the app asks; afterwards only Settings can change the answer.
    func requestAccess() async {
        _ = await store.requestAccess()
        await reload()
        AppReloads.all("tasks changed")
    }

    private func changing(_ change: () throws -> Void) async {
        do {
            try change()
        } catch {
            failed = true
        }
        await reload()
        AppReloads.all("tasks changed")
    }

    func save(_ task: TaskItem) async {
        await changing { try store.save(task) }
    }

    func delete(_ task: TaskItem) async {
        await changing { try store.delete(id: task.id) }
    }

    func toggle(_ task: TaskItem) async {
        await changing { try store.toggle(id: task.id) }
    }
}

struct TasksView: View {
    @Environment(TasksModel.self) private var model
    @Environment(AppState.self) private var appState
    @Environment(\.scenePhase) private var scenePhase
    @State private var filter = TaskFormat.Filter.today
    @State private var editing: TaskItem?
    @State private var deleting: TaskItem?
    private let language = RenderContext.preferredLanguage

    private var shown: [TaskItem] { TaskFormat.filter(model.tasks, filter, now: .now) }

    var body: some View {
        @Bindable var model = model
        Group {
            if model.isAuthorized {
                list
            } else {
                access
            }
        }
        .navigationTitle("tasks.title")
        .toolbar {
            if model.isAuthorized {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        editing = TaskItem(title: "")
                    } label: {
                        Label("tasks.add", systemImage: "plus")
                    }
                    .accessibilityIdentifier("ax.tasks.add")
                }
            }
        }
        .task { await model.reload() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { Task { await model.reload() } }
        }
        .onChange(of: appState.isAddingTask) { _, adding in
            if adding {
                appState.isAddingTask = false
                if model.isAuthorized { editing = TaskItem(title: "") }
            }
        }
        .sheet(item: $editing) { task in
            TaskEditorView(task: task, isNew: !model.tasks.contains { $0.id == task.id })
        }
        .alert("tasks.failed", isPresented: $model.failed) {
            Button("common.done", role: .cancel) {}
        }
        .confirmationDialog("tasks.delete.title", isPresented: deleteBinding, titleVisibility: .visible) {
            Button("tasks.delete", role: .destructive) {
                if let deleting { Task { await model.delete(deleting) } }
            }
        }
    }

    private var deleteBinding: Binding<Bool> {
        Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } })
    }

    /// Asked once; a refusal is explained, with the way back.
    private var access: some View {
        VStack(spacing: 14) {
            Image(systemName: "checklist")
                .font(.largeTitle)
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            Text("tasks.access.title").font(.headline).multilineTextAlignment(.center)
            Text(model.isDenied ? "tasks.access.denied" : "tasks.access.body")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            if model.isDenied {
                Button("tasks.access.settings") {
                    if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
                }
                .buttonStyle(.borderedProminent)
            } else {
                Button("tasks.access.allow") {
                    Task { await model.requestAccess() }
                }
                .buttonStyle(.borderedProminent)
                .accessibilityIdentifier("ax.tasks.allow")
            }
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var list: some View {
        List {
            Section {
                Picker("tasks.filter", selection: $filter) {
                    Text("tasks.filter.today").tag(TaskFormat.Filter.today)
                    Text("tasks.filter.upcoming").tag(TaskFormat.Filter.upcoming)
                    Text("tasks.filter.done").tag(TaskFormat.Filter.done)
                }
                .pickerStyle(.segmented)
                .accessibilityIdentifier("ax.tasks.filter")
            }
            .listRowBackground(Color.clear)
            if shown.isEmpty {
                Text(emptyText).font(.footnote).foregroundStyle(.secondary)
            }
            ForEach(shown) { task in
                row(task)
            }
        }
        .accessibilityIdentifier("ax.tasks.list")
    }

    private var emptyText: LocalizedStringKey {
        switch filter {
        case .today: "tasks.empty.today"
        case .upcoming: "tasks.empty.upcoming"
        case .done: "tasks.empty.done"
        }
    }

    private func row(_ task: TaskItem) -> some View {
        HStack(spacing: 12) {
            Button {
                Task { await model.toggle(task) }
            } label: {
                Image(systemName: task.done ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(task.done ? Color.accentColor : .secondary)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text(task.done ? "tasks.undone" : "tasks.complete"))
            Button {
                editing = task
            } label: {
                VStack(alignment: .leading, spacing: 2) {
                    Text(verbatim: task.title)
                        .strikethrough(task.done)
                        .foregroundStyle(task.done ? .secondary : .primary)
                    let detail = [TaskFormat.dueText(task, now: .now, calendar: .current, language: language), task.list ?? ""].filter { !$0.isEmpty }
                    if !detail.isEmpty {
                        Text(verbatim: detail.joined(separator: " · ")).font(.caption).foregroundStyle(.secondary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            if task.priority != .none {
                Image(systemName: "exclamationmark")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(task.priority == .high ? .red : .orange)
                    .accessibilityHidden(true)
            }
        }
        .swipeActions(edge: .trailing) {
            Button(role: .destructive) { deleting = task } label: { Label("tasks.delete", systemImage: "trash") }
        }
        .contextMenu {
            Button { editing = task } label: { Label("tasks.edit", systemImage: "pencil") }
            Button(role: .destructive) { deleting = task } label: { Label("tasks.delete", systemImage: "trash") }
        }
        .accessibilityIdentifier("ax.tasks.row")
    }
}

/// Adds or edits a task.
struct TaskEditorView: View {
    @Environment(TasksModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State var task: TaskItem
    let isNew: Bool
    @State private var hasDue: Bool
    @State private var confirmingDelete = false

    init(task: TaskItem, isNew: Bool) {
        _task = State(initialValue: task)
        self.isNew = isNew
        _hasDue = State(initialValue: task.due != nil)
    }

    private var dueBinding: Binding<Date> {
        Binding(get: { task.due ?? .now }, set: { task.due = $0 })
    }

    private var listBinding: Binding<String> {
        Binding(get: { task.list ?? "" }, set: { task.list = $0.isEmpty ? nil : $0 })
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("tasks.field.title", text: $task.title)
                        .accessibilityIdentifier("ax.tasks.title")
                    TextField("tasks.field.list", text: listBinding)
                    Picker("tasks.field.priority", selection: $task.priority) {
                        Text("tasks.priority.none").tag(TaskItem.Priority.none)
                        Text("tasks.priority.low").tag(TaskItem.Priority.low)
                        Text("tasks.priority.medium").tag(TaskItem.Priority.medium)
                        Text("tasks.priority.high").tag(TaskItem.Priority.high)
                    }
                }
                Section {
                    Toggle("tasks.field.due", isOn: $hasDue)
                    if hasDue {
                        Toggle("tasks.field.time", isOn: $task.hasTime)
                        DatePicker("tasks.field.date", selection: dueBinding, displayedComponents: task.hasTime ? [.date, .hourAndMinute] : [.date])
                        Toggle("tasks.field.reminder", isOn: $task.reminds)
                    }
                }
                if !isNew {
                    Section {
                        Button("tasks.delete", role: .destructive) { confirmingDelete = true }
                    }
                }
            }
            .navigationTitle(isNew ? "tasks.new" : "tasks.edit")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("common.cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("common.save") { save() }
                        .disabled(task.title.trimmingCharacters(in: .whitespaces).isEmpty)
                        .accessibilityIdentifier("ax.tasks.save")
                }
            }
            .confirmationDialog("tasks.delete.title", isPresented: $confirmingDelete, titleVisibility: .visible) {
                Button("tasks.delete", role: .destructive) {
                    let task = task
                    Task {
                        await model.delete(task)
                        dismiss()
                    }
                }
            }
        }
    }

    private func save() {
        var saved = task
        saved.title = saved.title.trimmingCharacters(in: .whitespaces)
        if hasDue {
            saved.due = saved.due ?? .now
        } else {
            saved.due = nil
            saved.reminds = false
        }
        Task {
            await model.save(saved)
            dismiss()
        }
    }
}
