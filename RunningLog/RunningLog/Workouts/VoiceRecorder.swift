//
//  VoiceRecorder.swift
//  RunningLog
//
//  The microphone, extracted.
//
//  This is `VoiceLogView`'s private recording code — permission handling,
//  session activation, the AVAudioRecorder, the tick timer — lifted into
//  something two screens can share. `LogWildView` and `CheckInView` both
//  use it.
//
//  `VoiceLogView` is deliberately NOT changed to use this. It is the
//  editorial skin's Log screen and it still works; rewiring it would put
//  the old app at risk for no gain. When the wild skin wins, that file
//  goes away and takes its copy with it.
//
//  Every behaviour here is preserved from the original, including the two
//  beta-audit fixes it carries:
//    • permission is requested before recording, never assumed
//    • `record()`'s return value is checked, so the timer never runs over
//      dead air when another app holds the mic
//

import AVFoundation
import Observation
import SwiftUI

/// `@MainActor` for three reasons, all of which the Swift 6 checker was
/// pointing at: the timer fires on the main run loop, `duration` is read from
/// a view body every tick, and a global-actor-isolated class is implicitly
/// `Sendable` — which is what lets the `Timer` block capture `self` at all.
/// Same shape as `TrainingAnalyticsViewModel` and `FitnessAssessmentViewModel`.
@MainActor
@Observable
final class VoiceRecorder {

    enum Outcome {
        case recorded(url: URL, duration: TimeInterval)
        case permissionDenied
        case failed(String)
    }

    private(set) var isRecording = false
    private(set) var duration: TimeInterval = 0

    @ObservationIgnored private var recorder: AVAudioRecorder?
    @ObservationIgnored private var timer: Timer?
    @ObservationIgnored private var url: URL?

    /// Configure the category eagerly, activate lazily.
    ///
    /// Activating on appear surfaces a spurious "failed to set up audio"
    /// banner whenever the simulator has no audio device, another app holds
    /// the route, or backgrounding interrupted us. Activation happens at
    /// record time, where an error is honest because the user just pressed
    /// a button.
    func prepare() {
        do {
            try AVAudioSession.sharedInstance().setCategory(.playAndRecord, mode: .default)
        } catch {
            print("[VoiceRecorder] setCategory failed (will retry at record time): \(error)")
        }
    }

    /// Start, asking for the microphone first if we've never asked.
    /// `onDenied` fires on the main actor when the answer is no.
    func start(onDenied: @escaping () -> Void, onError: @escaping (String) -> Void) {
        switch AVAudioApplication.shared.recordPermission {
        case .denied:
            onDenied()
        case .undetermined:
            // This Task inherits the class's MainActor isolation, so there is
            // no hop to write by hand.
            Task {
                let granted = await AVAudioApplication.requestRecordPermission()
                granted ? begin(onError: onError) : onDenied()
            }
        default:
            begin(onError: onError)
        }
    }

    private func begin(onError: @escaping (String) -> Void) {
        let name = "training_memo_\(Date().timeIntervalSince1970).m4a"
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let dest = docs.appendingPathComponent(name)

        let settings: [String: Any] = [
            AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
            AVSampleRateKey: 44100,
            AVNumberOfChannelsKey: 1,
            AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue
        ]

        do {
            try AVAudioSession.sharedInstance().setActive(true)
            recorder = try AVAudioRecorder(url: dest, settings: settings)

            guard recorder?.record() == true else {
                recorder = nil
                try? AVAudioSession.sharedInstance().setActive(false)
                onError("Error: Couldn't start recording — another app may be using the microphone.")
                return
            }

            url = dest
            isRecording = true
            duration = 0
            timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
                // The block already runs on the main run loop, so assume the
                // isolation rather than hopping through a Task. Two reasons:
                // a Task would let a tick land a frame late, and under Swift 6
                // it captures `self` across an isolation boundary — which is
                // the error this replaced.
                MainActor.assumeIsolated {
                    self?.duration += 1
                }
            }
        } catch {
            print("[VoiceRecorder] start failed: \(error)")
            onError("Error: Failed to start recording")
        }
    }

    /// Stop and hand back the file. Returns `nil` if there was nothing.
    @discardableResult
    func stop() -> (url: URL, duration: TimeInterval)? {
        recorder?.stop()
        timer?.invalidate()
        timer = nil
        isRecording = false
        guard let url else { return nil }
        return (url, duration)
    }

    /// Throw the take away and delete the file off disk.
    func discard() {
        if let url { try? FileManager.default.removeItem(at: url) }
        url = nil
        duration = 0
    }

    /// Forget the take without deleting — the upload path owns the file now.
    func release() {
        url = nil
        duration = 0
    }

    /// "m:ss". Tabular digits are the caller's job.
    ///
    /// `nonisolated` because it is pure arithmetic on its argument. Without
    /// it, a static member of a `@MainActor` class inherits that isolation,
    /// which would make this unusable from anywhere off the main actor for
    /// no reason.
    nonisolated static func clock(_ seconds: TimeInterval) -> String {
        String(format: "%d:%02d", Int(seconds) / 60, Int(seconds) % 60)
    }
}
