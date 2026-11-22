import Charts
import SwiftUI

struct ReadingRecordsView: View {
    @EnvironmentObject private var session: AppSession
    @State private var books: [ShelfItem] = []
    @State private var records: [ReadingRecordItem] = []
    @State private var statistics: ReadingStatistics?
    @State private var period = "WEEK"
    @State private var editor: RecordEditorItem?
    @State private var error: String?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    Picker("통계 기간", selection: $period) {
                        Text("이번 주").tag("WEEK")
                        Text("이번 달").tag("MONTH")
                    }
                    .pickerStyle(.segmented)

                    if let error {
                        Text(error).foregroundStyle(BookuhTheme.wine)
                        Button("다시 불러오기") { Task { await load() } }
                    }
                    if let statistics, statistics.period == period {
                        statisticsCard(statistics)
                    } else if error == nil {
                        ProgressView("독서 통계를 불러오고 있어요")
                    }

                    Text("기록").font(BookuhTheme.titleFont(size: 20))
                    if records.isEmpty {
                        Text("아직 독서 기록이 없어요").foregroundStyle(BookuhTheme.inkSoft)
                    }
                    ForEach(records) { record in
                        Button {
                            editor = RecordEditorItem(record: record)
                        } label: {
                            VStack(alignment: .leading, spacing: 7) {
                                Text(record.title).font(BookuhTheme.emphasizedFont())
                                Text(recordSummary(record)).font(BookuhTheme.bodyFont(size: 13))
                                    .foregroundStyle(BookuhTheme.inkSoft)
                            }
                            .foregroundStyle(BookuhTheme.ink)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(14)
                            .background(BookuhTheme.card,
                                        in: RoundedRectangle(cornerRadius: BookuhTheme.cornerRadius))
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(BookuhTheme.screenPadding)
            }
            .background(BookuhTheme.paper.ignoresSafeArea())
            .navigationTitle("독서 기록")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("기록 추가", systemImage: "plus") { editor = RecordEditorItem(record: nil) }
                        .disabled(books.isEmpty)
                }
            }
            .modifier(ManagerChatEntry(books: books, initialBook: nil))
            .sheet(item: $editor) { item in
                ReadingRecordEditor(books: books, record: item.record)
            }
            .task(id: period) { await load() }
            .refreshable { await load() }
            .onReceive(NotificationCenter.default.publisher(for: .bookuhRecordsChanged)) { _ in
                Task { await load() }
            }
        }
    }

    private func statisticsCard(_ stats: ReadingStatistics) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("총 독서 시간").font(BookuhTheme.emphasizedFont())
            Text(stats.durationMinutes.map(formatReadingMinutes) ?? "기록 없음")
                .font(BookuhTheme.titleFont(size: 28))
            readingTimeChart(stats)
            LabeledContent("읽은 페이지", value: stats.pagesRead.map { "\($0)쪽" } ?? "기록 없음")
            LabeledContent("독서한 날", value: "\(stats.readingDayCount)일")
            LabeledContent("완독", value: "\(stats.finishedBookCount)권")
            let total = stats.dayMinutes + stats.nightMinutes
            LabeledContent("낮 · 밤", value: total == 0 ? "기록 없음"
                           : "\(Int(100 * Double(stats.dayMinutes) / Double(total)))% · \(Int((100 * Double(stats.nightMinutes) / Double(total)).rounded(.up)))%")
            if total > 0 {
                Text("시간대를 기록한 독서 시간을 기준으로 계산해요.")
                    .font(BookuhTheme.bodyFont(size: 12))
                    .foregroundStyle(BookuhTheme.inkSoft)
            }
        }
        .font(BookuhTheme.bodyFont(size: 14))
        .padding(16)
        .background(BookuhTheme.card, in: RoundedRectangle(cornerRadius: BookuhTheme.cornerRadius))
    }

    private func readingTimeChart(_ stats: ReadingStatistics) -> some View {
        let weekly = stats.period == "WEEK"
        let unit = weekly ? "요일별" : "주차별"
        let weekdays = ["월", "화", "수", "목", "금", "토", "일"]
        let dates = stats.buckets.map(\.startDate)

        return VStack(alignment: .leading, spacing: 8) {
            LabeledContent(unit, value: dateRange(from: stats.startDate, to: stats.endDateExclusive))
                .font(BookuhTheme.bodyFont(size: 13))
                .foregroundStyle(BookuhTheme.inkSoft)

            Chart(stats.buckets) { point in
                BarMark(x: .value("시작일", point.startDate),
                        y: .value("독서 시간", point.durationMinutes ?? 0))
                    .foregroundStyle(BookuhTheme.green)
                    .accessibilityLabel(Text(dateRange(from: point.startDate, to: point.endDateExclusive)))
                    .accessibilityValue(Text(point.durationMinutes.map(formatReadingMinutes) ?? "기록 없음"))
            }
            .chartXScale(domain: dates)
            .chartXAxis {
                AxisMarks(values: dates) { value in
                    AxisGridLine()
                    if let date = value.as(String.self), let index = dates.firstIndex(of: date) {
                        AxisValueLabel(anchor: .top, collisionResolution: .disabled) {
                            VStack(spacing: 2) {
                                Text(weekly ? weekdays[index] : "\(index + 1)주차")
                                    .foregroundStyle(BookuhTheme.ink)
                                if !weekly {
                                    Text(dateRange(from: date, to: stats.buckets[index].endDateExclusive,
                                                   showMonth: false))
                                        .foregroundStyle(BookuhTheme.inkSoft)
                                }
                            }
                            .font(.caption2)
                        }
                    }
                }
            }
            .frame(height: 150)
            .accessibilityLabel("\(unit) 독서 시간 그래프")
        }
    }

    private func dateRange(from startDate: String, to endDateExclusive: String, showMonth: Bool = true) -> String {
        let format = Date.ISO8601FormatStyle(dateSeparator: .dash, timeZone: .gmt).year().month().day()
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .gmt
        guard let start = try? format.parse(startDate),
              let nextDay = try? format.parse(endDateExclusive),
              let end = calendar.date(byAdding: .day, value: -1, to: nextDay) else {
            return startDate
        }
        let startMonth = calendar.component(.month, from: start)
        let endMonth = calendar.component(.month, from: end)
        let startDay = calendar.component(.day, from: start)
        let endDay = calendar.component(.day, from: end)
        let first = showMonth || startMonth != endMonth ? "\(startMonth)월 \(startDay)일" : "\(startDay)"
        if start == end { return showMonth ? first : "\(first)일" }
        let last = startMonth == endMonth ? "\(endDay)일" : "\(endMonth)월 \(endDay)일"
        return "\(first)–\(last)"
    }

    @MainActor
    private func load() async {
        guard let token = session.accessToken else { return }
        let selectedPeriod = period
        do {
            let api = BookuhAPI()
            let result: ReadingStatistics = try await api.feature(
                "reading-stats", token: token, query: [
                    .init(name: "period", value: selectedPeriod),
                    .init(name: "timeZone", value: TimeZone.current.identifier)
                ]
            )
            let response: FeatureItems<ReadingRecordItem> = try await api.feature("reading-records", token: token)
            let shelf = try await api.fetchBookshelf(accessToken: token)
            guard !Task.isCancelled, period == selectedPeriod else { return }
            statistics = result
            records = response.items
            books = shelf
            error = nil
        } catch {
            if !Task.isCancelled, period == selectedPeriod { self.error = error.localizedDescription }
        }
    }
}

private struct RecordEditorItem: Identifiable {
    let id = UUID()
    let record: ReadingRecordItem?
}

private struct ReadingRecordEditor: View {
    @EnvironmentObject private var session: AppSession
    @Environment(\.dismiss) private var dismiss
    let books: [ShelfItem]
    let record: ReadingRecordItem?

    @State private var isbn = ""
    @State private var day = Date()
    @State private var band = ""
    @State private var minutes = ""
    @State private var pages = ""
    @State private var actionId = UUID().uuidString
    @State private var isSaving = false
    @State private var pendingId: String?
    @State private var confirmDelete = false
    @State private var error: String?

    var body: some View {
        NavigationStack {
            Form {
                if record == nil {
                    Picker("책", selection: $isbn) {
                        ForEach(books) { Text($0.title).tag($0.isbn) }
                    }
                } else if let record {
                    LabeledContent("책", value: record.title)
                }
                DatePicker("읽은 날", selection: $day, displayedComponents: .date)
                Picker("시간대", selection: $band) {
                    Text("기록 안 함").tag("")
                    Text("낮 (06:00–17:59)").tag("DAY")
                    Text("밤 (18:00–05:59)").tag("NIGHT")
                }
                TextField("독서 시간 (분)", text: $minutes).keyboardType(.numberPad)
                TextField("읽은 페이지 (쪽)", text: $pages).keyboardType(.numberPad)

                if let error { Text(error).foregroundStyle(BookuhTheme.wine) }
                if pendingId != nil {
                    Text("같은 날에 같은 독서량을 기록했어요. 새로 읽은 기록인가요?")
                    Button("추가로 기록하기") { Task { await decide("ADD") } }.disabled(isSaving)
                    Button("추가 취소") { Task { await decide("CANCEL") } }.disabled(isSaving)
                } else {
                    Button(isSaving ? "저장 중" : "저장") { Task { await save() } }
                        .disabled(isSaving || isbn.isEmpty || (minutes.isEmpty && pages.isEmpty))
                    if record != nil {
                        Button("기록 삭제", role: .destructive) { confirmDelete = true }.disabled(isSaving)
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(BookuhTheme.paper)
            .navigationTitle(record == nil ? "독서 기록 추가" : "독서 기록 수정")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("닫기") { dismiss() }.disabled(isSaving)
                }
            }
        }
        .confirmationDialog("이 독서 기록을 삭제할까요?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("삭제", role: .destructive) { Task { await delete() } }
            Button("취소", role: .cancel) {}
        } message: {
            if let record { Text("\(record.title) · \(recordSummary(record))") }
        }
        .task {
            isbn = record?.isbn ?? books.first?.isbn ?? ""
            if let record {
                day = recordDayFormatter.date(from: record.readingDate) ?? Date()
                band = record.timeBand ?? ""
                minutes = record.durationMinutes.map(String.init) ?? ""
                pages = record.pagesRead.map(String.init) ?? ""
            }
        }
        .onChange(of: isbn) { _, _ in resetRequest() }
        .onChange(of: day) { _, _ in resetRequest() }
        .onChange(of: band) { _, _ in resetRequest() }
        .onChange(of: minutes) { _, _ in resetRequest() }
        .onChange(of: pages) { _, _ in resetRequest() }
    }

    private func resetRequest() {
        actionId = UUID().uuidString
        error = nil
    }

    @MainActor
    private func run(_ operation: (String) async throws -> Void) async {
        guard !isSaving, let token = session.accessToken else { return }
        isSaving = true
        error = nil
        defer { isSaving = false }
        do { try await operation(token) } catch { self.error = error.localizedDescription }
    }

    private func finished() {
        NotificationCenter.default.post(name: .bookuhRecordsChanged, object: nil)
        dismiss()
    }

    private func save() async {
        await run { token in
            let duration = Int(minutes)
            let pageCount = Int(pages)
            guard minutes.isEmpty || (duration ?? 0) > 0,
                  pages.isEmpty || (pageCount ?? 0) > 0 else {
                error = "시간과 페이지는 1 이상의 숫자로 입력해 주세요."
                return
            }
            var body: [String: Any] = [
                "readingDate": recordDayFormatter.string(from: day),
                "timeBand": band.isEmpty ? NSNull() as Any : band,
                "durationMinutes": duration.map { $0 as Any } ?? NSNull(),
                "pagesRead": pageCount.map { $0 as Any } ?? NSNull()
            ]
            let api = BookuhAPI()
            if let record {
                let _: ReadingRecordItem = try await api.feature(
                    "reading-records/\(record.id)", token: token, method: "PATCH", body: body)
                finished()
            } else {
                body["actionId"] = actionId
                body["isbn"] = isbn
                body["additionIntent"] = "UNSPECIFIED"
                let result: ReadingRecordResult = try await api.feature(
                    "reading-records", token: token, method: "POST", body: body)
                if result.status == "NEEDS_CONFIRMATION" {
                    pendingId = result.pendingId
                } else {
                    finished()
                }
            }
        }
    }

    private func decide(_ decision: String) async {
        await run { token in
            guard let pendingId else { return }
            let _: ReadingRecordResult = try await BookuhAPI().feature(
                "reading-records/pending/\(pendingId)/decision", token: token,
                method: "POST", body: ["decision": decision])
            finished()
        }
    }

    private func delete() async {
        await run { token in
            guard let record else { return }
            let _: EmptyFeatureResponse = try await BookuhAPI().feature(
                "reading-records/\(record.id)", token: token, method: "DELETE")
            finished()
        }
    }
}

private var recordDayFormatter: DateFormatter {
    let formatter = DateFormatter()
    formatter.calendar = Calendar(identifier: .gregorian)
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.dateFormat = "yyyy-MM-dd"
    return formatter
}

func formatReadingMinutes(_ minutes: Int) -> String {
    if minutes < 60 { return "\(minutes)분" }
    return minutes % 60 == 0 ? "\(minutes / 60)시간" : "\(minutes / 60)시간 \(minutes % 60)분"
}

func recordSummary(_ record: ReadingRecordItem) -> String {
    [record.readingDate, record.durationMinutes.map(formatReadingMinutes),
     record.pagesRead.map { "\($0)쪽" }].compactMap { $0 }.joined(separator: " · ")
}
