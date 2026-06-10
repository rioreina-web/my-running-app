//
//  JoinCoachPlanFlowMockup.swift
//  RunningLog
//
//  STATIC MOCKUP — not wired to data, not wired to subscribe-to-plan.
//  This file exists so the design of the rebuilt onboarding sheet
//  (per athlete-onboarding-redesign.md) can be eyeballed in simulator
//  before any real refactor of JoinCoachPlanSheet.swift.
//
//  How to preview: in Xcode, navigate to this file and use the SwiftUI
//  canvas (#Preview block at the bottom). Shows the full 6-section
//  flow + week-1 preview at the bottom.
//
//  When the design is approved, fold this into the real JoinCoachPlanSheet
//  with state wiring, edge-fn calls, and validation. This file should be
//  deleted at that point.
//

import SwiftUI

struct JoinCoachPlanFlowMockup: View {
    // All state is local to the mockup — no persistence, no edge fn calls.

    // MARK: - Section state (mock values)
    @State private var goalUseCoach: Bool = false
    @State private var goalHours = 2
    @State private var goalMinutes = 30
    @State private var goalSeconds = 0
    @State private var goalDistance = "Marathon"

    @State private var selectedRestDows: Set<Int> = [4]   // Friday default mock
    @State private var selectedQualityDows: Set<Int> = [1, 3]  // Tue + Thu
    @State private var longRunDow: Int = 5  // Saturday

    @State private var currentWeeklyMileage: Double = 32
    @State private var rampStartMileage: Double = 35
    @State private var useFullRangeFromWeek1: Bool = false

    @State private var stridesPreQuality: Bool = true
    @State private var recoveryAfterLong: Bool = true
    @State private var doublesOnEasy: Bool = false

    @State private var startDate: Date = Calendar.current.nextMonday() ?? Date()

    private let dayNames = ["M", "T", "W", "Th", "F", "Sa", "Su"]

    var body: some View {
        NavigationStack {
            ZStack {
                Color.drip.background.ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 24) {
                        // ── HEADER ───────────────────────────────────
                        VStack(alignment: .leading, spacing: 4) {
                            Text("SUBSCRIBE TO PLAN")
                                .font(.dripCaption(11))
                                .tracking(1.4)
                                .foregroundStyle(Color.drip.textTertiary)
                            Text("Aerobic Base · Marathon · 16 weeks")
                                .font(.dripDisplay(20))
                                .foregroundStyle(Color.drip.textPrimary)
                            Text("from Coach Sarah")
                                .font(.dripBody(13))
                                .foregroundStyle(Color.drip.textSecondary)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 20)
                        .padding(.top, 12)

                        section1Goal
                        section2RestDays
                        section3QualityDays
                        section4Volume
                        section5Shape
                        section6StartDate

                        // ── PREVIEW ──────────────────────────────────
                        weekPreview

                        // ── SUBMIT ───────────────────────────────────
                        Button(action: { /* mockup — no action */ }) {
                            HStack(spacing: 6) {
                                Text("Subscribe to plan")
                                    .font(.dripLabel(15))
                                Image(systemName: "arrow.right").font(.system(size: 12))
                            }
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(Color.drip.coral)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                        }
                        .padding(.horizontal, 20)
                        .padding(.top, 8)
                        .padding(.bottom, 32)
                    }
                }
            }
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    // MARK: - Section 1: Goal

    private var section1Goal: some View {
        sectionCard(number: 1, title: "YOUR GOAL") {
            VStack(alignment: .leading, spacing: 10) {
                Text("This plan is built for a 2:25 marathon.")
                    .font(.dripBody(13))
                    .foregroundStyle(Color.drip.textSecondary)

                radio(label: "Train at coach's paces (recommended)",
                      selected: goalUseCoach,
                      action: { goalUseCoach = true })

                radio(label: "My goal is...",
                      selected: !goalUseCoach,
                      action: { goalUseCoach = false })

                if !goalUseCoach {
                    HStack(spacing: 6) {
                        timeStepper(value: $goalHours, range: 0...10)
                        Text(":").font(.dripStat(14)).foregroundStyle(Color.drip.textTertiary)
                        timeStepper(value: $goalMinutes, range: 0...59)
                        Text(":").font(.dripStat(14)).foregroundStyle(Color.drip.textTertiary)
                        timeStepper(value: $goalSeconds, range: 0...59)
                        Spacer()
                        distancePicker
                    }
                    .padding(.leading, 26)
                }
            }
        }
    }

    // MARK: - Section 2: Rest days

    private var section2RestDays: some View {
        sectionCard(number: 2, title: "REST DAYS") {
            VStack(alignment: .leading, spacing: 10) {
                Text("Pick zero, one, or many. Your call.")
                    .font(.dripBody(13))
                    .foregroundStyle(Color.drip.textSecondary)

                HStack(spacing: 6) {
                    ForEach(0..<7) { dow in
                        dayPill(label: dayNames[dow],
                                selected: selectedRestDows.contains(dow),
                                action: {
                                    if selectedRestDows.contains(dow) {
                                        selectedRestDows.remove(dow)
                                    } else {
                                        selectedRestDows.insert(dow)
                                    }
                                })
                    }
                }

                if selectedRestDows.isEmpty {
                    Text("No rest is fine — adaptive plans don't require one.")
                        .font(.dripCaption(11))
                        .foregroundStyle(Color.drip.textTertiary)
                }
            }
        }
    }

    // MARK: - Section 3: Quality days

    private var section3QualityDays: some View {
        sectionCard(number: 3, title: "YOUR QUALITY DAYS") {
            VStack(alignment: .leading, spacing: 10) {
                Text("Coach calls for 2 quality days per week.\nPick when you can do them.")
                    .font(.dripBody(13))
                    .foregroundStyle(Color.drip.textSecondary)

                HStack(spacing: 6) {
                    ForEach(0..<7) { dow in
                        dayPill(label: dayNames[dow],
                                selected: selectedQualityDows.contains(dow),
                                action: {
                                    if selectedQualityDows.contains(dow) {
                                        selectedQualityDows.remove(dow)
                                    } else {
                                        selectedQualityDows.insert(dow)
                                    }
                                })
                    }
                }

                HStack {
                    Text("Long run lands on:")
                        .font(.dripBody(13))
                        .foregroundStyle(Color.drip.textSecondary)
                    Picker("Long run day", selection: $longRunDow) {
                        ForEach(0..<7) { dow in
                            Text(["Mon","Tue","Wed","Thu","Fri","Sat","Sun"][dow]).tag(dow)
                        }
                    }
                    .pickerStyle(.menu)
                    .tint(Color.drip.coral)
                }
            }
        }
    }

    // MARK: - Section 4: Volume

    private var section4Volume: some View {
        sectionCard(number: 4, title: "STARTING VOLUME") {
            VStack(alignment: .leading, spacing: 12) {
                Text("Coach prescribes 50–60 mi/week.")
                    .font(.dripBody(13))
                    .foregroundStyle(Color.drip.textSecondary)

                VStack(alignment: .leading, spacing: 6) {
                    Text("What's your current weekly mileage?")
                        .font(.dripCaption(12))
                        .foregroundStyle(Color.drip.textSecondary)
                    HStack(spacing: 4) {
                        TextField("32", value: $currentWeeklyMileage, format: .number)
                            .keyboardType(.decimalPad)
                            .padding(8)
                            .background(Color.drip.background)
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                            .frame(width: 80)
                        Text("mi/week")
                            .font(.dripBody(13))
                            .foregroundStyle(Color.drip.textTertiary)
                    }
                    Text("We pre-fill from your last 4 weeks of logs when available.")
                        .font(.dripCaption(10))
                        .foregroundStyle(Color.drip.textTertiary)
                }

                Divider().background(Color.drip.divider)

                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 6) {
                        Text("Ramp from")
                            .font(.dripBody(13))
                            .foregroundStyle(Color.drip.textSecondary)
                        TextField("35", value: $rampStartMileage, format: .number)
                            .keyboardType(.decimalPad)
                            .padding(6)
                            .background(Color.drip.background)
                            .clipShape(RoundedRectangle(cornerRadius: 6))
                            .frame(width: 56)
                        Text("mi to coach's 50–60")
                            .font(.dripBody(13))
                            .foregroundStyle(Color.drip.textSecondary)
                    }
                    Text("over the first 4 weeks")
                        .font(.dripCaption(11))
                        .foregroundStyle(Color.drip.textTertiary)
                        .padding(.leading, 4)

                    Toggle(isOn: $useFullRangeFromWeek1) {
                        Text("Use coach's full range from Week 1")
                            .font(.dripBody(13))
                    }
                    .tint(Color.drip.coral)
                    .padding(.top, 4)
                }
            }
        }
    }

    // MARK: - Section 5: Shape

    private var section5Shape: some View {
        sectionCard(number: 5, title: "WORKOUT SHAPE") {
            VStack(alignment: .leading, spacing: 10) {
                Text("Optional shape preferences. Defaults are coach's.")
                    .font(.dripBody(13))
                    .foregroundStyle(Color.drip.textSecondary)

                Toggle(isOn: $stridesPreQuality) {
                    Text("Strides on the day before quality").font(.dripBody(13))
                }.tint(Color.drip.coral)

                Toggle(isOn: $recoveryAfterLong) {
                    Text("Easy recovery after long run").font(.dripBody(13))
                }.tint(Color.drip.coral)

                Toggle(isOn: $doublesOnEasy) {
                    Text("Add a second easy run on non-quality days").font(.dripBody(13))
                }.tint(Color.drip.coral)
            }
        }
    }

    // MARK: - Section 6: Start date

    private var section6StartDate: some View {
        sectionCard(number: 6, title: "START DATE") {
            VStack(alignment: .leading, spacing: 6) {
                DatePicker("Start", selection: $startDate, displayedComponents: [.date])
                    .labelsHidden()
                    .datePickerStyle(.compact)
                    .tint(Color.drip.coral)
                Text("Plans always start on a Monday — we'll snap to the nearest one.")
                    .font(.dripCaption(11))
                    .foregroundStyle(Color.drip.textTertiary)
            }
        }
    }

    // MARK: - Week 1 preview

    private var weekPreview: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("PREVIEW WEEK 1")
                .font(.dripCaption(11))
                .tracking(1.4)
                .foregroundStyle(Color.drip.textTertiary)

            VStack(spacing: 0) {
                previewRow(day: "Mon", workout: previewWorkout(for: 0), highlight: false)
                Divider().background(Color.drip.divider)
                previewRow(day: "Tue", workout: previewWorkout(for: 1), highlight: selectedQualityDows.contains(1))
                Divider().background(Color.drip.divider)
                previewRow(day: "Wed", workout: previewWorkout(for: 2), highlight: false)
                Divider().background(Color.drip.divider)
                previewRow(day: "Thu", workout: previewWorkout(for: 3), highlight: selectedQualityDows.contains(3))
                Divider().background(Color.drip.divider)
                previewRow(day: "Fri", workout: previewWorkout(for: 4), highlight: false)
                Divider().background(Color.drip.divider)
                previewRow(day: "Sat", workout: previewWorkout(for: 5), highlight: longRunDow == 5)
                Divider().background(Color.drip.divider)
                previewRow(day: "Sun", workout: previewWorkout(for: 6), highlight: false)
            }
            .background(Color.drip.cardBackground)
            .clipShape(RoundedRectangle(cornerRadius: 12))

            Text("≈ \(Int(rampStartMileage)) mi this week")
                .font(.dripCaption(11))
                .foregroundStyle(Color.drip.textTertiary)
                .padding(.leading, 4)
        }
        .padding(.horizontal, 20)
    }

    // Mock preview content — derived from current selections.
    // The real impl will call PlanPreviewMaterializer.swift.
    private func previewWorkout(for dow: Int) -> String {
        if selectedRestDows.contains(dow) { return "Rest" }
        if selectedQualityDows.contains(dow) {
            return dow == longRunDow ? "Long run · 14 mi" : "Quality · ~5 mi"
        }
        if dow == longRunDow { return "Long run · 14 mi" }
        return "Easy · 5 mi"
    }

    private func previewRow(day: String, workout: String, highlight: Bool) -> some View {
        HStack {
            Text(day)
                .font(.dripCaption(12))
                .foregroundStyle(Color.drip.textSecondary)
                .frame(width: 36, alignment: .leading)
            Text(workout)
                .font(.dripBody(13))
                .foregroundStyle(highlight ? Color.drip.textPrimary : Color.drip.textSecondary)
                .fontWeight(highlight ? .medium : .regular)
            Spacer()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    // MARK: - Reusable section + control primitives

    private func sectionCard<Content: View>(number: Int, title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Text("\(number).").font(.dripCaption(11))
                    .foregroundStyle(Color.drip.textTertiary)
                Text(title)
                    .font(.dripCaption(11))
                    .tracking(1.4)
                    .foregroundStyle(Color.drip.textTertiary)
            }
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(Color.drip.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .padding(.horizontal, 20)
    }

    private func radio(label: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 8) {
                ZStack {
                    Circle()
                        .stroke(selected ? Color.drip.coral : Color.drip.divider, lineWidth: 1.5)
                        .frame(width: 16, height: 16)
                    if selected {
                        Circle()
                            .fill(Color.drip.coral)
                            .frame(width: 8, height: 8)
                    }
                }
                Text(label)
                    .font(.dripBody(13))
                    .foregroundStyle(Color.drip.textPrimary)
                Spacer()
            }
        }
        .buttonStyle(.plain)
    }

    private func dayPill(label: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label)
                .font(.dripCaption(12))
                .foregroundStyle(selected ? .white : Color.drip.textSecondary)
                .frame(width: 36, height: 36)
                .background(selected ? Color.drip.coral : Color.drip.background)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(selected ? Color.drip.coral : Color.drip.divider, lineWidth: 0.5)
                )
        }
        .buttonStyle(.plain)
    }

    private func timeStepper(value: Binding<Int>, range: ClosedRange<Int>) -> some View {
        Picker("", selection: value) {
            ForEach(range, id: \.self) { v in
                Text(String(format: "%02d", v)).tag(v)
            }
        }
        .pickerStyle(.menu)
        .tint(Color.drip.textPrimary)
    }

    private var distancePicker: some View {
        Picker("Distance", selection: $goalDistance) {
            Text("Marathon").tag("Marathon")
            Text("Half").tag("Half")
            Text("10K").tag("10K")
            Text("5K").tag("5K")
        }
        .pickerStyle(.menu)
        .tint(Color.drip.coral)
    }
}

// MARK: - Calendar helper

private extension Calendar {
    func nextMonday(from date: Date = Date()) -> Date? {
        let components = DateComponents(weekday: 2)  // Monday = 2 in Calendar
        return self.nextDate(after: date, matching: components, matchingPolicy: .nextTime)
    }
}

// MARK: - Preview

#Preview {
    JoinCoachPlanFlowMockup()
}
