import AppKit
import SwiftUI

enum PillPhase: Equatable {
    case hidden
    case recording
    case locked
    case transcribing
    case message(String)
}

@MainActor
final class PillModel: ObservableObject {
    @Published var phase: PillPhase = .hidden
    @Published var level: Float = 0
}

/// Floating, click-through, non-activating pill at the bottom of the active
/// screen; never steals focus from the app being typed into.
@MainActor
final class StatusPanel {
    private static let size = NSSize(width: 340, height: 56)

    let model = PillModel()
    private let panel: NSPanel
    private var hideWork: DispatchWorkItem?

    init() {
        panel = NSPanel(
            contentRect: NSRect(origin: .zero, size: Self.size),
            styleMask: [.nonactivatingPanel, .borderless],
            backing: .buffered,
            defer: true
        )
        panel.level = .screenSaver
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.ignoresMouseEvents = true
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        panel.contentView = NSHostingView(rootView: PillView(model: model))
    }

    func show(_ phase: PillPhase) {
        hideWork?.cancel()
        model.phase = phase
        if phase == .hidden {
            panel.orderOut(nil)
            return
        }
        position()
        panel.orderFrontRegardless()
    }

    func flash(_ message: String, seconds: TimeInterval = 2.5) {
        show(.message(message))
        let work = DispatchWorkItem { [weak self] in self?.show(.hidden) }
        hideWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds, execute: work)
    }

    private func position() {
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) } ?? NSScreen.main
        guard let frame = screen?.visibleFrame else { return }
        let origin = NSPoint(x: frame.midX - Self.size.width / 2, y: frame.minY + 20)
        panel.setFrame(NSRect(origin: origin, size: Self.size), display: true)
    }
}

private struct PillView: View {
    @ObservedObject var model: PillModel

    var body: some View {
        ZStack {
            if model.phase != .hidden {
                content
                    .padding(.horizontal, 14)
                    .frame(height: 34)
                    .background(Capsule().fill(Color.black.opacity(0.85)))
                    .overlay(Capsule().stroke(Color.white.opacity(0.15), lineWidth: 1))
                    .transition(.opacity.combined(with: .scale(scale: 0.9)))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .animation(.easeOut(duration: 0.15), value: model.phase)
    }

    @ViewBuilder private var content: some View {
        switch model.phase {
        case .hidden:
            EmptyView()
        case .recording, .locked:
            HStack(spacing: 8) {
                if model.phase == .locked {
                    Image(systemName: "lock.fill").font(.system(size: 10)).foregroundStyle(.white.opacity(0.8))
                }
                LevelBars(level: model.level)
            }
        case .transcribing:
            HStack(spacing: 8) {
                ProgressView().controlSize(.small).tint(.white)
                Text("Transcribing").font(.system(size: 12, weight: .medium)).foregroundStyle(.white.opacity(0.85))
            }
        case .message(let text):
            Text(text).font(.system(size: 12, weight: .medium)).foregroundStyle(.white).lineLimit(1)
        }
    }
}

private struct LevelBars: View {
    let level: Float
    private static let shape: [CGFloat] = [0.35, 0.6, 0.85, 1.0, 0.75, 1.0, 0.85, 0.6, 0.35]

    var body: some View {
        HStack(spacing: 3) {
            ForEach(Self.shape.indices, id: \.self) { index in
                Capsule()
                    .fill(Color.white)
                    .frame(width: 3, height: 4 + 16 * Self.shape[index] * CGFloat(level))
            }
        }
        .frame(height: 20)
        .animation(.easeOut(duration: 0.08), value: level)
    }
}
