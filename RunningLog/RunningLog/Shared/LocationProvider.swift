//
//  LocationProvider.swift
//  RunningLog
//
//  Thin wrapper over CLLocationManager that returns a single recent
//  coordinate fix on demand. Used by the heat-forecast path: when the
//  athlete pins a per-workout time, we ask CoreLocation where they are
//  and pass that to fetch-workout-weather so the forecast reflects the
//  athlete's actual city — not a phantom `user_profiles.home_lat` row
//  that doesn't exist on the server.
//
//  Caches the most recent fix in memory for 5 minutes so back-to-back
//  edits don't burn a fresh CL request each time. Cache survives screen
//  navigation but not app relaunch — fine for the tap-pill-update flow.
//

import CoreLocation
import os

@MainActor
final class LocationProvider: NSObject {
    static let shared = LocationProvider()

    /// Cached fix lifetime. Long enough to absorb consecutive workout edits;
    /// short enough that a stale fix in a different city won't lie all day.
    private static let cacheTTL: TimeInterval = 300

    private let manager = CLLocationManager()
    private var cached: (location: CLLocationCoordinate2D, at: Date)?
    private var inFlight: [CheckedContinuation<CLLocationCoordinate2D?, Never>] = []

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyKilometer  // weather grid is coarse
    }

    /// Read-only view of CLLocationManager's current authorization. Used
    /// by callers to disambiguate a nil coordinate ("permission denied"
    /// vs "still resolving").
    func authorizationStatus() -> CLAuthorizationStatus {
        manager.authorizationStatus
    }

    /// One-shot async fetch of the device's current coordinate. Returns
    /// nil when permission is denied, location services are off, or the
    /// fix times out. Never throws — the heat banner is non-critical UX
    /// so callers fall back to "no forecast available" rather than
    /// surfacing the failure as an error.
    func currentCoordinate() async -> CLLocationCoordinate2D? {
        if let c = cached, Date().timeIntervalSince(c.at) < Self.cacheTTL {
            return c.location
        }

        let status = manager.authorizationStatus
        switch status {
        case .notDetermined:
            manager.requestWhenInUseAuthorization()
            // Don't block — caller will retry next time the athlete taps.
            return nil
        case .denied, .restricted:
            Log.health.warning("LocationProvider: authorization denied/restricted")
            return nil
        case .authorizedWhenInUse, .authorizedAlways:
            break
        @unknown default:
            return nil
        }

        return await withCheckedContinuation { (cont: CheckedContinuation<CLLocationCoordinate2D?, Never>) in
            inFlight.append(cont)
            // requestLocation delivers a single update via the delegate.
            // CLLocationManager already deduplicates concurrent requests
            // internally; we batch our continuations so a burst of
            // simultaneous callers all receive the same fix.
            if inFlight.count == 1 {
                manager.requestLocation()
            }
        }
    }
}

extension LocationProvider: CLLocationManagerDelegate {
    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let loc = locations.last else { return }
        let coord = loc.coordinate
        Task { @MainActor in
            self.cached = (location: coord, at: Date())
            let waiters = self.inFlight
            self.inFlight.removeAll()
            for w in waiters { w.resume(returning: coord) }
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        Task { @MainActor in
            Log.health.error("LocationProvider failed: \(error.localizedDescription)")
            let waiters = self.inFlight
            self.inFlight.removeAll()
            for w in waiters { w.resume(returning: nil) }
        }
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        // After first prompt fires, kick off a fetch so the next caller
        // gets a fix without having to re-tap. Best-effort — no-op when
        // still .notDetermined or denied.
        let status = manager.authorizationStatus
        if status == .authorizedWhenInUse || status == .authorizedAlways {
            Task { @MainActor in manager.requestLocation() }
        }
    }
}
