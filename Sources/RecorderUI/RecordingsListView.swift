import AppKit
import CaptureCore
import EncoderKit
import SwiftUI
import UniformTypeIdentifiers

struct RecordingsListView: View {
    @ObservedObject var library: RecordingsLibrary
    public var settings: AppSettings = .shared
    @Environment(\.dismiss) private var dismiss
    @State private var renamingID: URL?
    @State private var renameText: String = ""
    @State private var exportingID: URL?
    @State private var exportTask: Task<Void, Never>?
    @State private var activeTrimTarget: RecordingViewModel.TrimTarget?
    @State private var errorMessage: String?

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Recordings").font(.title2.bold())
                Spacer()
                Button {
                    openExternalVideoToTrim()
                } label: {
                    Label("Trim Video…", systemImage: "scissors")
                }
                .buttonStyle(.bordered)
                .help("Load any .mp4, .mov, or .m4v video from disk to trim losslessly")

                Button {
                    Task { await library.reload() }
                } label: { Image(systemName: "arrow.clockwise") }
                    .buttonStyle(.borderless)
                Button("Done") { dismiss() }.keyboardShortcut(.defaultAction)
            }
            .padding(16)
            Divider()
            if library.files.isEmpty {
                VStack(spacing: 8) {
                    Spacer()
                    Image(systemName: "film.stack")
                        .font(.system(size: 36))
                        .foregroundStyle(.secondary)
                    Text("No recordings yet").foregroundStyle(.secondary)
                    Text("Files saved to \((library.folder.path as NSString).abbreviatingWithTildeInPath)")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                    Spacer()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List {
                    ForEach(library.files) { file in
                        RecordingRow(
                            file: file,
                            library: library,
                            renamingID: $renamingID,
                            renameText: $renameText,
                            exportingID: $exportingID,
                            exportTask: $exportTask,
                            activeTrimTarget: $activeTrimTarget,
                            errorMessage: $errorMessage
                        )
                    }
                }
                .listStyle(.inset)
            }
        }
        .frame(minWidth: 540, minHeight: 420)
        .sheet(item: $activeTrimTarget) { target in
            VideoTrimModalView(target: target, library: library, settings: settings)
        }
        .alert("Error", isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "")
        }
        .task { await library.reload() }
        .onDisappear {
            exportTask?.cancel()
            exportTask = nil
        }
    }

    private func openExternalVideoToTrim() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [UTType.mpeg4Movie, UTType.quickTimeMovie, UTType(filenameExtension: "m4v")].compactMap { $0 }
        panel.message = "Choose a video to trim losslessly without re-encoding"
        panel.prompt = "Select Video"
        if panel.runModal() == .OK, let url = panel.url {
            activeTrimTarget = RecordingViewModel.TrimTarget(url: url, isPostCaptureReview: false, originalFile: nil)
        }
    }
}

private struct RecordingRow: View {
    let file: RecordingFile
    @ObservedObject var library: RecordingsLibrary
    @Binding var renamingID: URL?
    @Binding var renameText: String
    @Binding var exportingID: URL?
    @Binding var exportTask: Task<Void, Never>?
    @Binding var activeTrimTarget: RecordingViewModel.TrimTarget?
    @Binding var errorMessage: String?

    private var isRenaming: Bool { renamingID == file.url }
    private var isExporting: Bool { exportingID == file.url }

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: file.url.pathExtension.lowercased() == "gif" ? "photo" : "film")
                .font(.system(size: 22))
                .foregroundStyle(.tint)
            VStack(alignment: .leading, spacing: 2) {
                if isRenaming {
                    HStack(spacing: 6) {
                        TextField("Name", text: $renameText)
                            .textFieldStyle(.roundedBorder)
                            .onSubmit { commitRename() }
                        Button("Save", action: commitRename)
                        Button("Cancel") { renamingID = nil }
                    }
                } else {
                    Text(file.name).font(.body).lineLimit(1)
                    HStack(spacing: 6) {
                        Text("\(file.createdAt.formatted(date: .abbreviated, time: .shortened))  ·  \(file.formattedSize)  ·  \(file.formattedDuration)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        if file.hasEvidenceSeal {
                            HStack(spacing: 2) {
                                Image(systemName: "checkmark.seal.fill")
                                    .foregroundStyle(.green)
                                    .font(.system(size: 10))
                                Text("Sealed")
                                    .font(.caption2.bold())
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
            Spacer()
            if isExporting {
                ProgressView().scaleEffect(0.6)
            }
            if file.hasEvidenceSeal {
                Button { copySHA256() } label: { Image(systemName: "checkmark.seal") }
                    .buttonStyle(.borderless)
                    .help("Copy SHA-256 Checksum")
            }
            Button { library.open(file) }            label: { Image(systemName: "play.circle") }.buttonStyle(.borderless).help("Open")
            Button { library.revealInFinder(file) }  label: { Image(systemName: "folder") }.buttonStyle(.borderless).help("Reveal in Finder")
            if LosslessTrimmer.isSupported(url: file.url) {
                Button {
                    activeTrimTarget = RecordingViewModel.TrimTarget(url: file.url, originalFile: file)
                } label: {
                    Image(systemName: "scissors")
                }
                .buttonStyle(.borderless)
                .help("Trim recording losslessly…")
            }
            Button(role: .destructive) {
                deleteFile()
            } label: { Image(systemName: "trash") }.buttonStyle(.borderless).help("Move to Trash")
        }
        .padding(.vertical, 4)
        .onDrag { NSItemProvider(contentsOf: file.url) ?? NSItemProvider() }
        .contextMenu {
            Button("Open") { library.open(file) }
            Button("Reveal in Finder") { library.revealInFinder(file) }
            if LosslessTrimmer.isSupported(url: file.url) {
                Button("Trim Recording…") {
                    activeTrimTarget = RecordingViewModel.TrimTarget(url: file.url, originalFile: file)
                }
            }
            if file.hasEvidenceSeal {
                Divider()
                Button("Copy SHA-256 Hash") { copySHA256() }
                Button("Reveal Evidence Manifest (.evidence.json)") { revealEvidenceSeal() }
            }
            Divider()
            Button("Rename…") { startRename() }
            if file.url.pathExtension.lowercased() != "gif" {
                Button("Export as GIF") { exportGIF() }
                    .disabled(exportingID != nil)
            }
            Divider()
            Button("Move to Trash", role: .destructive) { deleteFile() }
        }
    }

    private func copySHA256() {
        if let sha = library.sha256Hex(for: file) {
            let pb = NSPasteboard.general
            pb.clearContents()
            pb.setString(sha, forType: .string)
        }
    }

    private func revealEvidenceSeal() {
        if let targetURL = EvidenceSeal.existingManifestURL(for: file.url) {
            NSWorkspace.shared.activateFileViewerSelecting([targetURL])
        }
    }

    private func deleteFile() {
        if let err = library.delete(file) {
            errorMessage = "Delete failed: \(err.localizedDescription)"
        }
    }

    private func startRename() {
        renameText = file.url.deletingPathExtension().lastPathComponent
        renamingID = file.url
    }

    private func commitRename() {
        guard renamingID == file.url else { return }
        let target = file
        let newName = renameText
        renamingID = nil
        Task {
            do {
                try await library.rename(target, to: newName)
            } catch {
                errorMessage = "Rename failed: \(error.localizedDescription)"
            }
        }
    }

    private func exportGIF() {
        guard exportingID == nil else { return }
        exportingID = file.url
        exportTask = Task {
            defer {
                exportingID = nil
                exportTask = nil
            }
            do {
                _ = try await library.exportGIF(file)
            } catch is CancellationError {
                // Cancelled on view dismissal
            } catch {
                errorMessage = "GIF export failed: \(error.localizedDescription)"
            }
        }
    }
}
