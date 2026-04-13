//
//  PeriodPickerSheet.swift
//  RunningLog
//
//  Period selection sheet and shared divider for the analysis feature.
//

import SwiftUI

// MARK: - PeriodPickerSheet

struct PeriodPickerSheet: View {
    @Bindable var viewModel: AnalysisViewModel
    @Binding var isPresented: Bool

    var body: some View {
        NavigationStack {
            ZStack {
                Color.drip.background.ignoresSafeArea()

                VStack(spacing: 16) {
                    // Period type toggle
                    HStack(spacing: 0) {
                        ForEach(AnalysisViewModel.PeriodType.allCases, id: \.self) { type in
                            Button {
                                withAnimation(.easeInOut(duration: 0.2)) {
                                    viewModel.selectedPeriodType = type
                                }
                            } label: {
                                Text(type.rawValue)
                                    .font(.dripLabel(13))
                                    .foregroundStyle(viewModel.selectedPeriodType == type ? .white : Color.drip.textSecondary)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 10)
                                    .background(viewModel.selectedPeriodType == type ? Color.drip.coral : Color.clear)
                                    .clipShape(RoundedRectangle(cornerRadius: 8))
                            }
                        }
                    }
                    .padding(3)
                    .background(Color.drip.cardBackground)
                    .clipShape(RoundedRectangle(cornerRadius: 10))

                    // Pickers side by side: Year + (Week or Month)
                    HStack(spacing: 0) {
                        // Year Picker
                        VStack(spacing: 4) {
                            Text("YEAR")
                                .font(.dripCaption(10))
                                .foregroundStyle(Color.drip.textSecondary)
                                .tracking(1.0)

                            Picker("Year", selection: $viewModel.selectedYear) {
                                ForEach(viewModel.availableYears, id: \.self) { year in
                                    Text(String(year))
                                        .foregroundStyle(Color.drip.textPrimary)
                                        .tag(year)
                                }
                            }
                            .pickerStyle(.wheel)
                            .frame(height: 140)
                        }
                        .frame(maxWidth: viewModel.selectedPeriodType == .year ? .infinity : nil)
                        .frame(width: viewModel.selectedPeriodType == .year ? nil : 120)

                        // Week or Month Picker
                        if viewModel.selectedPeriodType == .week {
                            VStack(spacing: 4) {
                                Text("WEEK")
                                    .font(.dripCaption(10))
                                    .foregroundStyle(Color.drip.textSecondary)
                                    .tracking(1.0)

                                Picker("Week", selection: $viewModel.selectedWeek) {
                                    ForEach(viewModel.availableWeeks, id: \.self) { week in
                                        weekLabel(week: week)
                                            .tag(week)
                                    }
                                }
                                .pickerStyle(.wheel)
                                .frame(height: 140)
                            }
                            .frame(maxWidth: .infinity)
                        }

                        if viewModel.selectedPeriodType == .month {
                            VStack(spacing: 4) {
                                Text("MONTH")
                                    .font(.dripCaption(10))
                                    .foregroundStyle(Color.drip.textSecondary)
                                    .tracking(1.0)

                                Picker("Month", selection: $viewModel.selectedMonth) {
                                    ForEach(viewModel.availableMonths, id: \.0) { month, name in
                                        Text(name)
                                            .foregroundStyle(Color.drip.textPrimary)
                                            .tag(month)
                                    }
                                }
                                .pickerStyle(.wheel)
                                .frame(height: 140)
                            }
                            .frame(maxWidth: .infinity)
                        }
                    }

                    // Current selection label
                    Text(viewModel.periodLabel)
                        .font(.dripLabel(16))
                        .foregroundStyle(Color.drip.textPrimary)
                        .padding(.vertical, 8)

                    // Analyze button — triggers fetch and dismisses
                    DripButton("Analyze", icon: "sparkles", style: .primary) {
                        isPresented = false
                        Task {
                            await viewModel.fetchAnalysis()
                        }
                    }
                }
                .padding(20)
            }
            .navigationTitle("Select Period")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Cancel") {
                        isPresented = false
                    }
                    .font(.dripBody(15))
                    .foregroundStyle(Color.drip.coral)
                }
            }
        }
        .presentationDetents([.medium])
    }

    private func weekLabel(week: Int) -> some View {
        if let dates = viewModel.getWeekDates(week: week, year: viewModel.selectedYear) {
            let formatter = DateFormatter()
            formatter.dateFormat = "MMM d"
            let startStr = formatter.string(from: dates.start)
            let endStr = formatter.string(from: dates.end)
            return Text("\(startStr) - \(endStr)")
                .foregroundStyle(Color.drip.textPrimary)
        } else {
            return Text("Week \(week)")
                .foregroundStyle(Color.drip.textPrimary)
        }
    }
}

// MARK: - Analysis Divider

struct AnalysisDivider: View {
    var body: some View {
        HStack(spacing: 8) {
            Rectangle()
                .fill(Color.drip.divider)
                .frame(height: 0.5)
            Circle()
                .fill(Color.drip.divider)
                .frame(width: 3, height: 3)
            Rectangle()
                .fill(Color.drip.divider)
                .frame(height: 0.5)
        }
    }
}
