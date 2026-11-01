import SwiftUI
import WidgetKit
import UserNotifications
import PhotosUI
import UniformTypeIdentifiers
import HealthKit
import LocalAuthentication
import AVFoundation

struct DeleteAccountView: View {
    @EnvironmentObject var store: EventStore
    @Binding var isPresented: Bool
    @State private var password = ""
    @State private var isWorking = false
    @State private var errorMessage = ""
    @State private var showFinalConfirm = false
    @State private var isExporting = false
    @State private var exportedFile: IdentifiableURL?
    @State private var exportError = ""

    var body: some View {
        NavigationView {
            ZStack {
                AuraAtmosphericBackground()
                Form {
                    Section {
                        Label("This cannot be undone", systemImage: "exclamationmark.triangle.fill")
                            .foregroundColor(.red)
                            .font(.system(size: 14, weight: .bold))
                        Text("Any group only you belong to is deleted along with your account. Groups you share with others stay -- ownership passes to another member instead.")
                            .font(.system(size: 13))
                            .foregroundColor(.secondary)
                    }
                    Section {
                        Button {
                            isExporting = true
                            exportError = ""
                            Task {
                                let result = await store.exportAccountData()
                                await MainActor.run {
                                    isExporting = false
                                    switch result {
                                    case .success(let url):
                                        exportedFile = IdentifiableURL(url: url)
                                    case .failure(let error):
                                        exportError = error.localizedDescription
                                    }
                                }
                            }
                        } label: {
                            if isExporting {
                                ProgressView()
                            } else {
                                Label("Export My Data First", systemImage: "square.and.arrow.up")
                            }
                        }
                        .disabled(isExporting)
                        if !exportError.isEmpty {
                            Text(exportError)
                                .font(.system(size: 12, weight: .medium))
                                .foregroundColor(.red)
                        }
                    } footer: {
                        Text("Downloads a copy of your account and group data as a file you can save or share.")
                    }
                    Section {
                        AuraSecureField(placeholder: "Confirm your password", text: $password)
                    } footer: {
                        Text("For your security, confirm your password to continue.")
                    }
                    if !errorMessage.isEmpty {
                        Section {
                            Text(errorMessage)
                                .font(.system(size: 13, weight: .medium))
                                .foregroundColor(.red)
                        }
                    }
                    Section {
                        Button(role: .destructive) {
                            showFinalConfirm = true
                        } label: {
                            if isWorking {
                                ProgressView()
                            } else {
                                Text("Delete My Account")
                            }
                        }
                        .disabled(password.isEmpty || isWorking)
                    }
                }
                .scrollContentBackground(.hidden)
            }
            .navigationTitle("Delete Account")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") { isPresented = false }
                }
            }
            .confirmationDialog(
                "Permanently delete your account?",
                isPresented: $showFinalConfirm,
                titleVisibility: .visible
            ) {
                Button("Delete My Account", role: .destructive) {
                    isWorking = true
                    errorMessage = ""
                    Task {
                        let result = await store.deleteServerAccount(password: password)
                        await MainActor.run {
                            isWorking = false
                            switch result {
                            case .success:
                                AuraHaptics.success()
                                isPresented = false
                            case .failure(let error):
                                errorMessage = error.localizedDescription
                            }
                        }
                    }
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This is your last chance to back out.")
            }
        }
        .sheet(item: $exportedFile) { file in
            ActivityShareSheet(activityItems: [file.url])
        }
    }
}

struct JoinOrCreateGroupView: View {
    enum Mode { case create, join }

    @EnvironmentObject var store: EventStore
    @Binding var isPresented: Bool
    @State var mode: Mode
    @State private var groupName = ""
    @State private var groupType = "Family"
    @State private var joinCode = ""
    @State private var isWorking = false
    @State private var message = ""

    var body: some View {
        NavigationView {
            Form {
                Section {
                    Picker("Mode", selection: $mode) {
                        Text("Create New").tag(Mode.create)
                        Text("Join Existing").tag(Mode.join)
                    }
                    .pickerStyle(.segmented)
                    .listRowBackground(Color.clear)
                }

                if mode == .create {
                    Section {
                        TextField("Group name", text: $groupName)
                        Picker("Group type", selection: $groupType) {
                            Text("Family").tag("Family")
                            Text("Roommates").tag("Roommates")
                            Text("Couple").tag("Couple")
                            Text("Church").tag("Church")
                            Text("Travel").tag("Travel")
                            Text("Study").tag("Study")
                            Text("Custom").tag("Custom")
                        }
                    } footer: {
                        Text("Creates a brand new, isolated group workspace. You'll be its Owner.")
                    }
                } else {
                    Section {
                        TextField("Join code", text: $joinCode)
                            .textInputAutocapitalization(.characters)
                            .autocorrectionDisabled(true)
                    } footer: {
                        Text("Ask the group's owner for their join code (visible on their Group Members screen).")
                    }
                }

                if isWorking {
                    Section { ProgressView() }
                }
                if !message.isEmpty {
                    Section {
                        Text(message)
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(.secondary)
                    }
                }
            }
            .navigationTitle(mode == .create ? "Create Group" : "Join Group")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") { isPresented = false }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(mode == .create ? "Create" : "Join") {
                        isWorking = true
                        message = ""
                        Task {
                            let result: Result<Void, Error>
                            if mode == .create {
                                let createResult = await store.createServerGroup(name: groupName, type: groupType)
                                result = createResult.map { _ in () }
                            } else {
                                result = await store.joinServerGroup(code: joinCode)
                            }
                            await MainActor.run {
                                isWorking = false
                                switch result {
                                case .success:
                                    AuraHaptics.success()
                                    isPresented = false
                                case .failure(let error):
                                    message = error.localizedDescription
                                }
                            }
                        }
                    }
                    .disabled(isWorking || (mode == .create ? groupName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty : joinCode.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty))
                }
            }
        }
    }
}

func groupTypeIcon(_ type: String) -> String {
    switch type {
    case "Family": return "house.fill"
    case "Roommates": return "person.2.fill"
    case "Couple": return "heart.fill"
    case "Church": return "building.columns.fill"
    case "Travel": return "airplane"
    case "Study": return "book.fill"
    default: return "square.stack.3d.up.fill"
    }
}

struct GroupsHubView: View {
    @EnvironmentObject var store: EventStore
    @Binding var isPresented: Bool
    @State private var joinOrCreateMode: JoinOrCreateGroupView.Mode = .create
    @State private var showJoinOrCreate = false
    @State private var renamingGroup: AuraRemoteGroupRecord?
    @State private var renameText = ""
    @State private var renameError = ""
    @State private var isRenaming = false

    var columns: [GridItem] { [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)] }

    var body: some View {
        NavigationView {
            ZStack {
                AuraAtmosphericBackground()
                ScrollView {
                    if store.serverGroups.isEmpty {
                        VStack(spacing: 10) {
                            Image(systemName: "square.stack.3d.up.slash")
                                .font(.system(size: 30))
                                .foregroundColor(.secondary.opacity(0.4))
                            Text("No groups yet")
                                .font(.system(size: 15, weight: .semibold))
                            Text("Create one, or join with a code from someone who already has one.")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundColor(.secondary)
                                .multilineTextAlignment(.center)
                        }
                        .padding(.top, 60)
                        .padding(.horizontal, 30)
                    } else {
                        LazyVGrid(columns: columns, spacing: 12) {
                            ForEach(store.serverGroups) { record in
                                Button {
                                    if record.group.id != store.activeServerGroupId {
                                        AuraHaptics.tap(.medium)
                                        store.setActiveServerGroup(id: record.group.id)
                                    }
                                    isPresented = false
                                } label: {
                                    GroupCard(record: record, isActive: record.group.id == store.activeServerGroupId)
                                }
                                .buttonStyle(.plain)
                                .contextMenu {
                                    if record.membership.role == "Owner" {
                                        Button {
                                            renameText = record.group.name
                                            renameError = ""
                                            renamingGroup = record
                                        } label: {
                                            Label("Rename Group", systemImage: "pencil")
                                        }
                                    }
                                }
                            }
                        }
                        .padding(16)
                    }

                    VStack(spacing: 10) {
                        Button {
                            joinOrCreateMode = .create
                            showJoinOrCreate = true
                        } label: {
                            Label("Create New Group", systemImage: "plus.circle")
                                .font(.system(size: 14, weight: .semibold))
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 12)
                        }
                        .background(Color(.secondarySystemBackground).opacity(0.7), in: RoundedRectangle(cornerRadius: 14, style: .continuous))

                        Button {
                            joinOrCreateMode = .join
                            showJoinOrCreate = true
                        } label: {
                            Label("Join Another Group", systemImage: "person.badge.key")
                                .font(.system(size: 14, weight: .semibold))
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 12)
                        }
                        .background(Color(.secondarySystemBackground).opacity(0.7), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 24)
                }
            }
            .navigationTitle("Groups")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") { isPresented = false }
                }
            }
        }
        .sheet(isPresented: $showJoinOrCreate) {
            JoinOrCreateGroupView(isPresented: $showJoinOrCreate, mode: joinOrCreateMode)
                .environmentObject(store)
        }
        .sheet(item: $renamingGroup) { record in
            NavigationView {
                Form {
                    Section {
                        TextField("Group name", text: $renameText)
                    }
                    if !renameError.isEmpty {
                        Section {
                            Text(renameError).foregroundColor(.red).font(.system(size: 13))
                        }
                    }
                }
                .navigationTitle("Rename Group")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .navigationBarLeading) {
                        Button("Cancel") { renamingGroup = nil }
                    }
                    ToolbarItem(placement: .navigationBarTrailing) {
                        if isRenaming {
                            ProgressView()
                        } else {
                            Button("Save") {
                                let groupId = record.group.id
                                let name = renameText
                                isRenaming = true
                                Task {
                                    let result = await store.renameGroup(groupId: groupId, name: name)
                                    await MainActor.run {
                                        isRenaming = false
                                        switch result {
                                        case .success:
                                            renamingGroup = nil
                                        case .failure(let error):
                                            renameError = error.localizedDescription
                                        }
                                    }
                                }
                            }
                            .fontWeight(.semibold)
                            .disabled(renameText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        }
                    }
                }
            }
            .presentationDetents([.height(220)])
        }
    }
}

struct GroupCard: View {
    let record: AuraRemoteGroupRecord
    let isActive: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                ZStack {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(LinearGradient(
                            colors: [AuraThemePalette.current.accentStart, AuraThemePalette.current.accentEnd],
                            startPoint: .topLeading, endPoint: .bottomTrailing))
                        .frame(width: 36, height: 36)
                    Image(systemName: groupTypeIcon(record.group.type))
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(.white)
                }
                Spacer()
                if isActive {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 18))
                        .foregroundColor(AuraThemePalette.current.accentStart)
                }
            }
            Text(record.group.name)
                .font(.system(size: 14, weight: .bold))
                .foregroundColor(.primary)
                .lineLimit(1)
            Text(record.group.type)
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(.secondary)
            Text(record.membership.role)
                .font(.system(size: 10, weight: .bold))
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(Color(.tertiarySystemBackground), in: Capsule())
                .foregroundColor(.secondary)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemBackground).opacity(0.7), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(isActive ? AuraThemePalette.current.accentStart.opacity(0.6) : Color.clear, lineWidth: 1.5)
        )
    }
}

struct AuraInAppBannerView: View {
    let payload: InAppBannerPayload
    let palette: AuraThemePalette

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "bell.badge.fill")
                .font(.system(size: 15, weight: .semibold))
                .foregroundColor(.white)
                .frame(width: 30, height: 30)
                .background(.white.opacity(0.2), in: RoundedRectangle(cornerRadius: 9))
            VStack(alignment: .leading, spacing: 1) {
                Text(payload.title)
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(.white)
                    .lineLimit(1)
                if !payload.message.isEmpty {
                    Text(payload.message)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.white.opacity(0.9))
                        .lineLimit(2)
                }
            }
            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(
            LinearGradient(
                colors: [palette.backgroundStart, palette.backgroundEnd],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            ),
            in: RoundedRectangle(cornerRadius: 14)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(.white.opacity(0.12), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.2), radius: 8, y: 4)
    }
}
