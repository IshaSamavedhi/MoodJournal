import SwiftUI

struct ReportView: View {
    @State private var startDate: Date = Calendar.current.date(byAdding: .day, value: -7, to: Date()) ?? Date()
    @State private var endDate: Date   = Date()
    @State private var selectedMood: String = ""
    @State private var moodOptions: [String] = []
    @State private var entries: [MoodEntry] = []
    @State private var stats: ReportStats?
    @State private var statsByMood: [String:(count: Int, avgNoteLen: Double)] = [:]

    private let moodDB = MoodDatabase()

    var body: some View {
        VStack(spacing: 16) {
            Text("📊 Mood Report")
                .font(.title2)
                .padding(.top)

            Form {
                DatePicker("Start Date", selection: $startDate, displayedComponents: .date)
                DatePicker("End Date",   selection: $endDate,   displayedComponents: .date)

                Picker("Mood Filter", selection: $selectedMood) {
                    Text("All").tag("")
                    ForEach(moodOptions, id: \.self) { mood in
                        Text(mood).tag(mood)
                    }
                }
            }
            .frame(height: 200)

            Button("Run Report") {
                moodDB.syncEntriesFromFirestore {
                    // 1) fetch entries
                    self.entries = moodDB.queryEntries(
                        from: startDate,
                        to:   endDate,
                        mood: selectedMood.isEmpty ? nil : selectedMood
                    )
                    // 2) compute aggregated stats
                    self.stats = moodDB.computeStats(from: startDate, to: endDate)
                    // 3) fetch per-mood stats from your VIEW
                    self.statsByMood = moodDB.fetchMoodEntryStats()
                }
            }
            .padding()
            .background(Color.pink.opacity(0.8))
            .foregroundColor(.white)
            .cornerRadius(8)

            // Overall stats
            if let s = stats {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Total Entries: \(s.totalCount)")
                    Text("Most Common Mood: \(s.mostCommonMood ?? "—")")
                    Text(String(format: "Avg. Note Length: %.1f", s.averageNoteLength))
                }
                .padding()
                .background(Color.white)
                .cornerRadius(10)
                .shadow(radius: 2)
            }

            // ✅ Per-mood stats from the VIEW
            if !statsByMood.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(statsByMood.sorted(by: { $0.key < $1.key }), id: \.key) { mood, tuple in
                        Text("\(mood): \(tuple.count) entries, avg note length \(String(format: "%.1f", tuple.avgNoteLen))")
                    }
                }
                .padding()
                .background(Color.white)
                .cornerRadius(10)
                .shadow(radius: 2)
            }

            // Detailed entry list
            List(entries) { entry in
                VStack(alignment: .leading) {
                    Text(entry.mood).font(.headline)
                    Text(entry.note).font(.subheadline)
                    Text(entry.date, style: .date).font(.caption)
                }
                .padding(.vertical, 4)
            }
        }
        .onAppear {
            self.moodOptions = moodDB.fetchMoods()
        }
        .navigationTitle("Report")
    }
}
