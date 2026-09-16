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

/// Thin card wrapper around the shared `RouteMapView`. The section eyebrow
/// ("ROUTE") is supplied by the callsite, so this only adds the card chrome —
/// the map itself (real tiles, pace coloring, markers, tap-to-expand) lives
/// in `RouteMapView` and is identical to the interval-receipt map.
struct RouteMapCard: View {
    let route: [CLLocation]

    var body: some View {
        RouteMapView(route: route, showMileMarkers: true, height: 240)
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
