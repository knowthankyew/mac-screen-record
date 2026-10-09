import SwiftUI

struct PresetsBar: View {
    @ObservedObject var vm: RecordingViewModel
    @ObservedObject private var presets: PresetsStore
    @State private var showSaveSheet = false
    @State private var newPresetName: String = ""
    @State private var useForFacecam: Bool = false
    @State private var setAsStartupDefault: Bool = false

    init(vm: RecordingViewModel) {
        self.vm = vm
        self._presets = ObservedObject(wrappedValue: vm.presets)
    }

    private var isDuplicateName: Bool {
        let trimmed = newPresetName.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return false }
        return presets.presets.contains { $0.name.caseInsensitiveCompare(trimmed) == .orderedSame }
    }

    var body: some View {
        HStack(spacing: 10) {
            // Profile Dropdown Selector
            Menu {
                // Section: Available Profiles
                if presets.presets.isEmpty {
                    Text("No profiles saved").foregroundStyle(.secondary)
                } else {
                    Section("Saved Profiles") {
                        ForEach(presets.presets) { p in
                            Button {
                                vm.apply(p)
                            } label: {
                                let badges = (presets.defaultPresetID == p.id ? " ★" : "") + (p.webcamEnabled && p.useForFacecam ? " 🔲" : "")
                                let title = p.name + badges
                                if vm.activePresetID == p.id {
                                    Label(title, systemImage: "checkmark")
                                } else {
                                    Text(title)
                                }
                            }
                        }
                    }

                    if let active = vm.activePreset {
                        Divider()
                        Button(vm.isPresetModified ? "Update '\(active.name)' with Current Settings" : "Re-save '\(active.name)'") {
                            vm.updateActivePreset()
                        }
                    }

                    Divider()
                    Menu("Startup Default Profile…") {
                        Button {
                            vm.setDefaultPreset(id: nil)
                        } label: {
                            if presets.defaultPresetID == nil {
                                Label("None (Use Last Settings)", systemImage: "checkmark")
                            } else {
                                Text("None (Use Last Settings)")
                            }
                        }
                        Divider()
                        ForEach(presets.presets) { p in
                            Button {
                                vm.setDefaultPreset(id: p.id)
                            } label: {
                                if presets.defaultPresetID == p.id {
                                    Label(p.name, systemImage: "checkmark")
                                } else {
                                    Text(p.name)
                                }
                            }
                        }
                    }

                    if !presets.presetsWithPIP.isEmpty {
                        Menu("Default Facecam Profile…") {
                            ForEach(presets.presetsWithPIP) { p in
                                Button {
                                    vm.setAsFacecamPreset(id: p.id)
                                } label: {
                                    if p.useForFacecam {
                                        Label(p.name, systemImage: "checkmark")
                                    } else {
                                        Text(p.name)
                                    }
                                }
                            }
                        }
                    }

                    Divider()
                    Menu("Delete Profile…") {
                        ForEach(presets.presets) { p in
                            Button(role: .destructive) {
                                vm.deletePreset(id: p.id)
                            } label: {
                                Text(p.name)
                            }
                        }
                    }
                }
            } label: {
                HStack(spacing: 7) {
                    Image(systemName: "slider.horizontal.2")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(vm.activePreset != nil ? Color.accentColor : Color.secondary)

                    HStack(spacing: 5) {
                        Text("Profile:")
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        if let active = vm.activePreset {
                            Text(active.name)
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.primary)
                                .lineLimit(1)

                            if vm.isPresetModified {
                                Text("• modified")
                                    .font(.caption2.weight(.semibold))
                                    .foregroundStyle(.orange)
                                    .help("Current settings differ from the saved profile")
                            }

                            if presets.defaultPresetID == active.id {
                                Image(systemName: "star.fill")
                                    .font(.system(size: 9))
                                    .foregroundStyle(.yellow)
                                    .help("Loads automatically on startup")
                            }

                            if active.webcamEnabled && active.useForFacecam {
                                Image(systemName: "person.crop.square.fill")
                                    .font(.system(size: 9))
                                    .foregroundStyle(Color.accentColor)
                                    .help("Designated Facecam profile")
                            }
                        } else {
                            Text("Custom Settings")
                                .font(.caption.weight(.medium))
                                .foregroundStyle(.secondary)
                        }
                    }

                    Image(systemName: "chevron.up.chevron.down")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 9)
                .padding(.vertical, 4)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Color(nsColor: .controlBackgroundColor))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(Color.secondary.opacity(0.25), lineWidth: 1)
                )
            }
            .menuStyle(.borderlessButton)
            .fixedSize()

            Button {
                newPresetName = "Preset \(presets.presets.count + 1)"
                useForFacecam = vm.webcamEnabled && presets.presetsWithPIP.isEmpty
                setAsStartupDefault = presets.presets.isEmpty
                showSaveSheet = true
            } label: {
                Label("Save As…", systemImage: "plus")
                    .font(.caption)
            }
            .controlSize(.small)
            .buttonStyle(.bordered)

            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(.thinMaterial)
        .sheet(isPresented: $showSaveSheet) {
            VStack(alignment: .leading, spacing: 14) {
                Text("Save Current Settings as Profile").font(.headline)
                TextField("Profile Name", text: $newPresetName)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 300)

                if isDuplicateName {
                    Text("A profile with this name exists and will be saved with a unique suffix.")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }

                Toggle("Set as default profile on startup", isOn: $setAsStartupDefault)
                    .font(.subheadline)
                    .help("Loads these settings automatically whenever Mac Screen Record launches")

                if vm.webcamEnabled {
                    Toggle("Use as default Facecam profile", isOn: $useForFacecam)
                        .font(.subheadline)
                        .help("Quick toggle in the header will activate this profile's Facecam configuration")
                }

                HStack {
                    Spacer()
                    Button("Cancel") { showSaveSheet = false }
                    Button("Save") {
                        let trimmed = newPresetName.trimmingCharacters(in: .whitespaces)
                        guard !trimmed.isEmpty else { return }
                        vm.saveCurrentAsPreset(named: trimmed, useForFacecam: useForFacecam, setAsStartupDefault: setAsStartupDefault)
                        showSaveSheet = false
                    }
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.borderedProminent)
                }
            }
            .padding(20)
        }
    }
}
