//
//  VitalWorkoutCards.swift
//  RunningLog
//
//  Card components for VitalWorkoutDetailView.
//  Includes RouteMapCard, SplitRow, and PaceSplitRow.
//

import CoreLocation
import MapKit
import SwiftUI

// MARK: - Route Map Card

struct RouteMapCard: View {
    let route: [CLLocation]

    var region: MKCoordinateRegion {
        guard !route.isEmpty else {
            return MKCoordinateRegion()
        }
        let lats = route.map(\.coordinate.latitude)
        let lngs = route.map(\.coordinate.longitude)
        let minLat = lats.min() ?? 0
        let maxLat = lats.max() ?? 0
        let minLng = lngs.min() ?? 0
        let maxLng = lngs.max() ?? 0
        let center = CLLocationCoordinate2D(
            latitude: (minLat + maxLat) / 2,
            longitude: (minLng + maxLng) / 2
        )
        let span = MKCoordinateSpan(
            latitudeDelta: (maxLat - minLat) * 1.4 + 0.002,
            longitudeDelta: (maxLng - minLng) * 1.4 + 0.002
        )
        return MKCoordinateRegion(center: center, span: span)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "map.fill")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Color.drip.coral)
                Text("ROUTE")
                    .font(.dripCaption(11))
                    .foregroundStyle(Color.drip.textSecondary)
                    .tracking(1.2)
            }

            Map(initialPosition: .region(region)) {
                MapPolyline(coordinates: route.map(\.coordinate))
                    .stroke(Color.drip.coral, lineWidth: 3)

                // Start marker
                if let start = route.first?.coordinate {
                    Annotation("Start", coordinate: start) {
                        Circle()
                            .fill(Color.green)
                            .frame(width: 12, height: 12)
                            .overlay(Circle().stroke(.white, lineWidth: 2))
                    }
                }

                // End marker
                if let end = route.last?.coordinate {
                    Annotation("Finish", coordinate: end) {
                        Circle()
                            .fill(Color.drip.coral)
                            .frame(width: 12, height: 12)
                            .overlay(Circle().stroke(.white, lineWidth: 2))
                    }
                }
            }
            .mapStyle(.standard(elevation: .realistic))
            .frame(height: 240)
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
        .padding(20)
        .background(Color.drip.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(Color.drip.divider, lineWidth: 1)
        )
    }
}

// MARK: - Split Row

struct SplitRow: View {
    let split: MileSplit
    let fastestPace: Double
    let slowestPace: Double

    private var barWidth: CGFloat {
        guard slowestPace > fastestPace else { return 0.5 }
        let range = slowestPace - fastestPace
        let normalized = (split.paceMinutes - fastestPace) / range
        return CGFloat(1.0 - normalized * 0.6) // Fastest = full width, slowest = 40%
    }

    private var paceColor: Color {
        guard slowestPace > fastestPace else { return Color.drip.coral }
        let range = slowestPace - fastestPace
        let normalized = (split.paceMinutes - fastestPace) / range
        if normalized < 0.33 { return Color.drip.positive }
        if normalized < 0.66 { return Color.drip.coral }
        return Color.drip.tired
    }

    var body: some View {
        HStack(spacing: 12) {
            // Mile number
            Text(split.isPartial ? "\(String(format: "%.1f", split.partialDistance))" : "\(split.mile)")
                .font(.dripLabel(14))
                .foregroundStyle(Color.drip.textSecondary)
                .frame(width: 28, alignment: .trailing)

            // Pace bar
            GeometryReader { geo in
                RoundedRectangle(cornerRadius: 4)
                    .fill(paceColor.opacity(0.3))
                    .frame(width: geo.size.width * barWidth, height: 24)
                    .overlay(alignment: .trailing) {
                        Text(split.formattedPace)
                            .font(.dripLabel(12))
                            .foregroundStyle(paceColor)
                            .padding(.trailing, 8)
                    }
            }
            .frame(height: 24)

            // Split time (how long this mile took)
            Text(split.formattedSplitTime)
                .font(.dripCaption(11))
                .foregroundStyle(Color.drip.textTertiary)
                .frame(width: 52, alignment: .trailing)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .overlay(alignment: .bottom) {
            if !split.isPartial {
                Rectangle()
                    .fill(Color.drip.divider)
                    .frame(height: 0.5)
                    .padding(.leading, 56)
            }
        }
    }
}

// MARK: - Pace Split Row (Garmin-style)

struct PaceSplitRow: View {
    let split: PaceSplit
    let fastestPace: Double
    let slowestPace: Double

    private var paceColor: Color {
        guard slowestPace > fastestPace else { return Color.drip.coral }
        let range = slowestPace - fastestPace
        guard range > 0 else { return Color.drip.coral }
        let normalized = (split.paceMinutes - fastestPace) / range
        if normalized < 0.33 { return Color.drip.positive }
        if normalized < 0.66 { return Color.drip.coral }
        return Color.drip.tired
    }

    private var barWidth: CGFloat {
        guard slowestPace > fastestPace else { return 0.5 }
        let range = slowestPace - fastestPace
        let normalized = (split.paceMinutes - fastestPace) / range
        return CGFloat(1.0 - normalized * 0.6)
    }

    var body: some View {
        HStack(spacing: 0) {
            // Segment number
            Text("\(split.segment)")
                .font(.dripLabel(13))
                .foregroundStyle(Color.drip.textSecondary)
                .frame(width: 24, alignment: .trailing)

            // Duration
            Text(split.formattedDuration)
                .font(.dripLabel(13))
                .foregroundStyle(Color.drip.textPrimary)
                .frame(width: 60, alignment: .center)

            // Distance
            Text(split.formattedDistance)
                .font(.dripLabel(12))
                .foregroundStyle(Color.drip.textSecondary)
                .frame(width: 58, alignment: .center)

            // Pace bar
            GeometryReader { geo in
                RoundedRectangle(cornerRadius: 4)
                    .fill(paceColor.opacity(0.25))
                    .frame(width: geo.size.width * barWidth, height: 22)
                    .overlay(alignment: .trailing) {
                        Text(split.formattedPace)
                            .font(.dripLabel(12))
                            .foregroundStyle(paceColor)
                            .padding(.trailing, 6)
                    }
            }
            .frame(height: 22)

            // Heart rate
            if let hr = split.avgHeartRate {
                Text("\(hr)")
                    .font(.dripCaption(11))
                    .foregroundStyle(Color.drip.injured)
                    .frame(width: 38, alignment: .trailing)
            } else {
                Text("--")
                    .font(.dripCaption(11))
                    .foregroundStyle(Color.drip.textTertiary)
                    .frame(width: 38, alignment: .trailing)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(Color.drip.divider)
                .frame(height: 0.5)
                .padding(.leading, 36)
        }
    }
}
