import SwiftUI
import WidgetKit
import UserNotifications
import PhotosUI
import UniformTypeIdentifiers
import HealthKit
import LocalAuthentication
import AVFoundation

// MARK: - Shared Lists Hub

struct ListsView: View {
    @EnvironmentObject var store: EventStore
    @State private var selectedKind: GroupListKind? = nil
    @State private var selectedVisibility: VisibilityScope? = nil
    @State private var showAddList = false
    @State private var selectedList: GroupList? = nil
    @State private var selectedPlan: GroupPlan? = nil
    @State private var showAddPlan = false
    @State private var listPendingDelete: GroupList? = nil

    private var visiblePlans: [GroupPlan] {
        store.groupPlans.filter { store.canView(visibility: $0.visibility, ownerName: $0.ownerName, sharedWithNames: $0.sharedWithNames) }
    }

    var filteredLists: [GroupList] {
        let base = store.visibleGroupLists
        let byKind = selectedKind == nil ? base : base.filter { $0.kind == selectedKind }
        return selectedVisibility == nil ? byKind : byKind.filter { $0.visibility == selectedVisibility }
    }

    var body: some View {
        NavigationView {
            ZStack {
                AuraAtmosphericBackground()
                List {
                    Section {
                        VStack(alignment: .leading, spacing: 10) {
                            VStack(alignment: .leading, spacing: 6) {
                                Text("TYPE")
                                    .auraFont(size: 10, weight: .bold, design: .rounded)
                                    .tracking(1.0)
                                    .foregroundColor(.secondary)
                                ScrollView(.horizontal, showsIndicators: false) {
                                    HStack(spacing: 8) {
                                        FilterChip(title: "All", selected: selectedKind == nil) {
                                            selectedKind = nil
                                        }
                                        ForEach(GroupListKind.allCases, id: \.self) { kind in
                                            FilterChip(title: kind.rawValue, selected: selectedKind == kind) {
                                                selectedKind = kind
                                            }
                                        }
                                    }
                                }
                            }

                            VStack(alignment: .leading, spacing: 6) {
                                Text("VISIBILITY")
                                    .auraFont(size: 10, weight: .bold, design: .rounded)
                                    .tracking(1.0)
                                    .foregroundColor(.secondary)
                                ScrollView(.horizontal, showsIndicators: false) {
                                    HStack(spacing: 8) {
                                        FilterChip(title: "All", selected: selectedVisibility == nil) {
                                            selectedVisibility = nil
                                        }
                                        ForEach(VisibilityScope.allCases, id: \.self) { scope in
                                            FilterChip(title: scope.displayName, selected: selectedVisibility == scope) {
                                                selectedVisibility = scope
                                            }
                                        }
                                    }
                                }
                            }
                        }
                        .padding(.vertical, 4)
                    }
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)

                    if filteredLists.isEmpty {
                        Section {
                            Text("No lists yet. Create your first shared group list.")
                                .foregroundColor(.secondary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(AuraDesignTokens.Spacing.sm)
                                .auraGlassCard(radius: AuraDesignTokens.Radius.md)
                        }
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                    } else {
                        Section {
                            ForEach(filteredLists) { list in
                                Button {
                                    selectedList = list
                                } label: {
                                    HStack(spacing: 12) {
                                        Image(systemName: list.kind.icon)
                                            .auraFont(size: 13, weight: .semibold)
                                            .foregroundColor(AuraThemePalette.current.accentStart)
                                            .frame(width: 30, height: 30)
                                            .background(AuraThemePalette.current.accentStart.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
                                        VStack(alignment: .leading, spacing: 1) {
                                            Text(list.title)
                                                .auraFont(size: 15, weight: .bold, design: .rounded)
                                                .foregroundColor(.primary)
                                            Text(summary(for: list))
                                                .auraFont(size: 12)
                                                .foregroundColor(.secondary)
                                        }
                                        Spacer()
                                        Image(systemName: list.visibility.icon)
                                            .auraFont(size: 12, weight: .semibold)
                                            .foregroundColor(.secondary)
                                    }
                                    .padding(AuraDesignTokens.Spacing.sm)
                                    .auraGlassCard(radius: AuraDesignTokens.Radius.md)
                                }
                                .buttonStyle(.plain)
                                .listRowBackground(Color.clear)
                                .listRowSeparator(.hidden)
                                .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                    if store.canDelete(list) {
                                        Button(role: .destructive) {
                                            listPendingDelete = list
                                        } label: {
                                            Label("Delete", systemImage: "trash")
                                        }
                                    }
                                }
                            }
                        } header: {
                            Text("GROUP LISTS")
                                .auraFont(size: 11, weight: .bold, design: .rounded)
                                .foregroundColor(.secondary)
                        }
                    }

                    // Plans are multi-step projects that live alongside lists.
                    Section {
                        if visiblePlans.isEmpty {
                            Text("No plans yet. A plan is a goal with steps and a target date, like a party or a move.")
                                .auraFont(size: 13)
                                .foregroundColor(.secondary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(AuraDesignTokens.Spacing.sm)
                                .auraGlassCard(radius: AuraDesignTokens.Radius.md)
                                .listRowBackground(Color.clear)
                                .listRowSeparator(.hidden)
                        }
                        ForEach(visiblePlans) { plan in
                            Button {
                                selectedPlan = plan
                            } label: {
                                HStack(spacing: 12) {
                                    Image(systemName: "flag.checkered")
                                        .auraFont(size: 13, weight: .semibold)
                                        .foregroundColor(AuraThemePalette.current.accentStart)
                                        .frame(width: 30, height: 30)
                                        .background(AuraThemePalette.current.accentStart.opacity(0.12), in: RoundedRectangle(cornerRadius: AuraDesignTokens.Radius.sm))
                                    VStack(alignment: .leading, spacing: 1) {
                                        Text(plan.title)
                                            .auraFont(size: 15, weight: .bold, design: .rounded)
                                            .foregroundColor(.primary)
                                        Text("\(plan.targetDate.formatted(date: .abbreviated, time: .omitted)) · \(plan.items.filter(\.isDone).count) of \(countLabel(plan.items.count, "step")) done")
                                            .auraFont(size: 12)
                                            .foregroundColor(.secondary)
                                    }
                                    Spacer()
                                    ProgressView(value: plan.progress)
                                        .frame(width: 44)
                                        .tint(AuraThemePalette.current.accentStart)
                                }
                                .padding(AuraDesignTokens.Spacing.sm)
                                .auraGlassCard(radius: AuraDesignTokens.Radius.md)
                            }
                            .buttonStyle(.plain)
                            .listRowBackground(Color.clear)
                            .listRowSeparator(.hidden)
                            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                if store.canDelete(plan) {
                                    Button(role: .destructive) {
                                        store.deleteGroupPlan(id: plan.id)
                                    } label: {
                                        Label("Delete", systemImage: "trash")
                                    }
                                }
                            }
                        }
                    } header: {
                        Text("PLANS")
                            .auraFont(size: 11, weight: .bold, design: .rounded)
                            .foregroundColor(.secondary)
                    }
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
            }
            .navigationTitle("Lists")
            .auraTabChrome()
            .alert("Delete List", isPresented: Binding(
                get: { listPendingDelete != nil },
                set: { if !$0 { listPendingDelete = nil } }
            ), presenting: listPendingDelete) { list in
                Button("Cancel", role: .cancel) {}
                Button("Delete", role: .destructive) {
                    AuraHaptics.warning()
                    store.deleteGroupList(id: list.id)
                }
            } message: { list in
                Text("Delete \"\(list.title)\" and its \(countLabel(list.items.count, "item")) for everyone in the group?")
            }
        }
        .sheet(item: $selectedPlan) { plan in
            GroupPlanDetailView(planId: plan.id)
                .environmentObject(store)
        }
        .sheet(isPresented: $showAddPlan) {
            AddGroupPlanView(isPresented: $showAddPlan)
                .environmentObject(store)
        }
        .sheet(isPresented: $showAddList) {
            AddGroupListView(isPresented: $showAddList)
                .environmentObject(store)
        }
        .sheet(item: $selectedList) { list in
            GroupListDetailView(listId: list.id)
                .environmentObject(store)
        }
    }

    private func summary(for list: GroupList) -> String {
        let done = list.items.filter { $0.isDone }.count
        var parts = [countLabel(list.items.count, "item"), "\(done) done"]
        if list.kind == .supermarket {
            let stores = Set(list.items.compactMap { $0.preferredStore?.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty })
            if !stores.isEmpty { parts.append(countLabel(stores.count, "store")) }
        }
        return parts.joined(separator: " · ")
    }
}

struct FilterChip: View {
    let title: String
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .auraFont(size: 12, weight: .semibold, design: .rounded)
                .foregroundColor(selected ? .white : .primary)
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .background(
                    selected
                        ? AnyShapeStyle(LinearGradient(colors: [AuraThemePalette.current.accentStart, AuraThemePalette.current.accentEnd], startPoint: .topLeading, endPoint: .bottomTrailing))
                        : AnyShapeStyle(Color(.tertiarySystemFill)),
                    in: Capsule()
                )
                .overlay(
                    Capsule().stroke(selected ? Color.clear : Color.primary.opacity(0.08), lineWidth: 1)
                )
                .shadow(color: selected ? AuraThemePalette.current.accentStart.opacity(0.3) : .clear, radius: 6, y: 2)
        }
        .buttonStyle(.plain)
    }
}

struct AddGroupListView: View {
    @EnvironmentObject var store: EventStore
    @Binding var isPresented: Bool
    @State private var title = ""
    @State private var kind: GroupListKind = .supermarket
    @State private var visibility: VisibilityScope = .family
    @State private var customNames: Set<String> = []

    var body: some View {
        NavigationView {
            ZStack {
                AuraAtmosphericBackground()
                Form {
                if store.serverGroups.count > 1 {
                    Section {
                        Label("Creating in **\(store.activeServerGroupName)**", systemImage: "square.stack.3d.up.fill")
                            .auraFont(size: 13)
                            .foregroundColor(.secondary)
                    } footer: {
                        Text("To put this list in a different group, switch groups first using the pill at the top of the screen, then create it from there.")
                    }
                }
                Section("List Name") {
                    TextField("e.g. Weekly Grocery", text: $title)
                }
                Section("List Type") {
                    Picker("Type", selection: $kind) {
                        ForEach(GroupListKind.allCases, id: \.self) { k in
                            Label(k.rawValue, systemImage: k.icon).tag(k)
                        }
                    }
                    .pickerStyle(.menu)
                }
                Section("Visibility") {
                    Picker("Who can see this", selection: $visibility) {
                        ForEach(VisibilityScope.allCases, id: \.self) { s in
                            Label(s.displayName, systemImage: s.icon).tag(s)
                        }
                    }
                    Text(visibility.subtitle)
                        .auraFont(size: 12)
                        .foregroundColor(.secondary)
                }
                if visibility == .custom {
                    Section("Share With") {
                        ForEach(store.members.map(\.name), id: \.self) { name in
                            Button {
                                if customNames.contains(name) {
                                    customNames.remove(name)
                                } else {
                                    customNames.insert(name)
                                }
                            } label: {
                                HStack {
                                    Text(name).foregroundColor(.primary)
                                    Spacer()
                                    if customNames.contains(name) {
                                        Image(systemName: "checkmark.circle.fill")
                                            .foregroundColor(AuraThemePalette.current.accentStart)
                                    }
                                }
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                }
                .scrollContentBackground(.hidden)
            }
            .navigationTitle("New List")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") { isPresented = false }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Create") {
                        AuraHaptics.success()
                        store.addGroupList(
                            title: title,
                            kind: kind,
                            visibility: visibility,
                            sharedWithNames: Array(customNames)
                        )
                        isPresented = false
                    }
                    .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }
}

struct GroupListDetailView: View {
    @EnvironmentObject var store: EventStore
    @Environment(\.dismiss) var dismiss
    let listId: UUID
    @State private var showAddItem = false
    @State private var editItem: GroupListItem? = nil
    @State private var showRename = false
    @State private var renameText = ""
    @State private var showStores = false

    var list: GroupList? {
        store.groupLists.first(where: { $0.id == listId })
    }

    var groupedItems: [(String, [GroupListItem])] {
        guard let list, list.kind == .supermarket else { return [] }
        let groups = Dictionary(grouping: list.items) { item -> String in
            let trimmed = item.preferredStore?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return trimmed.isEmpty ? "No Store Set" : trimmed
        }
        return groups
            .sorted { lhs, rhs in
                if lhs.key == "No Store Set" { return false }
                if rhs.key == "No Store Set" { return true }
                return lhs.key.localizedCaseInsensitiveCompare(rhs.key) == .orderedAscending
            }
    }

    var body: some View {
        NavigationView {
            List {
                if let list {
                    if list.items.isEmpty {
                        Text("No items yet")
                            .foregroundColor(.secondary)
                    } else if list.kind == .supermarket {
                        ForEach(groupedItems, id: \.0) { storeGroup in
                            Section(storeGroup.0) {
                                ForEach(storeGroup.1) { item in
                                    itemRow(item)
                                }
                            }
                        }
                    } else {
                        ForEach(list.items) { item in
                            itemRow(item)
                        }
                    }
                }
            }
            .navigationTitle(list?.title ?? "List")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Close") { dismiss() }
                }
                ToolbarItemGroup(placement: .navigationBarTrailing) {
                    Menu {
                        Button {
                            renameText = list?.title ?? ""
                            showRename = true
                        } label: {
                            Label(list.map(store.canEdit) ?? false ? "Rename List" : "Suggest New Name", systemImage: "pencil")
                        }
                        Button {
                            showStores = true
                        } label: {
                            Label("Manage Stores", systemImage: "storefront")
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                            .accessibilityLabel("More options")
                    }
                    Button {
                        showAddItem = true
                    } label: {
                        Image(systemName: "plus")
                            .accessibilityLabel("Add")
                    }
                }
            }
            .alert(list.map(store.canEdit) ?? false ? "Rename List" : "Suggest New Name", isPresented: $showRename) {
                TextField("List name", text: $renameText)
                Button("Cancel", role: .cancel) {}
                Button(list.map(store.canEdit) ?? false ? "Save" : "Send") {
                    if store.renameGroupList(id: listId, title: renameText) == .proposed, let list {
                        NotificationCenter.default.post(
                            name: .auraInAppBanner,
                            object: nil,
                            userInfo: ["title": "Change requested", "message": "Sent to \(store.creatorName(ownerName: list.ownerName)) to approve."]
                        )
                    }
                }
            }
        }
        .sheet(isPresented: $showAddItem) {
            AddGroupListItemView(isPresented: $showAddItem, listId: listId)
                .environmentObject(store)
        }
        .sheet(isPresented: $showStores) {
            ManageStoresView().environmentObject(store)
        }
        .sheet(item: $editItem) { item in
            AddGroupListItemView(isPresented: .constant(true), listId: listId, editingItem: item)
                .environmentObject(store)
        }
    }

    private func itemSummary(_ item: GroupListItem) -> String {
        var bits: [String] = []
        if !item.quantity.isEmpty { bits.append(item.quantity) }
        let storeText = item.preferredStore?.trimmingCharacters(in: .whitespacesAndNewlines)
        bits.append((storeText?.isEmpty ?? true) ? "Store not set" : storeText!)
        if let dueDate = item.dueDate {
            let f = DateFormatter()
            f.dateStyle = .medium
            bits.append(f.string(from: dueDate))
        }
        if item.isDone, let completedBy = item.completedByName {
            bits.append("Bought by \(completedBy)")
        }
        if store.pendingProposal(for: item.id) != nil {
            bits.append("Your change is awaiting approval")
        }
        return bits.joined(separator: " · ")
    }

    private func canEdit(_ item: GroupListItem) -> Bool {
        guard let list else { return false }
        return store.canEdit(item: item, in: list)
    }

    private func canDelete(_ item: GroupListItem) -> Bool {
        guard let list else { return false }
        return store.canDelete(item: item, in: list)
    }

    @ViewBuilder
    private func itemRow(_ item: GroupListItem) -> some View {
        HStack(spacing: 10) {
            Button {
                AuraHaptics.tap(.light)
                withAnimation(AuraMotion.quick) {
                    store.toggleItem(listId: listId, itemId: item.id)
                }
            } label: {
                Image(systemName: item.isDone ? "checkmark.circle.fill" : "circle")
                    .accessibilityLabel(item.isDone ? "Mark \(item.name) not done" : "Mark \(item.name) done")
                    .auraFont(size: 18, weight: .semibold)
                    .foregroundColor(item.isDone ? .green : .secondary)
            }
            .buttonStyle(.plain)

            VStack(alignment: .leading, spacing: 1) {
                Text(item.name)
                    .auraFont(size: 15, weight: .semibold)
                    .strikethrough(item.isDone)
                    .foregroundColor(item.isDone ? .secondary : .primary)
                Text(itemSummary(item))
                    .auraFont(size: 12)
                    .foregroundColor(.secondary)
            }
            Spacer()
            if let id = item.assignedMemberId,
               let m = store.members.first(where: { $0.id == id }) {
                Text(m.name)
                    .auraFont(size: 11, weight: .bold)
                    .foregroundColor(m.color)
            }
        }
        .swipeActions(edge: .leading, allowsFullSwipe: false) {
            Button {
                editItem = item
            } label: {
                Label(canEdit(item) ? "Edit" : "Suggest Changes", systemImage: "pencil")
            }
            .tint(AuraThemePalette.current.accentStart)
        }
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            if canDelete(item) {
                Button(role: .destructive) {
                    store.deleteItem(listId: listId, itemId: item.id)
                } label: {
                    Label("Delete", systemImage: "trash")
                }
            }
        }
        .contextMenu {
            Button {
                AuraHaptics.tap(.light)
                withAnimation(AuraMotion.quick) {
                    store.toggleItem(listId: listId, itemId: item.id)
                }
            } label: {
                Label(item.isDone ? "Mark Not Done" : "Mark Done", systemImage: item.isDone ? "circle" : "checkmark.circle.fill")
            }
            Button {
                editItem = item
            } label: {
                Label(canEdit(item) ? "Edit" : "Suggest Changes", systemImage: "pencil")
            }
            if canDelete(item) {
                Button(role: .destructive) {
                    store.deleteItem(listId: listId, itemId: item.id)
                } label: {
                    Label("Delete", systemImage: "trash")
                }
            }
        }
    }
}

struct AddGroupListItemView: View {
    @EnvironmentObject var store: EventStore
    @Environment(\.dismiss) var dismiss
    @Binding var isPresented: Bool
    let listId: UUID
    var editingItem: GroupListItem? = nil

    @State private var name = ""
    @State private var quantity = ""
    @State private var note = ""
    @State private var assignedMemberId: UUID? = nil
    @State private var preferredStore: String = ""
    @State private var dueDate = Date()
    @State private var hasDueDate = false

    private var list: GroupList? { store.groupLists.first(where: { $0.id == listId }) }

    /// Editing an item someone else added: saving sends them a request.
    private var isSuggesting: Bool {
        guard let editingItem, let list else { return false }
        return !store.canEdit(item: editingItem, in: list)
    }

    private var creatorName: String { store.creatorName(ownerName: list?.ownerName ?? "") }

    private func closeView() {
        if editingItem == nil {
            isPresented = false
        } else {
            dismiss()
        }
    }

    var body: some View {
        NavigationView {
            Form {
                if isSuggesting, let editingItem {
                    Section {
                        Text("\(creatorName) added \"\(editingItem.name)\". Your changes will be sent to them to approve.")
                            .font(.footnote)
                            .foregroundColor(.secondary)
                    }
                }
                Section("Item") {
                    TextField("e.g. Milk", text: $name)
                    TextField("Quantity", text: $quantity)
                    StorePickerField(selection: $preferredStore)
                    Toggle("Set date", isOn: $hasDueDate)
                    if hasDueDate {
                        DatePicker("Date", selection: $dueDate, displayedComponents: [.date, .hourAndMinute])
                    }
                }
                Section("Assignment") {
                    Picker("Assigned To", selection: $assignedMemberId) {
                        Text("Anyone").tag(UUID?.none)
                        ForEach(store.members) { m in
                            Text(m.name).tag(Optional(m.id))
                        }
                    }
                }
                Section("Notes") {
                    TextField("Optional note", text: $note)
                }
            }
            .navigationTitle(editingItem == nil ? "Add Item" : (isSuggesting ? "Suggest Changes" : "Edit Item"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") { closeView() }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(editingItem == nil ? "Add" : (isSuggesting ? "Send" : "Save")) {
                        AuraHaptics.success()
                        let item = GroupListItem(
                            id: editingItem?.id ?? UUID(),
                            name: name,
                            quantity: quantity,
                            note: note,
                            isDone: editingItem?.isDone ?? false,
                            assignedMemberId: assignedMemberId,
                            preferredStore: preferredStore.isEmpty ? nil : preferredStore,
                            dueDate: hasDueDate ? dueDate : nil,
                            completedByName: editingItem?.completedByName,
                            boughtAt: editingItem?.boughtAt
                        )
                        if editingItem == nil {
                            store.addItem(to: listId, item: item)
                        } else if store.updateItem(listId: listId, item: item) == .proposed {
                            NotificationCenter.default.post(
                                name: .auraInAppBanner,
                                object: nil,
                                userInfo: ["title": "Change requested", "message": "Sent to \(creatorName) to approve."]
                            )
                        }
                        closeView()
                    }
                    .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .onAppear {
                guard let editingItem else { return }
                name = editingItem.name
                quantity = editingItem.quantity
                note = editingItem.note
                assignedMemberId = editingItem.assignedMemberId
                preferredStore = editingItem.preferredStore ?? ""
                if let due = editingItem.dueDate {
                    dueDate = due
                    hasDueDate = true
                }
            }
        }
    }
}

/// Where an item can be bought: one of the group's saved stores, or a new one
/// typed here (saved for everyone in the group).
struct StorePickerField: View {
    @EnvironmentObject var store: EventStore
    @Binding var selection: String
    @State private var addingNew = false
    @State private var newName = ""

    private static let newStoreTag = "__aurenda_new_store__"

    private var isUnsaved: Bool {
        !selection.isEmpty && !store.groupStores.contains { $0.name.caseInsensitiveCompare(selection) == .orderedSame }
    }

    var body: some View {
        Picker("Where to buy", selection: Binding(
            get: { selection },
            set: { value in
                if value == Self.newStoreTag {
                    addingNew = true
                } else {
                    selection = value
                }
            }
        )) {
            Text("Not set").tag("")
            ForEach(store.groupStores) { shop in
                Text(shop.name).tag(shop.name)
            }
            if isUnsaved {
                Text(selection).tag(selection)
            }
            Text("New store…").tag(Self.newStoreTag)
        }
        .alert("New Store", isPresented: $addingNew) {
            TextField("Store name", text: $newName)
            Button("Cancel", role: .cancel) { newName = "" }
            Button("Add") {
                if let name = store.addStore(named: newName) {
                    selection = name
                }
                newName = ""
            }
        } message: {
            Text("It's saved to this group's stores so everyone can pick it.")
        }
    }
}

/// The group's own list of stores. Anyone can add; the person who added a
/// store (or the group Owner) can remove it.
struct ManageStoresView: View {
    @EnvironmentObject var store: EventStore
    @Environment(\.dismiss) var dismiss
    @State private var newName = ""

    var body: some View {
        NavigationView {
            List {
                Section {
                    HStack {
                        TextField("Add a store", text: $newName)
                            .onSubmit(add)
                        Button("Add", action: add)
                            .disabled(newName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                } footer: {
                    Text("Stores are shared with everyone in \(store.activeServerGroupName == "No Group" ? "this group" : store.activeServerGroupName).")
                }
                Section("Stores") {
                    if store.groupStores.isEmpty {
                        Text("No stores yet")
                            .foregroundColor(.secondary)
                    }
                    ForEach(store.groupStores) { shop in
                        Text(shop.name)
                            .swipeActions {
                                if store.canDelete(shop) {
                                    Button(role: .destructive) {
                                        store.deleteStore(id: shop.id)
                                    } label: {
                                        Label("Delete", systemImage: "trash")
                                    }
                                }
                            }
                    }
                }
            }
            .navigationTitle("Stores")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    private func add() {
        store.addStore(named: newName)
        newName = ""
    }
}

struct AddGroupPlanView: View {
    @EnvironmentObject var store: EventStore
    @Binding var isPresented: Bool
    @State private var title = ""
    @State private var targetDate = Date().addingTimeInterval(7 * 86400)
    @State private var notes = ""

    var body: some View {
        NavigationView {
            Form {
                Section("Plan") {
                    TextField("e.g. Mom's Birthday Party", text: $title)
                    DatePicker("Target Date", selection: $targetDate, displayedComponents: [.date])
                }
                Section("Notes") {
                    TextField("Optional notes", text: $notes)
                }
            }
            .navigationTitle("New Plan")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") { isPresented = false }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Create") {
                        AuraHaptics.success()
                        store.addGroupPlan(title: title, targetDate: targetDate, notes: notes)
                        isPresented = false
                    }
                    .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }
}

struct GroupPlanDetailView: View {
    @EnvironmentObject var store: EventStore
    @Environment(\.dismiss) var dismiss
    let planId: UUID
    @State private var showAddItem = false
    @State private var editItem: GroupListItem? = nil

    var plan: GroupPlan? {
        store.groupPlans.first(where: { $0.id == planId })
    }

    var body: some View {
        NavigationView {
            ZStack {
                AuraAtmosphericBackground()
                List {
                    if let plan {
                        Section {
                            VStack(alignment: .leading, spacing: 8) {
                                HStack {
                                    Text("Target Date")
                                        .auraFont(size: 13, weight: .semibold)
                                    Spacer()
                                    Text(plan.targetDate.formatted(date: .abbreviated, time: .omitted))
                                        .foregroundColor(.secondary)
                                }
                                if !plan.notes.isEmpty {
                                    Text(plan.notes)
                                        .auraFont(size: 13)
                                        .foregroundColor(.secondary)
                                }
                                ProgressView(value: plan.progress)
                                    .tint(AuraThemePalette.current.accentStart)
                            }
                            .padding(AuraDesignTokens.Spacing.sm)
                            .auraGlassCard(radius: AuraDesignTokens.Radius.md)
                        }
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)

                        Section {
                            if plan.items.isEmpty {
                                Text("No steps yet")
                                    .foregroundColor(.secondary)
                                    .listRowBackground(Color.clear)
                            } else {
                                ForEach(plan.items) { item in
                                    itemRow(item)
                                        .padding(AuraDesignTokens.Spacing.sm)
                                        .auraGlassCard(radius: AuraDesignTokens.Radius.md)
                                        .listRowBackground(Color.clear)
                                        .listRowSeparator(.hidden)
                                }
                            }
                        } header: {
                            Text("STEPS")
                                .auraFont(size: 11, weight: .bold, design: .rounded)
                                .foregroundColor(.secondary)
                        }
                    }
                }
                .scrollContentBackground(.hidden)
            }
            .navigationTitle(plan?.title ?? "Plan")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Close") { dismiss() }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        showAddItem = true
                    } label: {
                        Image(systemName: "plus")
                            .accessibilityLabel("Add")
                    }
                }
            }
        }
        .sheet(isPresented: $showAddItem) {
            AddGroupPlanItemView(isPresented: $showAddItem, planId: planId)
                .environmentObject(store)
        }
        .sheet(item: $editItem) { item in
            AddGroupPlanItemView(isPresented: .constant(true), planId: planId, editingItem: item)
                .environmentObject(store)
        }
    }

    @ViewBuilder
    private func itemRow(_ item: GroupListItem) -> some View {
        HStack(spacing: 10) {
            Button {
                AuraHaptics.tap(.light)
                withAnimation(AuraMotion.quick) {
                    store.togglePlanItem(planId: planId, itemId: item.id)
                }
            } label: {
                Image(systemName: item.isDone ? "checkmark.circle.fill" : "circle")
                    .accessibilityLabel(item.isDone ? "Mark \(item.name) not done" : "Mark \(item.name) done")
                    .auraFont(size: 18, weight: .semibold)
                    .foregroundColor(item.isDone ? .green : .secondary)
            }
            .buttonStyle(.plain)

            VStack(alignment: .leading, spacing: 1) {
                Text(item.name)
                    .auraFont(size: 15, weight: .semibold)
                    .strikethrough(item.isDone)
                    .foregroundColor(item.isDone ? .secondary : .primary)
                if !item.note.isEmpty {
                    Text(item.note)
                        .auraFont(size: 12)
                        .foregroundColor(.secondary)
                }
            }
            Spacer()
            if let id = item.assignedMemberId,
               let m = store.members.first(where: { $0.id == id }) {
                Text(m.name)
                    .auraFont(size: 11, weight: .bold)
                    .foregroundColor(m.color)
            }
        }
        .swipeActions(edge: .leading, allowsFullSwipe: false) {
            Button {
                editItem = item
            } label: {
                Label(plan.map { store.canEdit(item: item, in: $0) } ?? false ? "Edit" : "Suggest Changes", systemImage: "pencil")
            }
            .tint(AuraThemePalette.current.accentStart)
        }
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            if plan.map({ store.canDelete(item: item, in: $0) }) ?? false {
                Button(role: .destructive) {
                    store.deletePlanItem(planId: planId, itemId: item.id)
                } label: {
                    Label("Delete", systemImage: "trash")
                }
            }
        }
    }
}

struct AddGroupPlanItemView: View {
    @EnvironmentObject var store: EventStore
    @Environment(\.dismiss) var dismiss
    @Binding var isPresented: Bool
    let planId: UUID
    var editingItem: GroupListItem? = nil

    /// Editing a step someone else added: saving sends them a request.
    private var isSuggesting: Bool {
        guard let editingItem, let plan = store.groupPlans.first(where: { $0.id == planId }) else { return false }
        return !store.canEdit(item: editingItem, in: plan)
    }

    @State private var name = ""
    @State private var note = ""
    @State private var assignedMemberId: UUID? = nil
    @State private var dueDate = Date()
    @State private var hasDueDate = false

    private func closeView() {
        if editingItem == nil {
            isPresented = false
        } else {
            dismiss()
        }
    }

    var body: some View {
        NavigationView {
            Form {
                Section("Step") {
                    TextField("e.g. Book the venue", text: $name)
                    Toggle("Set date", isOn: $hasDueDate)
                    if hasDueDate {
                        DatePicker("Date", selection: $dueDate, displayedComponents: [.date, .hourAndMinute])
                    }
                }
                Section("Assignment") {
                    Picker("Assigned To", selection: $assignedMemberId) {
                        Text("Anyone").tag(UUID?.none)
                        ForEach(store.members) { m in
                            Text(m.name).tag(Optional(m.id))
                        }
                    }
                }
                Section("Notes") {
                    TextField("Optional note", text: $note)
                }
            }
            .navigationTitle(editingItem == nil ? "Add Step" : (isSuggesting ? "Suggest Changes" : "Edit Step"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") { closeView() }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(editingItem == nil ? "Add" : (isSuggesting ? "Send" : "Save")) {
                        AuraHaptics.success()
                        let item = GroupListItem(
                            id: editingItem?.id ?? UUID(),
                            name: name,
                            quantity: "",
                            note: note,
                            isDone: editingItem?.isDone ?? false,
                            assignedMemberId: assignedMemberId,
                            preferredStore: nil,
                            dueDate: hasDueDate ? dueDate : nil,
                            completedByName: editingItem?.completedByName,
                            boughtAt: editingItem?.boughtAt
                        )
                        if editingItem == nil {
                            store.addPlanItem(to: planId, item: item)
                        } else if store.updatePlanItem(planId: planId, item: item) == .proposed {
                            let owner = store.groupPlans.first(where: { $0.id == planId })?.ownerName ?? ""
                            NotificationCenter.default.post(
                                name: .auraInAppBanner,
                                object: nil,
                                userInfo: ["title": "Change requested", "message": "Sent to \(store.creatorName(ownerName: owner)) to approve."]
                            )
                        }
                        closeView()
                    }
                    .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .onAppear {
                guard let editingItem else { return }
                name = editingItem.name
                note = editingItem.note
                assignedMemberId = editingItem.assignedMemberId
                if let due = editingItem.dueDate {
                    dueDate = due
                    hasDueDate = true
                }
            }
        }
    }
}

struct AddActivityView: View {
    @EnvironmentObject var store: EventStore
    @Environment(\.dismiss) var dismiss
    @Binding var isPresented: Bool
    var editingActivity: GroupActivity? = nil
    @State private var kind: GroupActivityKind = .walk
    @State private var date = Date()
    @State private var duration = 30
    @State private var notes = ""
    @State private var selectedMembers: Set<UUID> = []
    @State private var visibility: VisibilityScope = .family
    @State private var customNames: Set<String> = []

    private func closeView() {
        if editingActivity == nil {
            isPresented = false
        } else {
            dismiss()
        }
    }

    var body: some View {
        NavigationView {
            Form {
                Section("Activity") {
                    Picker("Type", selection: $kind) {
                        ForEach(GroupActivityKind.allCases, id: \.self) { k in
                            Label(k.rawValue, systemImage: k.icon).tag(k)
                        }
                    }
                    DatePicker("Date", selection: $date)
                    Stepper(value: $duration, in: 5...300, step: 5) {
                        Text("Duration: \(duration) min")
                    }
                }
                Section("Participants") {
                    ForEach(store.members) { m in
                        Button {
                            if selectedMembers.contains(m.id) {
                                selectedMembers.remove(m.id)
                            } else {
                                selectedMembers.insert(m.id)
                            }
                        } label: {
                            HStack {
                                Circle().fill(m.color).frame(width: 10, height: 10)
                                Text(m.name).foregroundColor(.primary)
                                Spacer()
                                if selectedMembers.contains(m.id) {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundColor(AuraThemePalette.current.accentStart)
                                }
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
                Section("Visibility") {
                    Picker("Who can see this", selection: $visibility) {
                        ForEach(VisibilityScope.allCases, id: \.self) { s in
                            Label(s.displayName, systemImage: s.icon).tag(s)
                        }
                    }
                    Text(visibility.subtitle)
                        .auraFont(size: 12)
                        .foregroundColor(.secondary)
                }
                if visibility == .custom {
                    Section("Share With") {
                        ForEach(store.members.map(\.name), id: \.self) { name in
                            Button {
                                if customNames.contains(name) {
                                    customNames.remove(name)
                                } else {
                                    customNames.insert(name)
                                }
                            } label: {
                                HStack {
                                    Text(name).foregroundColor(.primary)
                                    Spacer()
                                    if customNames.contains(name) {
                                        Image(systemName: "checkmark.circle.fill")
                                            .foregroundColor(AuraThemePalette.current.accentStart)
                                    }
                                }
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                Section("Notes") {
                    TextField("Optional notes", text: $notes, axis: .vertical)
                }
            }
            .navigationTitle("Log Activity")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") { closeView() }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(editingActivity == nil ? "Save" : "Update") {
                        AuraHaptics.success()
                        let activity = GroupActivity(
                            id: editingActivity?.id ?? UUID(),
                            kind: kind,
                            date: date,
                            durationMinutes: duration,
                            notes: notes,
                            participantIds: Array(selectedMembers),
                            ownerName: editingActivity?.ownerName ?? store.activeProfileName,
                            visibility: visibility,
                            sharedWithNames: Array(customNames)
                        )
                        if editingActivity == nil {
                            store.addActivity(activity)
                        } else {
                            store.updateActivity(activity)
                        }
                        closeView()
                    }
                }
            }
            .onAppear {
                guard let editingActivity else { return }
                kind = editingActivity.kind
                date = editingActivity.date
                duration = editingActivity.durationMinutes
                notes = editingActivity.notes
                selectedMembers = Set(editingActivity.participantIds)
                visibility = editingActivity.visibility
                customNames = Set(editingActivity.sharedWithNames)
            }
        }
    }
}

struct StartLiveActivityView: View {
    @EnvironmentObject var store: EventStore
    @Binding var isPresented: Bool
    @State private var kind: GroupActivityKind = .walk
    @State private var notes = ""
    @State private var selectedMembers: Set<UUID> = []
    @State private var visibility: VisibilityScope = .family
    @State private var customNames: Set<String> = []

    var body: some View {
        NavigationView {
            Form {
                Section("Activity") {
                    Picker("Type", selection: $kind) {
                        ForEach(GroupActivityKind.allCases, id: \.self) { kind in
                            Label(kind.rawValue, systemImage: kind.icon).tag(kind)
                        }
                    }
                }
                Section("Participants") {
                    ForEach(store.members) { member in
                        Button {
                            if selectedMembers.contains(member.id) {
                                selectedMembers.remove(member.id)
                            } else {
                                selectedMembers.insert(member.id)
                            }
                        } label: {
                            HStack {
                                Text(member.name).foregroundColor(.primary)
                                Spacer()
                                if selectedMembers.contains(member.id) {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundColor(AuraThemePalette.current.accentStart)
                                }
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
                Section("Visibility") {
                    Picker("Who can see this", selection: $visibility) {
                        ForEach(VisibilityScope.allCases, id: \.self) { scope in
                            Label(scope.displayName, systemImage: scope.icon).tag(scope)
                        }
                    }
                }
                if visibility == .custom {
                    Section("Share With") {
                        ForEach(store.members.map(\.name), id: \.self) { name in
                            Button {
                                if customNames.contains(name) { customNames.remove(name) } else { customNames.insert(name) }
                            } label: {
                                HStack {
                                    Text(name).foregroundColor(.primary)
                                    Spacer()
                                    if customNames.contains(name) {
                                        Image(systemName: "checkmark.circle.fill")
                                            .foregroundColor(AuraThemePalette.current.accentStart)
                                    }
                                }
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                Section("Notes") {
                    TextField("Optional notes", text: $notes)
                }
            }
            .navigationTitle("Track Activity")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") { isPresented = false }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Start") {
                        store.startLiveActivity(kind: kind, notes: notes, participantIds: Array(selectedMembers), visibility: visibility, sharedWithNames: Array(customNames))
                        AuraHaptics.success()
                        isPresented = false
                    }
                }
            }
        }
    }
}

struct QuickAddShoppingItemView: View {
    @EnvironmentObject var store: EventStore
    @Binding var isPresented: Bool
    @State private var name = ""
    @State private var quantity = ""
    @State private var preferredStore: String = ""
    @State private var assignedMemberId: UUID? = nil
    @State private var hasDueDate = false
    @State private var dueDate = Date()
    @State private var newListVisibility: VisibilityScope = .family

    var firstSupermarketList: GroupList? {
        store.visibleGroupLists.first(where: { $0.kind == .supermarket }) ?? store.visibleGroupLists.first
    }

    var body: some View {
        NavigationView {
            Form {
                Section("Item") {
                    TextField("Item name", text: $name)
                    TextField("Quantity", text: $quantity)
                    StorePickerField(selection: $preferredStore)
                    Picker("Responsible", selection: $assignedMemberId) {
                        Text("Anyone").tag(UUID?.none)
                        ForEach(store.members) { member in
                            Text(member.name).tag(Optional(member.id))
                        }
                    }
                    Toggle("Set date", isOn: $hasDueDate)
                    if hasDueDate {
                        DatePicker("Date", selection: $dueDate, displayedComponents: [.date, .hourAndMinute])
                    }
                }
                Section {
                    if let list = firstSupermarketList {
                        Text("Will be added to: \(list.title)")
                            .auraFont(size: 13)
                            .foregroundColor(.secondary)
                    } else {
                        Text("No list found. A Shopping List will be created in \(store.activeServerGroupName).")
                            .auraFont(size: 13)
                            .foregroundColor(.secondary)
                        Picker("Who can see it", selection: $newListVisibility) {
                            ForEach([VisibilityScope.family, .personal], id: \.self) { s in
                                Label(s.displayName, systemImage: s.icon).tag(s)
                            }
                        }
                    }
                }
            }
            .navigationTitle("Quick Add")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") { isPresented = false }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Add") {
                        AuraHaptics.success()
                        if firstSupermarketList == nil {
                            store.addGroupList(title: "Shopping List", kind: .supermarket, visibility: newListVisibility, sharedWithNames: [])
                        }
                        if let target = store.visibleGroupLists.first(where: { $0.kind == .supermarket }) ?? store.visibleGroupLists.first {
                            store.addItem(to: target.id, item: .init(name: name, quantity: quantity, note: "", isDone: false, assignedMemberId: assignedMemberId, preferredStore: preferredStore.isEmpty ? nil : preferredStore, dueDate: hasDueDate ? dueDate : nil, completedByName: nil, boughtAt: nil))
                        }
                        isPresented = false
                    }
                    .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }
}

struct AddMemberView: View {
    @EnvironmentObject var store: EventStore
    @Binding var isPresented: Bool
    @State private var name = ""
    @State private var role = "Parent"
    @State private var color = Color(hex: "6366F1")

    var body: some View {
        NavigationView {
            ZStack {
                AuraAtmosphericBackground()
                Form {
                    Section("Member") {
                        TextField("Name", text: $name)
                        TextField("Role", text: $role)
                        ColorPicker("Color", selection: $color)
                    }
                }
                .scrollContentBackground(.hidden)
            }
            .navigationTitle("Add Member")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") { isPresented = false }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Save") {
                        AuraHaptics.success()
                        let member = GroupMember(name: name, colorHex: color.toHex(), role: role, allowsStepSharing: false)
                        store.addMember(member)
                        store.setActiveMember(id: member.id)
                        isPresented = false
                    }
                    .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }
}
