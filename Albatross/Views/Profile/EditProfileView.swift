import PhotosUI
import SwiftUI

struct EditProfileView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(AuthStore.self) private var authStore

    @State private var displayName: String
    @State private var username: String
    @State private var homeCourse: String
    @State private var location: String
    @State private var avatarImage: UIImage? = nil
    @State private var selectedPhotoItem: PhotosPickerItem? = nil
    @State private var isSaving = false

    init(
        initialDisplayName: String = "",
        initialUsername: String = "",
        initialHomeCourse: String = "",
        initialLocation: String = ""
    ) {
        _displayName = State(initialValue: initialDisplayName)
        _username    = State(initialValue: initialUsername)
        _homeCourse  = State(initialValue: initialHomeCourse)
        _location    = State(initialValue: initialLocation)
    }

    var body: some View {
        NavigationStack {
            Form {
                // MARK: Avatar
                Section {
                    HStack {
                        Spacer()
                        PhotosPicker(selection: $selectedPhotoItem, matching: .images) {
                            ZStack(alignment: .bottomTrailing) {
                                avatarCircle(size: 88)

                                Circle()
                                    .fill(Color(.secondarySystemGroupedBackground))
                                    .frame(width: 28, height: 28)
                                    .overlay(
                                        Image(systemName: "camera.fill")
                                            .appFont(.small, weight: .medium)
                                            .foregroundStyle(Color.accentColor)
                                    )
                                    .offset(x: 4, y: 4)
                            }
                        }
                        .buttonStyle(.pressFeedback)
                        Spacer()
                    }
                    .listRowBackground(Color.clear)
                    .padding(.vertical, 8)

                    if avatarImage != nil {
                        Button(role: .destructive) {
                            avatarImage = nil
                            try? FileManager.default.removeItem(at: UserProfile.localAvatarURL)
                        } label: {
                            HStack {
                                Spacer()
                                Text("Remove Photo")
                                    .appFont(.small)
                                Spacer()
                            }
                        }
                    }
                } header: {
                    Text("Photo")
                        .appFont(.small)
                }

                // MARK: Profile info
                Section {
                    LabeledContent("First Name") {
                        TextField("Your name", text: $displayName)
                            .appFont(.body)
                            .multilineTextAlignment(.trailing)
                    }
                    .appFont(.body)

                    LabeledContent("Username") {
                        TextField("username", text: $username)
                            .appFont(.body)
                            .multilineTextAlignment(.trailing)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .onChange(of: username) { _, val in
                                let cleaned = val.lowercased().filter { !$0.isWhitespace }
                                if cleaned != val { username = cleaned }
                            }
                    }
                    .appFont(.body)
                } header: {
                    Text("Profile Info")
                        .appFont(.small)
                }

                // MARK: Golf info
                Section {
                    LabeledContent("Home Course") {
                        TextField("Course name", text: $homeCourse)
                            .appFont(.body)
                            .multilineTextAlignment(.trailing)
                    }
                    .appFont(.body)

                    LabeledContent("Location") {
                        TextField("City, State", text: $location)
                            .appFont(.body)
                            .multilineTextAlignment(.trailing)
                    }
                    .appFont(.body)
                } header: {
                    Text("Golf Info")
                        .appFont(.small)
                }
            }
            .navigationTitle("Edit Profile")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button { dismiss() } label: {
                        Label("Cancel", systemImage: "xmark")
                    }
                }
                ToolbarItem(placement: .albatrossConfirm) {
                    if isSaving {
                        ProgressView()
                    } else {
                        Button { Task { await save() } } label: {
                            Label("Save", systemImage: "checkmark")
                        }
                    }
                }
            }
            .onAppear { loadAvatar() }
            .onChange(of: selectedPhotoItem) { _, item in
                guard let item else { return }
                Task {
                    if let data = try? await item.loadTransferable(type: Data.self),
                       let image = UIImage(data: data) {
                        avatarImage = image
                    }
                }
            }
        }
    }

    // MARK: - Avatar view

    @ViewBuilder
    private func avatarCircle(size: CGFloat) -> some View {
        if let img = avatarImage {
            Image(uiImage: img)
                .resizable()
                .scaledToFill()
                .frame(width: size, height: size)
                .clipShape(Circle())
        } else {
            let initials = displayName.split(separator: " ")
                .compactMap { $0.first.map(String.init) }
                .prefix(2)
                .joined()
            Circle()
                .fill(Color.accentColor.opacity(0.15))
                .frame(width: size, height: size)
                .overlay(
                    Text(initials.isEmpty ? "?" : initials)
                        .font(.system(size: size * 0.38, weight: .semibold))
                        .foregroundStyle(Color.accentColor)
                )
        }
    }

    // MARK: - Load avatar from disk

    private func loadAvatar() {
        if let data = try? Data(contentsOf: UserProfile.localAvatarURL),
           let img = UIImage(data: data) {
            avatarImage = img
        }
    }

    // MARK: - Save

    private func save() async {
        isSaving = true
        defer { isSaving = false }

        // Save avatar locally
        if let img = avatarImage,
           let data = img.jpegData(compressionQuality: 0.85) {
            try? data.write(to: UserProfile.localAvatarURL, options: .atomic)
        }

        // Update Supabase profile
        await authStore.updateProfile(
            displayName: displayName,
            username: username,
            homeCourse: homeCourse,
            location: location
        )
        dismiss()
    }
}

#Preview {
    EditProfileView(
        initialDisplayName: "Matt Trujillo",
        initialUsername: "matttruj",
        initialHomeCourse: "Augusta National",
        initialLocation: "Atlanta, GA"
    )
    .environment(AuthStore())
}
