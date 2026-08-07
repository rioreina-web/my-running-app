//
//  MemoPlayerRow.swift
//  RunningLog
//
//  The voice memo, as a single row you can play.
//
//  Replaces the wall of transcript text at the top of the journal entry
//  detail sheet. The memo IS a recording, so the primary affordance is
//  playback; the words move behind a "READ THE WORDS ↓" disclosure
//  (see `HistoryDetailSheet+Editorial.swift`).
//
//  Two deliberate engineering choices, both load-bearing:
//
//  1. LAZY DOWNLOAD. Audio is fetched on the first tap, not on appear.
//     `HistoryDetailPager` instantiates one `HistoryDetailSheet` per page,
//     so an eager download would pull several hundred KB per adjacent
//     journal entry the athlete never opens. The cost is that duration is
//     unknown until first play — hence the "TAP TO PLAY" idle label rather
//     than a fake "0:00".
//
//  2. THE WAVEFORM IS DECORATIVE, NOT SAMPLED. Bar heights come from a
//     stable hash of the audio URL, so a given memo always draws the same
//     shape, but the shape does not represent amplitude. Real sampling
//     means decoding the whole file to PCM — far too expensive for a row
//     in a scrolling sheet. Progress colouring and drag-to-seek ARE real.
//     If we ever want true amplitude, compute it server-side at ingest and
//     store a small peaks array on `training_logs`.
//

import AVFoundation
import os
import Supabase
import SwiftUI

// ─────────────────────────────────────────────────────────────────────────
// MARK: - Shared training-memos storage access
//
// Voice memo audio and transcripts both live in the PRIVATE `training-memos`
// bucket, but the URL stored on the row is a public-object path that a
// private bucket rejects (400 "Bucket not found") — a naked GET can never
// read it. Everything must go through the authenticated storage client,
// which carries the athlete's session.
//
// Extracted from `VoiceTranscriptText`, which had this logic inline and
// now calls in here, so audio and transcript can't drift apart.
// ─────────────────────────────────────────────────────────────────────────

enum TrainingMemoStorage {
    static let bucket = "training-memos"

    /// Bucket-relative object path from a stored `training-memos` URL (public
    /// or signed), e.g. ".../training-memos/<uid>/<file>.m4a" →
    /// "<uid>/<file>.m4a". Strips any signed-URL query token so
    /// `download(path:)` gets the bare path.
    static func objectPath(from urlString: String) -> String? {
        guard let range = urlString.range(of: "/\(bucket)/") else { return nil }
        var path = String(urlString[range.upperBound...])
        if let q = path.firstIndex(of: "?") { path = String(path[..<q]) }
        return path.removingPercentEncoding ?? path
    }

    /// Fetch a stored memo asset. Tries the authenticated storage client first
    /// (the correct path for the private bucket), then falls back to a direct
    /// URL fetch so genuinely public legacy URLs keep working.
    static func data(for urlString: String) async throws -> Data {
        if let path = objectPath(from: urlString) {
            do {
                return try await supabase.storage.from(bucket).download(path: path)
            } catch {
                // fall through to a direct fetch (legacy public URLs)
            }
        }
        guard let u = URL(string: urlString) else { throw MemoStorageError.badURL }
        let (data, response) = try await URLSession.shared.data(from: u)
        if let http = response as? HTTPURLResponse, !(200 ... 299).contains(http.statusCode) {
            throw MemoStorageError.http(http.statusCode)
        }
        return data
    }

    enum MemoStorageError: Error {
        case badURL
        case http(Int)
    }
}

// ─────────────────────────────────────────────────────────────────────────
// MARK: - MemoPlayerRow
// ─────────────────────────────────────────────────────────────────────────

/// One-row memo player: coral play/pause, waveform scrubber, elapsed/total.
/// Renders as a hairline capsule — no card, no shadow (editorial = flat).
struct MemoPlayerRow: View {
    let url: String

    @State private var player: AVAudioPlayer?
    @State private var isPlaying = false
    @State private var isLoading = false
    @State private var failed = false
    /// 0…1 playback position. Driven by the progress ticker while playing and
    /// by the drag gesture while seeking.
    @State private var progress: Double = 0
    @State private var duration: TimeInterval = 0
    /// True while a drag is in flight, so the 50ms ticker doesn't overwrite the
    /// position the finger is setting (which made the playhead snap back).
    ///
    /// `@GestureState`, not `@State`: SwiftUI resets it automatically when the
    /// gesture is CANCELLED, which a plain flag cleared in `onEnded` does not
    /// cover. With `minimumDistance: 0` inside the sheet's ScrollView, a
    /// touch-down followed by a vertical scroll hands the touch to the
    /// ScrollView and `onEnded` never fires — leaving a `@State` flag stuck
    /// true and the waveform frozen for the life of the row.
    @GestureState private var isSeeking = false
    /// Whether THIS row activated the shared audio session. Without this,
    /// `onDisappear` on a row that never played would still call
    /// `setActive(false)` — and since `HistoryDetailPager` keeps several sheets
    /// alive, paging away could deactivate the session out from under a row
    /// that IS playing, or under an in-flight recording elsewhere in the app.
    @State private var didActivateSession = false

    private let barCount = 28

    /// The URL's FNV-1a hash, computed once per row rather than once per bar
    /// per frame. `barHeight` used to walk `url.utf8` on every call — 28 calls
    /// per render, re-rendered every 50ms during playback.
    private let urlHash: UInt64

    init(url: String) {
        self.url = url
        var hash: UInt64 = 0xcbf2_9ce4_8422_2325
        for byte in url.utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 0x100_0000_01b3
        }
        self.urlHash = hash
    }

    var body: some View {
        HStack(spacing: 11) {
            playButton

            waveform
                .frame(height: 19)
                .frame(maxWidth: .infinity)

            Text(timeLabel)
                .font(.dripEyebrow(10))
                .foregroundStyle(Color.drip.textTertiary)
                .monospacedDigit()
        }
        .padding(.leading, 11)
        .padding(.trailing, 13)
        .padding(.vertical, 8)
        .background(Color.drip.cardBackground)
        .clipShape(Capsule())
        // strokeBorder, not stroke: a centred stroke on a clipped shape loses
        // its outer half-pixel to the clip.
        .overlay(Capsule().strokeBorder(Color.drip.divider, lineWidth: 1))
        // Progress ticker. Scoped to `isPlaying` so nothing runs while paused,
        // and torn down automatically when the row leaves the hierarchy.
        .task(id: isPlaying) {
            guard isPlaying else { return }
            while !Task.isCancelled, let p = player {
                if p.isPlaying {
                    // Don't fight an in-progress drag.
                    if p.duration > 0, !isSeeking { progress = p.currentTime / p.duration }
                    try? await Task.sleep(for: .milliseconds(50))
                } else {
                    // Stopped playing. Distinguish "finished" from "interrupted"
                    // (incoming call, another app taking audio): a finished memo
                    // rewinds so the next tap replays it, an interrupted one
                    // holds its place so the next tap resumes.
                    isPlaying = false
                    if p.currentTime >= p.duration - 0.05 {
                        progress = 0
                        p.currentTime = 0
                    }
                    deactivateSession()
                    return
                }
            }
        }
        // Reset if this view is recycled for a DIFFERENT memo — the pager and the
        // post-save refetch can both swap `currentEntry` under a structurally
        // identical row, which would otherwise keep playing the previous audio.
        //
        // `onChange`, not `.task(id:)`: `.task` also fires on every re-appearance,
        // and the pager sends sheets through disappear/appear as pages scroll by.
        // That would throw away an already-downloaded memo and re-fetch several
        // hundred KB — the exact cost the lazy-download design exists to avoid.
        .onChange(of: url) { _, _ in
            stop()
            player = nil
            duration = 0
            progress = 0
            failed = false
        }
        .onDisappear { stop() }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Voice memo")
        .accessibilityValue(accessibilityValue)
        .accessibilityAddTraits(.isButton)
        .accessibilityHint(isPlaying ? "Double tap to pause" : "Double tap to play")
        // The play button itself is accessibilityHidden so the row reads as one
        // element — which means the row has to carry the action, or VoiceOver
        // users get a button that announces itself and then does nothing.
        .accessibilityAction { Task { await toggle() } }
    }

    // MARK: Play / pause

    private var playButton: some View {
        Button {
            Task { await toggle() }
        } label: {
            ZStack {
                Circle()
                    .fill(failed ? Color.drip.textTertiary : Color.drip.coral)
                    .frame(width: 26, height: 26)

                if isLoading {
                    ProgressView()
                        .tint(.white)
                        .scaleEffect(0.55)
                } else {
                    Image(systemName: failed ? "exclamationmark" : (isPlaying ? "pause.fill" : "play.fill"))
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(.white)
                        // play.fill reads left-heavy inside a circle; nudge it.
                        .offset(x: isPlaying || failed ? 0 : 1)
                }
            }
        }
        .buttonStyle(.plain)
        .disabled(isLoading)
        .accessibilityHidden(true)
    }

    // MARK: Waveform / scrubber

    private var waveform: some View {
        GeometryReader { geo in
            let spacing: CGFloat = 2
            let totalSpacing = spacing * CGFloat(barCount - 1)
            let barWidth = max(1, (geo.size.width - totalSpacing) / CGFloat(barCount))

            HStack(alignment: .center, spacing: spacing) {
                ForEach(0 ..< barCount, id: \.self) { i in
                    let played = Double(i) / Double(barCount) < progress
                    Capsule()
                        .fill(played ? Color.drip.coral : Color.drip.paperDeep)
                        .frame(width: barWidth, height: barHeight(i))
                }
            }
            .frame(height: geo.size.height, alignment: .center)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .updating($isSeeking) { _, state, _ in state = true }
                    .onChanged { value in
                        guard duration > 0, geo.size.width > 0 else { return }
                        progress = min(max(value.location.x / geo.size.width, 0), 1)
                    }
                    .onEnded { _ in
                        guard let p = player, duration > 0 else { return }
                        p.currentTime = progress * duration
                    }
            )
        }
    }

    /// Stable per-memo bar height, mixing the precomputed `urlHash` with the bar
    /// index. `String.hashValue` is seeded per process and would redraw a
    /// different shape on every launch — a fixed hash gives the same memo the
    /// same waveform forever.
    ///
    /// The mixer is a splitmix64 finaliser, NOT another FNV round. FNV's prime
    /// is 2^40 + 0x1b3, so XOR-ing a small index only perturbs the low bits and
    /// the product lands in bits 0–14 and 40–46 — bits 32–39 are effectively
    /// index-invariant. Extracting a byte from there gave all 28 bars the SAME
    /// height (measured: 1 distinct value out of 28, a flat block). splitmix64
    /// avalanches properly: 26/28 distinct heights spanning ~14 of the 15pt
    /// range, which is what makes it read as a waveform.
    private func barHeight(_ index: Int) -> CGFloat {
        var x = urlHash ^ (0x9E37_79B9_7F4A_7C15 &* UInt64(index &+ 1))
        x = (x ^ (x >> 30)) &* 0xBF58_476D_1CE4_E5B9
        x = (x ^ (x >> 27)) &* 0x94D0_49BB_1331_11EB
        x ^= x >> 31
        // 4…19pt — never zero-height (an empty slot reads as a rendering bug).
        return 4 + CGFloat((x >> 24) & 0xFF) / 255.0 * 15
    }

    // MARK: Labels

    private var timeLabel: String {
        if failed { return "—:—" }
        if isLoading { return "···" }
        guard duration > 0 else { return "TAP TO PLAY" }
        let shown = isPlaying || progress > 0 ? duration * progress : duration
        return Self.mmss(shown)
    }

    private var accessibilityValue: String {
        if failed { return "Couldn't load audio" }
        guard duration > 0 else { return "Not loaded" }
        return "\(Self.mmss(duration * progress)) of \(Self.mmss(duration))"
    }

    private static func mmss(_ t: TimeInterval) -> String {
        guard t.isFinite, t >= 0 else { return "0:00" }
        let total = Int(t.rounded())
        return String(format: "%d:%02d", total / 60, total % 60)
    }

    // MARK: Transport

    private func toggle() async {
        // A failed load is retryable — tapping again clears the error and
        // re-fetches rather than dead-ending the row.
        if failed { failed = false }
        if player == nil {
            await load()
        }
        guard let p = player else { return }
        if p.isPlaying {
            p.pause()
            isPlaying = false
            deactivateSession()
        } else {
            // Rewind if we're parked at the end — either from a drag to the far
            // right, or because the row disappeared at the instant playback
            // finished and the ticker never got to reset it. Ask the PLAYER, not
            // `progress`: the ticker samples every 50ms, so the last recorded
            // progress for a finished memo is ~0.996–0.999 and would slip under
            // a `progress >= 0.999` test, giving one silent tap per playthrough.
            if p.currentTime >= p.duration - 0.05 {
                progress = 0
                p.currentTime = 0
            }
            activateSession()
            p.play()
            isPlaying = true
        }
    }

    private func load() async {
        isLoading = true
        defer { isLoading = false }
        do {
            let data = try await TrainingMemoStorage.data(for: url)
            let p = try AVAudioPlayer(data: data)
            p.prepareToPlay()
            player = p
            duration = p.duration
        } catch {
            Log.app.error("MemoPlayerRow load failed: \(error.localizedDescription)")
            failed = true
        }
    }

    private func stop() {
        player?.stop()
        isPlaying = false
        deactivateSession()
    }

    // MARK: Audio session
    //
    // Recording (VoiceLogView / WorkoutReceiptSignals) sets `.playAndRecord`
    // when it starts, so claiming `.playback` here and releasing it on
    // pause/stop can't strand the recorder in the wrong category.

    private func activateSession() {
        do {
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .spokenAudio)
            try AVAudioSession.sharedInstance().setActive(true)
            didActivateSession = true
        } catch {
            Log.app.error("MemoPlayerRow session activate failed: \(error.localizedDescription)")
        }
    }

    /// Only ever release a session this row actually claimed — see
    /// `didActivateSession`.
    private func deactivateSession() {
        guard didActivateSession else { return }
        didActivateSession = false
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }
}
