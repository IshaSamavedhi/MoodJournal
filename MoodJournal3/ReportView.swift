import SwiftUI

struct ReportView: View {
    @State private var startDate: Date = Calendar.current.date(byAdding: .day, value: -7, to: Date()) ?? Date()
    @State private var endDate: Date   = Date()
    @State private var selectedMood: String = ""
    @State private var moodOptions: [String] = []
    @State private var entries: [MoodEntry] = []
    @State private var stats: ReportStats?

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
                    self.entries = moodDB.queryEntries(
                        from: startDate,
                        to:   endDate,
                        mood: selectedMood.isEmpty ? nil : selectedMood
                    )
                    self.stats = moodDB.computeStats(
                        from: startDate,
                        to:   endDate
                    )
                }
            }
            .padding()
            .background(Color.pink.opacity(0.8))
            .foregroundColor(.white)
            .cornerRadius(8)

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
