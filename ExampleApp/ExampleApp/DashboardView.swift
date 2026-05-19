import SwiftUI
import SensorBioSDK

struct DashboardView: View {
    let session: SB_Session

    @Environment(AppDateContext.self) private var dateContext
    @State private var dashboard = DashboardState()
    @State private var postSyncRefreshTask: Task<Void, Never>? = nil

    var body: some View {
        @Bindable var ctx = dateContext
        List {
            if dashboard.isLoading && dashboard.data == nil {
                Section("Today") {
                    HStack {
                        ProgressView()
                        Text("Loading dashboard\u{2026}").foregroundStyle(.secondary)
                    }
                }
            } else if let error = dashboard.errorMessage {
                Section("Today") {
                    Label(error, systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                }
            } else if let data = dashboard.data {
                Section("Summary") {
                    if let activity = data.activity {
                        LabeledContent("Activity", value: "\(Int(activity.item.value))")
                    }
                    if let recovery = data.recovery {
                        NavigationLink {
                            RecoveryDetailView()
                        } label: {
                            LabeledContent("Recovery", value: "\(Int(recovery.item.value))")
                        }
                    }
                    if let sleep = data.sleep {
                        NavigationLink {
                            SleepDetailView()
                        } label: {
                            LabeledContent("Sleep",
                                value: "\(Int(sleep.item.value)) · \(sleep.durationSeconds / 3600)h \((sleep.durationSeconds % 3600) / 60)m")
                        }
                    }
                }
                Section("Metrics") {
                    if data.metrics.isEmpty {
                        Text("No metrics for today").foregroundStyle(.secondary)
                    } else {
                        ForEach(data.metrics, id: \.metricType) { metric in
                            metricRow(metric)
                        }
                    }
                }
            }
        }
        .navigationTitle("Dashboard")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                DatePicker(
                    "Date",
                    selection: $ctx.selectedDate,
                    in: ...Date(),
                    displayedComponents: .date
                )
                .labelsHidden()
            }
        }
        .task(id: dateContext.selectedDate) { await dashboard.load(date: dateContext.selectedDate) }
        .refreshable { await dashboard.load(date: dateContext.selectedDate) }
        .onReceive(sensorBio.$lastSyncd.dropFirst()) { _ in
            // Device just synced. Schedule a dashboard refresh ~30s out
            // (server-side processing lags the BLE sync) but only if the
            // user is looking at today's data — historical days don't
            // change in response to new syncs.
            guard Calendar.current.isDateInToday(dateContext.selectedDate) else { return }
            postSyncRefreshTask?.cancel()
            postSyncRefreshTask = Task { @MainActor in
                try? await Task.sleep(nanoseconds: 30_000_000_000)
                guard !Task.isCancelled else { return }
                await dashboard.load(date: dateContext.selectedDate)
            }
        }
    }

    @ViewBuilder
    private func metricLabel(_ metric: SB_DashboardMetric) -> some View {
        LabeledContent(metric.title ?? metricFallbackTitle(metric.metricType)) {
            Text(formattedValue(metric))
                .foregroundStyle(.primary)
        }
    }

    @ViewBuilder
    private func metricRow(_ metric: SB_DashboardMetric) -> some View {
        switch metric.metricType {
        case .stepDashMetric:
            NavigationLink { StepsDetailView() } label: { metricLabel(metric) }
        case .calorieDashMetric:
            NavigationLink { CaloriesDetailView() } label: { metricLabel(metric) }
        case .hrDashMetric:
            NavigationLink { HRDetailView() } label: { metricLabel(metric) }
        case .hrvDashMetric:
            NavigationLink { HRVDetailView() } label: { metricLabel(metric) }
        case .respRateDashMetric:
            NavigationLink { RRDetailView() } label: { metricLabel(metric) }
        default:
            metricLabel(metric)
        }
    }

    private func metricFallbackTitle(_ type: SB_DashboardMetricType) -> String {
        switch type {
        case .stepDashMetric: return "Steps"
        case .calorieDashMetric: return "Calories"
        case .hrDashMetric: return "Heart Rate"
        case .hrvDashMetric: return "HRV"
        case .respRateDashMetric: return "Respiratory Rate"
        case .spo2DashMetric: return "SpO\u{2082}"
        case .temperatureDashMetric: return "Temperature"
        case .unknown: return "Metric"
            @unknown default:
                return "?"
        }
    }

    private func formattedValue(_ metric: SB_DashboardMetric) -> String {
        let unit = metric.valueUnit ?? ""
        let numberPart: String
        if metric.valueFloat != 0 {
            numberPart = metric.valueFloat.formatted(.number)
        } else {
            numberPart = metric.value.formatted(.number)
        }
        return "\(numberPart) \(unit)".trimmingCharacters(in: .whitespaces)
    }
}
