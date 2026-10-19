import AppKit
import SwiftUI

/// Modal staging editor for positioning and resizing the presenter camera and backdrop plate.
/// Provides an interactive display canvas matching the target screen's aspect ratio, with 8-handle
/// expand/contract resize grips, grouping controls, and real-time live synchronization.
public struct PresenterLayoutModalView: View {
    @ObservedObject var vm: RecordingViewModel
    @ObservedObject private var webcam: WebcamOverlayController
    @ObservedObject private var backdropOverlay: PresenterBackdropOverlay
    @Environment(\.dismiss) private var dismiss

    @State private var hoveredHandle: ResizeHandle? = nil
    @GestureState private var activeDraggingHandle: ResizeHandle? = nil
    @GestureState private var isBackdropBodyDragging: Bool = false
    @GestureState private var isPiPCameraDragging: Bool = false
    @State private var initialDragRect: CGRect = .zero
    @State private var dragStartPiPNormalized: CGPoint? = nil
    @State private var dragStartBackdropScreenRect: CGRect? = nil

    public init(vm: RecordingViewModel) {
        self.vm = vm
        self._webcam = ObservedObject(wrappedValue: vm.webcam)
        self._backdropOverlay = ObservedObject(wrappedValue: vm.webcam.backdropOverlay)
    }

    public var body: some View {
        VStack(spacing: 0) {
            headerBar
            Divider()

            HSplitView {
                canvasArea
                    .frame(minWidth: 460, minHeight: 380)

                controlsSidebar
                    .frame(width: 280)
            }

            Divider()
            footerBar
        }
        .frame(minWidth: 780, minHeight: 560)
        .background(Color(NSColor.windowBackgroundColor))
        .allowAppTerminationWhenModal()
        .onAppear {
            let pipScreen = currentPiPScreenRect
            let targetScreen = (vm.selectedDisplayID.flatMap { id in
                NSScreen.screens.first(where: {
                    guard let num = $0.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else { return false }
                    return CGDirectDisplayID(num.uint32Value) == id
                })
            } ?? NSScreen.main ?? NSScreen.screens.first)
            backdropOverlay.updatePiPFrame(pipScreen, on: targetScreen)
        }
        .onChange(of: activeDraggingHandle) { handle in
            if handle == nil {
                initialDragRect = .zero
            }
        }
        .onChange(of: isBackdropBodyDragging) { active in
            if !active {
                dragStartBackdropScreenRect = nil
            }
        }
        .onChange(of: isPiPCameraDragging) { active in
            if !active {
                dragStartPiPNormalized = nil
            }
        }
        .onDisappear {
            initialDragRect = .zero
            dragStartBackdropScreenRect = nil
            dragStartPiPNormalized = nil
        }
    }

    // MARK: - Header & Footer

    private var headerBar: some View {
        HStack {
            Image(systemName: "rectangle.inset.filled.and.person.filled")
                .font(.title2)
                .foregroundStyle(Color.accentColor)
            VStack(alignment: .leading, spacing: 2) {
                Text("Presenter Layout & Staging")
                    .font(.headline)
                Text("Position camera and resize backdrop plate with grips. Live preview updates immediately.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button("Done") {
                vm.showPresenterLayoutModal = false
            }
            .keyboardShortcut(.defaultAction)
            .controlSize(.regular)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    private var footerBar: some View {
        HStack {
            Text("Tip: Drag the camera to move it. Drag the white handles to resize the backdrop plate.")
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
            Button("Reset Layout") {
                resetLayout()
            }
            .controlSize(.small)
            Button("Done") {
                vm.showPresenterLayoutModal = false
            }
            .keyboardShortcut(.return, modifiers: [])
            .controlSize(.small)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    // MARK: - Display Canvas

    private var canvasArea: some View {
        GeometryReader { geo in
            let screenSize = targetScreenVisibleFrame.size
            let (canvasSize, scale) = computeCanvasSize(in: geo.size)
            let canvasW = canvasSize.width
            let canvasH = canvasSize.height

            VStack(spacing: 8) {
                HStack {
                    Label(targetScreenDisplayName, systemImage: "display")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text("\(Int(screenSize.width)) × \(Int(screenSize.height)) pt")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.tertiary)
                }
                .frame(width: canvasW)

                ZStack(alignment: .topLeading) {
                    // Monitor Bezel & Screen Background
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color(nsColor: .underPageBackgroundColor).opacity(0.85))
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(Color.secondary.opacity(0.2), lineWidth: 1.5)
                        )

                    // Subtle grid lines for alignment
                    CanvasGridPattern()
                        .clipShape(RoundedRectangle(cornerRadius: 8))

                    // Backdrop Plate Element (Behind PiP)
                    if vm.backdropEnabled {
                        backdropPlateBox(canvasSize: CGSize(width: canvasW, height: canvasH), scale: scale)
                    }

                    // PiP Camera Element (In front)
                    pipCameraBox(canvasSize: CGSize(width: canvasW, height: canvasH), scale: scale)
                }
                .frame(width: canvasW, height: canvasH)
                .coordinateSpace(name: "displayCanvas")
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .shadow(color: .black.opacity(0.15), radius: 6, x: 0, y: 3)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .padding(16)
    }

    // MARK: - Canvas Elements

    @ViewBuilder
    private func backdropPlateBox(canvasSize: CGSize, scale: CGFloat) -> some View {
        let frame = backdropCanvasFrame(canvasSize: canvasSize, scale: scale)

        ZStack(alignment: .topLeading) {
            // Backdrop Image or Placeholder
            Group {
                if let img = backdropOverlay.cachedImage ?? (vm.backdropImageURL.flatMap { NSImage(contentsOf: $0) }) {
                    Image(nsImage: img)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                } else {
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Color.accentColor.opacity(0.12))
                        .overlay(
                            RoundedRectangle(cornerRadius: 6)
                                .strokeBorder(Color.accentColor.opacity(0.4), style: StrokeStyle(lineWidth: 1.5, dash: [4, 4]))
                        )
                        .overlay(
                            Text("Backdrop Plate")
                                .font(.caption2.weight(.medium))
                                .foregroundStyle(Color.accentColor)
                        )
                }
            }
            .frame(width: frame.width, height: frame.height)
            .clipped()
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(Color.accentColor.opacity(0.8), lineWidth: 1.5)
            )
            .contentShape(Rectangle())
            .gesture(
                DragGesture(coordinateSpace: .named("displayCanvas"))
                    .updating($isBackdropBodyDragging) { _, state, _ in
                        state = true
                    }
                    .onChanged { val in
                        guard activeDraggingHandle == nil else { return }
                        if dragStartBackdropScreenRect == nil {
                            dragStartBackdropScreenRect = currentBackdropScreenRect
                        }
                        handleBackdropBodyDrag(translation: val.translation, scale: scale)
                    }
                    .onEnded { _ in
                        dragStartBackdropScreenRect = nil
                    }
            )

            // 8 Resize Grips
            ForEach(ResizeHandle.allCases) { handle in
                resizeHandleView(handle: handle, boxFrame: frame, scale: scale)
            }
        }
        .offset(x: frame.minX, y: frame.minY)
    }

    @ViewBuilder
    private func resizeHandleView(handle: ResizeHandle, boxFrame: CGRect, scale: CGFloat) -> some View {
        let pos = handle.position(in: CGRect(origin: .zero, size: boxFrame.size))
        let handleSize: CGFloat = 10
        let hitSize: CGFloat = 20

        Circle()
            .fill(Color.white)
            .frame(width: handleSize, height: handleSize)
            .overlay(Circle().stroke(Color.accentColor, lineWidth: 2))
            .shadow(color: .black.opacity(0.3), radius: 2, x: 0, y: 1)
            .frame(width: hitSize, height: hitSize)
            .contentShape(Rectangle())
            .offset(x: pos.x - hitSize / 2, y: pos.y - hitSize / 2)
            .highPriorityGesture(
                DragGesture(coordinateSpace: .named("displayCanvas"))
                    .updating($activeDraggingHandle) { _, state, _ in
                        state = handle
                    }
                    .onChanged { val in
                        if initialDragRect == .zero {
                            initialDragRect = currentBackdropScreenRect
                        }
                        handleResizeDrag(handle: handle, translation: val.translation, scale: scale)
                    }
                    .onEnded { _ in
                        initialDragRect = .zero
                    }
            )
    }

    @ViewBuilder
    private func pipCameraBox(canvasSize: CGSize, scale: CGFloat) -> some View {
        let pipDim = webcam.currentDimensions
        let canvasW = max(24, pipDim.width * scale)
        let canvasH = max(24, pipDim.height * scale)
        let frame = pipCanvasFrame(canvasSize: canvasSize, scale: scale)

        ZStack {
            // Camera Fill Shape
            Path(webcam.shape.path(in: CGRect(origin: .zero, size: CGSize(width: canvasW, height: canvasH)), flipped: true))
                .fill(Color(nsColor: .controlAccentColor).opacity(0.35))

            // Border Stroke
            if vm.webcamShowBorder && vm.webcamBorderWidth > 0 {
                let borderScale = max(0.5, CGFloat(vm.webcamBorderWidth) * scale)
                Path(webcam.shape.path(in: CGRect(origin: .zero, size: CGSize(width: canvasW, height: canvasH)).insetBy(dx: borderScale / 2, dy: borderScale / 2), flipped: true))
                    .stroke(Color(nsColor: NSColor(cgColor: vm.webcamBorderColor) ?? .white), lineWidth: borderScale)
            }

            // Camera Label & Icon
            VStack(spacing: 2) {
                Image(systemName: "video.fill")
                    .font(.system(size: max(10, 16 * scale)))
                    .foregroundStyle(.white)
                if canvasW > 60 {
                    Text("Presenter")
                        .font(.system(size: max(8, 10 * scale)).weight(.bold))
                        .foregroundStyle(.white)
                }
            }
        }
        .frame(width: canvasW, height: canvasH)
        .contentShape(Rectangle())
        .shadow(color: .black.opacity(0.25), radius: 4, x: 0, y: 2)
        .offset(x: frame.minX, y: frame.minY)
        .gesture(
            DragGesture(coordinateSpace: .named("displayCanvas"))
                .updating($isPiPCameraDragging) { _, state, _ in
                    state = true
                }
                .onChanged { val in
                    guard activeDraggingHandle == nil && !isBackdropBodyDragging else { return }
                    if dragStartPiPNormalized == nil {
                        dragStartPiPNormalized = webcam.pipNormalizedPosition
                    }
                    handlePiPDrag(translation: val.translation, scale: scale)
                }
                .onEnded { _ in
                    dragStartPiPNormalized = nil
                }
        )
    }

    // MARK: - Sidebar Controls

    private var controlsSidebar: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                // Grouping Section
                VStack(alignment: .leading, spacing: 8) {
                    Text("Grouping")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.secondary)

                    Toggle(isOn: Binding(
                        get: { vm.backdropIsGrouped },
                        set: { newIsGrouped in
                            guard vm.backdropIsGrouped != newIsGrouped else { return }
                            let vFrame = targetScreenVisibleFrame
                            let pipScreen = currentPiPScreenRect
                            let targetScreen = (vm.selectedDisplayID.flatMap { id in
                                NSScreen.screens.first(where: {
                                    guard let num = $0.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else { return false }
                                    return CGDirectDisplayID(num.uint32Value) == id
                                })
                            } ?? NSScreen.main ?? NSScreen.screens.first)

                            backdropOverlay.updatePiPFrame(pipScreen, on: targetScreen)

                            if newIsGrouped {
                                let currentBackdrop = PresenterBackdropGeometry.freeformScreenRect(
                                    visibleFrame: vFrame,
                                    freeformNormalizedRect: backdropOverlay.freeformNormalizedRect
                                )
                                backdropOverlay.relativeRect = PresenterBackdropGeometry.computeRelativeRect(
                                    backdropScreenRect: currentBackdrop,
                                    pipScreenRect: pipScreen
                                )
                            } else {
                                let currentBackdrop = PresenterBackdropGeometry.groupedScreenRect(
                                    pipScreenRect: pipScreen,
                                    relativeRect: backdropOverlay.relativeRect
                                )
                                backdropOverlay.freeformNormalizedRect = PresenterBackdropGeometry.computeFreeformNormalizedRect(
                                    backdropScreenRect: currentBackdrop,
                                    visibleFrame: vFrame
                                )
                            }
                            vm.backdropIsGrouped = newIsGrouped
                        }
                    )) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(vm.backdropIsGrouped ? "Grouped with Camera" : "Ungrouped (Independent)")
                                .font(.subheadline.weight(.medium))
                            Text(vm.backdropIsGrouped
                                 ? "Moving the camera moves the backdrop plate along with it."
                                 : "Backdrop plate stays fixed when camera is moved.")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .toggleStyle(.checkbox)
                }

                Divider()

                // Backdrop Plate Configuration
                VStack(alignment: .leading, spacing: 8) {
                    Text("Backdrop Plate")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.secondary)

                    Toggle("Enable backdrop plate", isOn: $vm.backdropEnabled)
                        .font(.subheadline)

                    if vm.backdropEnabled {
                        if let url = vm.backdropImageURL {
                            HStack {
                                Text(url.lastPathComponent)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                                Spacer()
                                Button("Change…") { vm.pickBackdropImage() }
                                    .controlSize(.small)
                                Button("Clear") { vm.clearBackdropImage() }
                                    .controlSize(.small)
                            }
                        } else {
                            Button("Choose Backdrop Image…") {
                                vm.pickBackdropImage()
                            }
                            .controlSize(.small)
                        }

                        // Dimension readouts
                        let curRect = currentBackdropScreenRect
                        HStack {
                            Text("Size:")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Text("\(Int(curRect.width)) × \(Int(curRect.height)) pt")
                                .font(.caption.monospacedDigit())
                        }
                    }
                }

                Divider()

                // Quick Snap Positions
                VStack(alignment: .leading, spacing: 8) {
                    Text("Snap Positioning")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.secondary)

                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 6) {
                        ForEach(PresenterSnapPosition.allCases) { pos in
                            Button(pos.rawValue) {
                                webcam.snapTo(position: pos)
                            }
                            .controlSize(.small)
                            .frame(maxWidth: .infinity)
                        }
                    }
                }

                Divider()

                // Quick PiP Size & Shape
                VStack(alignment: .leading, spacing: 8) {
                    Text("Camera Appearance")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.secondary)

                    Picker("Size", selection: $vm.webcamSize) {
                        ForEach(WebcamSize.allCases) { s in
                            Text(s.displayName).tag(s)
                        }
                    }

                    Picker("Shape", selection: $vm.webcamShape) {
                        ForEach(WebcamShape.allCases) { shape in
                            Label(shape.displayName, systemImage: shape.systemImage).tag(shape)
                        }
                    }
                }
            }
            .padding(16)
        }
    }

    // MARK: - Geometry & Math Helpers

    private var targetScreenVisibleFrame: NSRect {
        let screen = (vm.selectedDisplayID.flatMap { id in
            NSScreen.screens.first(where: {
                guard let num = $0.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else { return false }
                return CGDirectDisplayID(num.uint32Value) == id
            })
        } ?? NSScreen.main ?? NSScreen.screens.first)

        return screen?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1920, height: 1080)
    }

    private var targetScreenDisplayName: String {
        vm.displays.first(where: { $0.id == vm.selectedDisplayID })?.displayName ?? "Display"
    }

    private var currentBackdropScreenRect: CGRect {
        let vFrame = targetScreenVisibleFrame
        let pipScreen = currentPiPScreenRect

        if vm.backdropIsGrouped {
            return PresenterBackdropGeometry.groupedScreenRect(
                pipScreenRect: pipScreen,
                relativeRect: backdropOverlay.relativeRect
            )
        } else {
            return PresenterBackdropGeometry.freeformScreenRect(
                visibleFrame: vFrame,
                freeformNormalizedRect: backdropOverlay.freeformNormalizedRect
            )
        }
    }

    private var currentPiPScreenRect: CGRect {
        let vFrame = targetScreenVisibleFrame
        let target = webcam.currentDimensions
        let margin: CGFloat = 24
        let minX = vFrame.minX + margin
        let maxX = max(minX, vFrame.maxX - target.width - margin)
        let minY = vFrame.minY + margin
        let maxY = max(minY, vFrame.maxY - target.height - margin)

        let posX = minX + max(0, min(1, webcam.pipNormalizedPosition.x)) * (maxX - minX)
        let posY = minY + max(0, min(1, webcam.pipNormalizedPosition.y)) * (maxY - minY)
        return CGRect(x: posX, y: posY, width: target.width, height: target.height)
    }

    private func pipCanvasFrame(canvasSize: CGSize, scale: CGFloat) -> CGRect {
        let pipScreen = currentPiPScreenRect
        let vFrame = targetScreenVisibleFrame
        let relX = pipScreen.minX - vFrame.minX
        let relY = pipScreen.minY - vFrame.minY

        let canvasX = relX * scale
        let canvasY = canvasSize.height - (relY + pipScreen.height) * scale
        return CGRect(x: canvasX, y: canvasY, width: pipScreen.width * scale, height: pipScreen.height * scale)
    }

    private func backdropCanvasFrame(canvasSize: CGSize, scale: CGFloat) -> CGRect {
        let bdScreen = currentBackdropScreenRect
        let vFrame = targetScreenVisibleFrame
        let relX = bdScreen.minX - vFrame.minX
        let relY = bdScreen.minY - vFrame.minY

        let canvasX = relX * scale
        let canvasY = canvasSize.height - (relY + bdScreen.height) * scale
        return CGRect(x: canvasX, y: canvasY, width: bdScreen.width * scale, height: bdScreen.height * scale)
    }

    // MARK: - Drag & Resize Handling

    private func handlePiPDrag(translation: CGSize, scale: CGFloat) {
        guard let startNorm = dragStartPiPNormalized else { return }

        let vFrame = targetScreenVisibleFrame
        let target = webcam.currentDimensions
        let margin: CGFloat = 24
        let minX = vFrame.minX + margin
        let maxX = max(minX, vFrame.maxX - target.width - margin)
        let minY = vFrame.minY + margin
        let maxY = max(minY, vFrame.maxY - target.height - margin)

        guard maxX > minX, maxY > minY else { return }

        let startScreenX = minX + max(0, min(1, startNorm.x)) * (maxX - minX)
        let startScreenY = minY + max(0, min(1, startNorm.y)) * (maxY - minY)

        let deltaScreenX = translation.width / scale
        let deltaScreenY = -translation.height / scale

        let newX = max(minX, min(maxX, startScreenX + deltaScreenX))
        let newY = max(minY, min(maxY, startScreenY + deltaScreenY))

        let normX = (newX - minX) / (maxX - minX)
        let normY = (newY - minY) / (maxY - minY)

        webcam.pipNormalizedPosition = CGPoint(x: normX, y: normY)
        webcam.reposition()
    }

    private func handleBackdropBodyDrag(translation: CGSize, scale: CGFloat) {
        guard activeDraggingHandle == nil else { return }
        guard let startScreenRect = dragStartBackdropScreenRect else { return }
        let vFrame = targetScreenVisibleFrame
        let targetRect = PresenterBackdropGeometry.computeBodyDragRect(
            initialScreenRect: startScreenRect,
            canvasTranslation: translation,
            scale: scale,
            visibleFrame: vFrame
        )
        applyBackdropScreenRect(targetRect, visibleFrame: vFrame)
    }

    private func handleResizeDrag(handle: ResizeHandle, translation: CGSize, scale: CGFloat) {
        let vFrame = targetScreenVisibleFrame
        let targetRect = PresenterBackdropGeometry.computeResizedRect(
            handle: handle,
            initialScreenRect: initialDragRect,
            canvasTranslation: translation,
            scale: scale,
            visibleFrame: vFrame
        )
        applyBackdropScreenRect(targetRect, visibleFrame: vFrame)
    }

    private func applyBackdropScreenRect(_ targetRect: CGRect, visibleFrame: CGRect) {
        if vm.backdropIsGrouped {
            let pipScreen = currentPiPScreenRect
            let relX = targetRect.origin.x - pipScreen.minX
            let relY = targetRect.origin.y - pipScreen.minY
            backdropOverlay.relativeRect = CGRect(x: relX, y: relY, width: targetRect.width, height: targetRect.height)
        } else {
            let normX = (targetRect.origin.x - visibleFrame.minX) / visibleFrame.width
            let normY = (targetRect.origin.y - visibleFrame.minY) / visibleFrame.height
            let normW = targetRect.width / visibleFrame.width
            let normH = targetRect.height / visibleFrame.height
            backdropOverlay.freeformNormalizedRect = CGRect(x: normX, y: normY, width: normW, height: normH)
        }
        backdropOverlay.updateFrame()
    }

    private func computeCanvasSize(in geoSize: CGSize) -> (CGSize, CGFloat) {
        let screenSize = targetScreenVisibleFrame.size
        let screenAspect = max(1.0, screenSize.width / max(1.0, screenSize.height))
        let maxW = max(100, geoSize.width - 40)
        let maxH = max(100, geoSize.height - 40)

        let canvasW: CGFloat
        let canvasH: CGFloat
        if maxW / maxH > screenAspect {
            canvasH = max(200, maxH)
            canvasW = canvasH * screenAspect
        } else {
            canvasW = max(300, maxW)
            canvasH = canvasW / screenAspect
        }
        let scale = canvasW / max(1.0, screenSize.width)
        return (CGSize(width: canvasW, height: canvasH), scale)
    }

    private func resetLayout() {
        webcam.snapTo(position: .bottomRight)
        vm.backdropIsGrouped = true
        backdropOverlay.isGrouped = true
        backdropOverlay.relativeRect = CGRect(x: -30, y: -20, width: 260, height: 240)
        backdropOverlay.freeformNormalizedRect = CGRect(x: 0.75, y: 0.05, width: 0.22, height: 0.22)
        webcam.reposition()
        backdropOverlay.updateFrame()
    }
}

// MARK: - Canvas Alignment Grid

private struct CanvasGridPattern: View {
    var body: some View {
        GeometryReader { geo in
            Path { path in
                let step: CGFloat = 30
                for x in stride(from: step, to: geo.size.width, by: step) {
                    path.move(to: CGPoint(x: x, y: 0))
                    path.addLine(to: CGPoint(x: x, y: geo.size.height))
                }
                for y in stride(from: step, to: geo.size.height, by: step) {
                    path.move(to: CGPoint(x: 0, y: y))
                    path.addLine(to: CGPoint(x: geo.size.width, y: y))
                }
            }
            .stroke(Color.primary.opacity(0.04), lineWidth: 0.5)
        }
    }
}
