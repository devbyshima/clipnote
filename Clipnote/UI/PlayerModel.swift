import AVFoundation
import AVKit
import Observation
import SwiftUI

/// Plays a note's original video and seeks to timestamps tapped in the note.
@MainActor @Observable
final class PlayerModel {
    private(set) var player: AVPlayer?
    private(set) var hasVideo = true
    private(set) var isUnavailable = false
    @ObservationIgnored private var accessedURL: URL?

    func load(_ note: Note) {
        guard player == nil else { return }
        guard let url = note.resolveSource() else {
            isUnavailable = true
            return
        }
        if url.startAccessingSecurityScopedResource() { accessedURL = url }
        guard FileManager.default.isReadableFile(atPath: url.path) else {
            isUnavailable = true
            release()
            return
        }
        isUnavailable = false
        let asset = AVURLAsset(url: url)
        player = AVPlayer(playerItem: AVPlayerItem(asset: asset))
        Task {
            let tracks = (try? await asset.loadTracks(withMediaType: .video)) ?? []
            hasVideo = !tracks.isEmpty
        }
    }

    func seek(to seconds: TimeInterval) {
        guard let player else { return }
        player.seek(to: CMTime(seconds: seconds, preferredTimescale: 600), toleranceBefore: .zero, toleranceAfter: .zero)
        player.play()
    }

    func reload(_ note: Note) {
        unload()
        load(note)
    }

    func unload() {
        player?.pause()
        player = nil
        release()
    }

    private func release() {
        accessedURL?.stopAccessingSecurityScopedResource()
        accessedURL = nil
    }
}

/// AppKit's player view. SwiftUI's `VideoPlayer` crashes on macOS 27 while
/// building its view (in `_AVKit_SwiftUI`), so the note uses this instead.
struct PlayerView: NSViewRepresentable {
    let player: AVPlayer

    func makeNSView(context: Context) -> AVPlayerView {
        let view = AVPlayerView()
        view.player = player
        view.controlsStyle = .inline
        view.videoGravity = .resizeAspect
        view.showsFullScreenToggleButton = true
        return view
    }

    func updateNSView(_ view: AVPlayerView, context: Context) {
        if view.player !== player { view.player = player }
    }

    static func dismantleNSView(_ view: AVPlayerView, coordinator: ()) {
        view.player = nil
    }
}
