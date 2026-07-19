//
//  StadiaRouteMap.swift
//  RunningLog
//
//  Custom-styled street map for the EXPANDED route view.
//
//  The inline route stays the editorial ink-line on paper (see RouteMapView).
//  When the athlete taps to expand, THIS shows a real, pannable/zoomable
//  street map — but drawn on a *designed* basemap (Stadia Maps raster tiles,
//  e.g. Stamen "Toner": editorial black-ink streets) instead of Apple's
//  default tiles, so even the map reads on-brand.
//
//  The route itself (pace-colored line + casing + start/finish/mile/rep
//  markers) is drawn on top, exactly as elsewhere in the app.
//
//  ── ONE-TIME SETUP (no coding) ────────────────────────────────────────────
//    1. Make a free account at https://client.stadiamaps.com
//    2. Create an API key (Manage Properties → Authentication → add key).
//    3. Paste it into `StadiaMapsConfig.apiKey` below and rebuild.
//  Until a key is set, this gracefully falls back to Apple's standard map,
//  so the app keeps working with no key.
//
//  Note: Stadia's *prebuilt* styles (Toner / Alidade / Outdoors) are free to
//  use this way. A fully bespoke "warm paper" basemap (matching the paper
//  tokens exactly) is the vector-tile path (Mapbox / MapLibre) — a later step.
//

import MapKit
import SwiftUI
import UIKit

// MARK: - Config

enum StadiaMapsConfig {
    /// Paste your free Stadia Maps API key here.
    /// Get one at https://client.stadiamaps.com — it looks like a long
    /// hex string. Leave empty to fall back to the standard Apple map.
    static let apiKey = ""   // <-- TODO: paste your Stadia Maps API key

    /// Prebuilt Stadia style slug. Editorial-leaning options:
    ///   "stamen_toner_lite" — soft black-ink streets (default, most on-brand)
    ///   "stamen_toner"      — high-contrast black & white
    ///   "alidade_smooth"    — clean light grey
    ///   "outdoors"          — trails + terrain (good for trail runners)
    static let style = "stamen_toner_lite"

    /// True once a non-empty key has been pasted in.
    static var isConfigured: Bool {
        !apiKey.trimmingCharacters(in: .whitespaces).isEmpty
    }

    /// MKTileOverlay URL template. `@2x` requests retina (512px) tiles.
    static var tileURLTemplate: String {
        "https://tiles.stadiamaps.com/tiles/\(style)/{z}/{x}/{y}@2x.png?api_key=\(apiKey)"
    }
}

// MARK: - Annotation model

/// A single point drawn on the street map. Carries its own kind + label so the
/// delegate can pick the right glyph without any external lookup.
final class RoutePointAnnotation: MKPointAnnotation {
    enum Kind { case start, finish, mile, rep }
    let kind: Kind
    let text: String?

    init(coordinate: CLLocationCoordinate2D, kind: Kind, text: String?) {
        self.kind = kind
        self.text = text
        super.init()
        self.coordinate = coordinate
    }
}

// MARK: - Street map (UIViewRepresentable over MKMapView)

/// The expanded, real-street route map. Uses MKMapView (not the SwiftUI `Map`)
/// because a custom raster basemap needs an `MKTileOverlay`, which SwiftUI's
/// Map doesn't expose.
struct StreetRouteMapView: UIViewRepresentable {
    let region: MKCoordinateRegion
    let segments: [RouteSegment]
    let downsampledCoords: [CLLocationCoordinate2D]
    let clean: [CLLocation]
    let repMarkers: [RouteMarker]
    let mileMarkers: [RouteMarker]

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> MKMapView {
        let map = MKMapView(frame: .zero)
        map.delegate = context.coordinator
        map.pointOfInterestFilter = .excludingAll
        map.showsUserLocation = false
        map.showsCompass = true
        map.setRegion(region, animated: false)

        // 1) Designed basemap (only when a key is set; otherwise Apple's tiles).
        if StadiaMapsConfig.isConfigured {
            let tiles = MKTileOverlay(urlTemplate: StadiaMapsConfig.tileURLTemplate)
            tiles.canReplaceMapContent = true          // hide Apple's base
            tiles.tileSize = CGSize(width: 512, height: 512)
            map.addOverlay(tiles, level: .aboveLabels)
        }

        // 2) White casing under the route, for contrast on any basemap.
        if downsampledCoords.count > 1 {
            let casing = MKPolyline(coordinates: downsampledCoords, count: downsampledCoords.count)
            context.coordinator.casingID = ObjectIdentifier(casing)
            map.addOverlay(casing, level: .aboveLabels)
        }

        // 3) Pace-colored route on top (one merged polyline per color run).
        for seg in segments where seg.coords.count > 1 {
            let line = MKPolyline(coordinates: seg.coords, count: seg.coords.count)
            context.coordinator.colorsByPolyline[ObjectIdentifier(line)] = UIColor(seg.color)
            map.addOverlay(line, level: .aboveLabels)
        }

        // 4) Markers: mile ticks, interval reps, then start / finish dots.
        var annotations: [RoutePointAnnotation] = []
        annotations += mileMarkers.map {
            RoutePointAnnotation(coordinate: $0.coordinate, kind: .mile, text: $0.label)
        }
        annotations += repMarkers.map {
            RoutePointAnnotation(coordinate: $0.coordinate, kind: .rep, text: $0.label)
        }
        if let start = clean.first {
            annotations.append(RoutePointAnnotation(coordinate: start.coordinate, kind: .start, text: nil))
        }
        if let finish = clean.last {
            annotations.append(RoutePointAnnotation(coordinate: finish.coordinate, kind: .finish, text: nil))
        }
        map.addAnnotations(annotations)

        return map
    }

    func updateUIView(_ uiView: MKMapView, context: Context) {
        // Content is fixed for a given run; nothing to reconcile.
    }

    // MARK: Delegate

    final class Coordinator: NSObject, MKMapViewDelegate {
        var colorsByPolyline: [ObjectIdentifier: UIColor] = [:]
        var casingID: ObjectIdentifier?

        func mapView(_ mapView: MKMapView, rendererFor overlay: MKOverlay) -> MKOverlayRenderer {
            if let tile = overlay as? MKTileOverlay {
                return MKTileOverlayRenderer(tileOverlay: tile)
            }
            if let poly = overlay as? MKPolyline {
                let r = MKPolylineRenderer(polyline: poly)
                let id = ObjectIdentifier(poly)
                if id == casingID {
                    r.strokeColor = UIColor.white.withAlphaComponent(0.95)
                    r.lineWidth = 6.5
                } else {
                    r.strokeColor = colorsByPolyline[id] ?? UIColor(Color.drip.coral)
                    r.lineWidth = 3.8
                }
                r.lineCap = .round
                r.lineJoin = .round
                return r
            }
            return MKOverlayRenderer(overlay: overlay)
        }

        func mapView(_ mapView: MKMapView, viewFor annotation: MKAnnotation) -> MKAnnotationView? {
            guard let point = annotation as? RoutePointAnnotation else { return nil }
            let id = "routePoint"
            let view = mapView.dequeueReusableAnnotationView(withIdentifier: id)
                ?? MKAnnotationView(annotation: point, reuseIdentifier: id)
            view.annotation = point
            view.canShowCallout = false
            view.subviews.forEach { $0.removeFromSuperview() }

            let glyph: UIView
            switch point.kind {
            case .start:
                glyph = Self.dot(color: UIColor(Color.drip.positive), diameter: 16)
            case .finish:
                glyph = Self.dot(color: UIColor(Color.drip.coral), diameter: 16)
            case .mile:
                glyph = Self.badge(
                    text: point.text ?? "",
                    fg: UIColor(Color.drip.textSecondary),
                    bg: UIColor(Color.drip.cardBackgroundElevated),
                    border: UIColor(Color.drip.divider),
                    diameter: 18
                )
            case .rep:
                glyph = Self.badge(
                    text: point.text ?? "",
                    fg: UIColor(Color.drip.textPrimary),
                    bg: .white,
                    border: UIColor(Color.drip.textPrimary),
                    diameter: 20
                )
            }
            view.frame = glyph.frame
            view.addSubview(glyph)
            view.centerOffset = .zero
            return view
        }

        // MARK: Glyph builders

        static func dot(color: UIColor, diameter: CGFloat) -> UIView {
            let v = UIView(frame: CGRect(x: 0, y: 0, width: diameter, height: diameter))
            v.backgroundColor = color
            v.layer.cornerRadius = diameter / 2
            v.layer.borderColor = UIColor.white.cgColor
            v.layer.borderWidth = 2.5
            v.layer.shadowColor = UIColor.black.cgColor
            v.layer.shadowOpacity = 0.25
            v.layer.shadowRadius = 2
            v.layer.shadowOffset = CGSize(width: 0, height: 1)
            v.isUserInteractionEnabled = false
            return v
        }

        static func badge(text: String, fg: UIColor, bg: UIColor, border: UIColor, diameter: CGFloat) -> UIView {
            let v = UIView(frame: CGRect(x: 0, y: 0, width: diameter, height: diameter))
            v.backgroundColor = bg
            v.layer.cornerRadius = diameter / 2
            v.layer.borderColor = border.cgColor
            v.layer.borderWidth = 1.2
            v.isUserInteractionEnabled = false

            let label = UILabel(frame: v.bounds)
            label.text = text
            label.textAlignment = .center
            label.font = .monospacedSystemFont(ofSize: 9, weight: .semibold)
            label.textColor = fg
            label.adjustsFontSizeToFitWidth = true
            label.minimumScaleFactor = 0.6
            v.addSubview(label)
            return v
        }
    }
}
