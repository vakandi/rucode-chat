//
//  ScheduleEditorView.swift
//  RuCode Chat
//
//  Port of EliaTopBar's SchedulePopoverView so both apps configure Bun
//  subworkers the same way: hourly slots, frequent (every N minutes) or cron.
//

import SwiftUI

struct ScheduleEditorView: View {
    let agentName: String
    let photo: Data?
    let schedule: [String: JSONValue]?
    var onSave: ([String: JSONValue]) async throws -> Void

    enum Mode: String, CaseIterable { case hourly = "Hourly", frequent = "Frequent", cron = "Cron" }

    @Environment(\.dismiss) private var dismiss

    @State private var mode: Mode = .hourly
    @State private var selectedHours: Set<Int> = []
    @State private var selectedDays: Set<Int> = []
    @State private var minute: Int = 0
    @State private var everyMinutes: Int = 10
    @State private var restrictHours: Bool = false
    @State private var frequentHours: Set<Int> = Set(9...18)
    @State private var cronExpression: String = "*/10 * * * *"
    @State private var initialLoaded = false
    @State private var saving = false
    @State private var saveError: String?

    private let daySymbols = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]
    private let everyPresets = [5, 10, 15, 20, 30, 45, 60, 120, 240]
    private let minutePresets = [0, 5, 10, 15, 20, 30, 45]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            modePicker
            Divider().opacity(0.5)

            switch mode {
            case .hourly: hourlySection
            case .frequent: frequentSection
            case .cron: cronSection
            }

            summaryBar
            if let saveError {
                Text(saveError).font(.caption).foregroundColor(.red)
            }
        }
        .padding(14)
        .frame(width: 380)
        .onAppear { loadCurrent() }
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 8) {
            if let photo, let image = platformImage(photo) {
                image
                    .resizable()
                    .scaledToFill()
                    .frame(width: 28, height: 28)
                    .clipShape(Circle())
            }
            Text("Schedule — \(agentName)").font(.system(size: 13, weight: .semibold))
            Spacer()
            Button(action: { dismiss() }) {
                Image(systemName: "xmark.circle.fill").foregroundColor(.secondary)
            }
            .buttonStyle(.plain)
        }
    }

    private func platformImage(_ data: Data) -> Image? {
#if os(macOS)
        guard let image = NSImage(data: data) else { return nil }
        return Image(nsImage: image)
#else
        guard let image = UIImage(data: data) else { return nil }
        return Image(uiImage: image)
#endif
    }

    private var modePicker: some View {
        Picker("", selection: $mode) {
            Text("Hourly").tag(Mode.hourly)
            Text("Frequent").tag(Mode.frequent)
            Text("Cron").tag(Mode.cron)
        }
        // Menu, not segmented: NSSegmentedControl inside a hosting view crashes
        // the app on this macOS release (same workaround as EliaTopBar).
        .pickerStyle(.menu)
        .labelsHidden()
    }

    // MARK: - Sections

    private var hourlySection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("At minute").font(.caption).foregroundColor(.secondary)
                Spacer()
                Picker("", selection: $minute) {
                    ForEach(0..<60, id: \.self) { value in
                        Text(String(format: ":%02d", value)).tag(value)
                    }
                }
                .frame(width: 96)
                .labelsHidden()
                Text("past the hour").font(.caption).foregroundColor(.secondary)
            }
            HStack(spacing: 4) {
                ForEach(minutePresets, id: \.self) { value in
                    Button(String(format: ":%02d", value)) { minute = value }
                        .buttonStyle(.bordered)
                        .controlSize(.mini)
                        .tint(minute == value ? .accentColor : nil)
                }
            }
            dayHoursControls(hours: $selectedHours, days: $selectedDays)
            Text("Hours").font(.caption).foregroundColor(.secondary)
            hourGrid(selection: $selectedHours)
        }
    }

    private var frequentSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Every").font(.caption).foregroundColor(.secondary)
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 5), spacing: 6) {
                ForEach(everyPresets, id: \.self) { value in
                    Button(action: { everyMinutes = value }) {
                        Text(labelForEvery(value))
                            .font(.system(size: 11, weight: .medium))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 6)
                            .background(everyMinutes == value ? Color.accentColor : chipOffColor)
                            .foregroundColor(everyMinutes == value ? .white : .primary)
                            .cornerRadius(6)
                    }
                    .buttonStyle(.plain)
                }
            }
            HStack(spacing: 8) {
                Text("Custom:").font(.caption).foregroundColor(.secondary)
                Stepper(value: $everyMinutes, in: 1...1440, step: 1) {
                    Text("\(everyMinutes) min").font(.caption.monospacedDigit())
                }
                .frame(maxWidth: 160)
                Spacer()
            }
            Toggle("Restrict to hours", isOn: $restrictHours)
                .font(.caption)
                .toggleStyle(.switch)
                .scaleEffect(0.8)
            if restrictHours {
                hourGrid(selection: $frequentHours)
                HStack(spacing: 6) {
                    quickButton("9–18") { frequentHours = Set(9...18) }
                    quickButton("All") { frequentHours = Set(0...23) }
                    quickButton("None") { frequentHours = [] }
                }
            }
            Text("Days").font(.caption).foregroundColor(.secondary)
            HStack(spacing: 4) {
                ForEach(0..<7, id: \.self) { day in dayChip(day, selection: $selectedDays) }
            }
            HStack(spacing: 6) {
                presetButton("Every day") { selectedDays = [] }
                presetButton("Weekdays") { selectedDays = [1, 2, 3, 4, 5] }
                presetButton("Weekend") { selectedDays = [0, 6] }
            }
        }
    }

    private var cronSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Cron expression (5 fields: minute hour day month weekday)")
                .font(.caption)
                .foregroundColor(.secondary)
            TextField("*/10 * * * *", text: $cronExpression)
                .textFieldStyle(.roundedBorder)
                .font(.system(size: 12, design: .monospaced))
                .autocorrectionDisabled()
            if !isCronValid {
                Text("Invalid cron — needs 5 fields, e.g. \"*/15 * * * *\"")
                    .font(.caption)
                    .foregroundColor(.red)
            }
            Text("Presets").font(.caption).foregroundColor(.secondary)
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 3), spacing: 6) {
                cronPreset("Every 5m", "*/5 * * * *")
                cronPreset("Every 10m", "*/10 * * * *")
                cronPreset("Every 15m", "*/15 * * * *")
                cronPreset("Every 20m", "*/20 * * * *")
                cronPreset("Every 30m", "*/30 * * * *")
                cronPreset("Every 45m", "0,45 * * * *")
                cronPreset("Hourly :00", "0 * * * *")
                cronPreset("Daily 09:00", "0 9 * * *")
                cronPreset("Weekdays 9:00", "0 9 * * 1-5")
            }
            Text("Tip: presets with weekdays set the last cron field automatically.")
                .font(.caption2)
                .foregroundColor(.secondary)
        }
    }

    private var summaryBar: some View {
        VStack(spacing: 6) {
            HStack {
                Text(summary)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(2)
                Spacer()
                Button("Cancel") { dismiss() }
                    .controlSize(.small)
                if saving {
                    ProgressView().scaleEffect(0.6)
                }
                Button("Save") { save() }
                    .buttonStyle(.borderedProminent)
                    .disabled(!canSave)
            }
            if let nextRunPreview {
                Text("Next: \(nextRunPreview)").font(.caption2).foregroundColor(.secondary)
            }
        }
    }

    // MARK: - Helpers

    private var chipOffColor: Color {
#if os(macOS)
        Color(nsColor: .quaternaryLabelColor)
#else
        Color(uiColor: .quaternaryLabel)
#endif
    }

    private func labelForEvery(_ value: Int) -> String {
        if value < 60 { return "\(value)m" }
        if value == 60 { return "60m" }
        return "\(value / 60)h"
    }

    private var isCronValid: Bool {
        let parts = cronExpression.split(separator: " ")
        return parts.count == 5 && !cronExpression.trimmingCharacters(in: .whitespaces).isEmpty
    }

    private var canSave: Bool {
        if saving { return false }
        switch mode {
        case .hourly: return !selectedHours.isEmpty
        case .frequent:
            if restrictHours && frequentHours.isEmpty { return false }
            return everyMinutes >= 1
        case .cron: return isCronValid
        }
    }

    private var summary: String {
        switch mode {
        case .hourly:
            guard !selectedHours.isEmpty else { return "No hours selected" }
            let hours = selectedHours.sorted()
            let pad = { (value: Int) in String(format: "%02d", value) }
            let label = hours.count == 24
                ? "every hour at :\(pad(minute))"
                : "\(pad(hours.first!)):\(pad(minute)) → \(pad(hours.last!)):\(pad(minute)), \(hours.count)×/day"
            return "\(label) · \(daysLabel)"
        case .frequent:
            let hoursPart: String
            if restrictHours {
                if frequentHours.isEmpty { hoursPart = "no hours" }
                else if frequentHours.count == 24 { hoursPart = "all hours" }
                else { hoursPart = "\(frequentHours.count) hours" }
            } else {
                hoursPart = "all hours"
            }
            if restrictHours && !frequentHours.isEmpty {
                let estimate = frequentHours.count * 60 / max(everyMinutes, 1)
                return "Every \(everyMinutes)m · ~\(estimate)×/day · \(hoursPart) · \(daysLabel)"
            }
            let total = 1440 / max(everyMinutes, 1)
            return "Every \(everyMinutes)m · ~\(total)×/day · \(hoursPart) · \(daysLabel)"
        case .cron:
            return "Cron: \(cronExpression) · \(daysLabel)"
        }
    }

    private var daysLabel: String {
        if selectedDays.isEmpty { return "every day" }
        if selectedDays == [1, 2, 3, 4, 5] { return "weekdays only" }
        if selectedDays == [0, 6] { return "weekends only" }
        return selectedDays.sorted().map { daySymbols[$0] }.joined(separator: " ")
    }

    private var nextRunPreview: String? {
        switch mode {
        case .frequent: return "every \(everyMinutes) min\(restrictHours ? " in selected hours" : "")"
        case .hourly:
            guard let hour = selectedHours.sorted().first else { return nil }
            return String(format: "next ~%02d:%02d", hour, minute)
        case .cron: return cronExpression
        }
    }

    private func dayHoursControls(hours: Binding<Set<Int>>, days: Binding<Set<Int>>) -> some View {
        VStack(spacing: 6) {
            HStack(spacing: 6) {
                presetButton("Every day") { days.wrappedValue = [] }
                presetButton("Weekdays") { days.wrappedValue = [1, 2, 3, 4, 5] }
                presetButton("Weekend") { days.wrappedValue = [0, 6] }
                Spacer()
                quickButton("9h–18h") { hours.wrappedValue = Set(9...18) }
                quickButton("All") { hours.wrappedValue = Set(0...23) }
                quickButton("None") { hours.wrappedValue = [] }
            }
            Text("Days").font(.caption).foregroundColor(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
            HStack(spacing: 4) {
                ForEach(0..<7, id: \.self) { day in dayChip(day, selection: days) }
            }
        }
    }

    private func hourGrid(selection: Binding<Set<Int>>) -> some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 4), count: 6), spacing: 4) {
            ForEach(0..<24, id: \.self) { hour in
                let on = selection.wrappedValue.contains(hour)
                Button(action: {
                    if on { selection.wrappedValue.remove(hour) }
                    else { selection.wrappedValue.insert(hour) }
                }) {
                    Text(String(format: "%02d", hour))
                        .font(.system(size: 11, design: .monospaced))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 4)
                        .background(on ? Color.accentColor : chipOffColor)
                        .foregroundColor(on ? .white : .primary)
                        .cornerRadius(5)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func dayChip(_ day: Int, selection: Binding<Set<Int>>) -> some View {
        let on = selection.wrappedValue.contains(day)
        return Button(action: {
            if on { selection.wrappedValue.remove(day) }
            else { selection.wrappedValue.insert(day) }
        }) {
            Text(daySymbols[day])
                .font(.system(size: 10, weight: .medium))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 4)
                .background(on ? Color.accentColor.opacity(0.85) : chipOffColor)
                .foregroundColor(on ? .white : .secondary)
                .cornerRadius(5)
        }
        .buttonStyle(.plain)
    }

    private func presetButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button(title) { action() }.controlSize(.small).buttonStyle(.bordered)
    }

    private func quickButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button(title) { action() }.controlSize(.small).buttonStyle(.borderless).font(.caption)
    }

    private func cronPreset(_ title: String, _ expression: String) -> some View {
        Button(title) { cronExpression = expression }
            .font(.system(size: 10))
            .buttonStyle(.bordered)
            .controlSize(.mini)
            .tint(cronExpression == expression ? .accentColor : nil)
    }

    // MARK: - Load / save

    private func loadCurrent() {
        guard !initialLoaded else { return }
        initialLoaded = true
        guard let schedule else { return }

        switch Self.string(schedule["type"]) {
        case "cron":
            mode = .cron
            cronExpression = Self.string(schedule["expression"]) ?? cronExpression
        case "every":
            mode = .frequent
            everyMinutes = Self.int(schedule["every"]) ?? everyMinutes
            selectedDays = Self.intSet(schedule["days"])
            let hours = Self.intSet(schedule["hours"])
            if hours.isEmpty {
                restrictHours = false
            } else {
                restrictHours = true
                frequentHours = hours
            }
        default:
            mode = .hourly
            selectedHours = Self.intSet(schedule["hours"])
            minute = Self.int(schedule["minute"]) ?? 0
            selectedDays = Self.intSet(schedule["days"])
        }
    }

    private func save() {
        saving = true
        saveError = nil
        let payload = schedulePayload()
        Task {
            do {
                try await onSave(payload)
                saving = false
                dismiss()
            } catch {
                saving = false
                saveError = "Save failed: \(error.localizedDescription)"
            }
        }
    }

    private func schedulePayload() -> [String: JSONValue] {
        let days: JSONValue = selectedDays.isEmpty
            ? .null
            : .array(selectedDays.sorted().map { .number(Double($0)) })

        switch mode {
        case .hourly:
            return [
                "type": .string("interval"),
                "hours": .array(selectedHours.sorted().map { .number(Double($0)) }),
                "minute": .number(Double(minute)),
                "days": days,
            ]
        case .frequent:
            var payload: [String: JSONValue] = [
                "type": .string("every"),
                "every": .number(Double(everyMinutes)),
                "days": days,
            ]
            if restrictHours {
                payload["hours"] = .array(frequentHours.sorted().map { .number(Double($0)) })
            }
            return payload
        case .cron:
            return ["type": .string("cron"), "expression": .string(cronExpression)]
        }
    }

    // MARK: - JSON helpers

    private static func string(_ value: JSONValue?) -> String? {
        if case .string(let value)? = value { return value }
        return nil
    }

    private static func int(_ value: JSONValue?) -> Int? {
        if case .number(let value)? = value { return Int(value) }
        return nil
    }

    private static func intSet(_ value: JSONValue?) -> Set<Int> {
        guard case .array(let items)? = value else { return [] }
        return Set(items.compactMap { item in
            if case .number(let value) = item { return Int(value) }
            return nil
        })
    }

    /// One-line description used by the settings row before the sheet opens.
    static func summary(_ schedule: [String: JSONValue]?) -> String {
        guard let schedule else { return "not set" }
        switch string(schedule["type"]) {
        case "cron":
            return "cron · \(string(schedule["expression"]) ?? "?")"
        case "every":
            let every = int(schedule["every"]) ?? 0
            return "every \(every)m"
        case "interval":
            let hours = intSet(schedule["hours"])
            let minute = int(schedule["minute"]) ?? 0
            let days = intSet(schedule["days"])
            let dayLabel = days.isEmpty ? "every day" : "\(days.count) days"
            return String(format: "%d hours at :%02d · %@", hours.count, minute, dayLabel)
        default:
            return "not set"
        }
    }
}
