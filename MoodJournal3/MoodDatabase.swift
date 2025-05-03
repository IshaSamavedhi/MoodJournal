import Foundation
import SQLite3
import FirebaseFirestore

/// Holds the aggregate statistics for a report
struct ReportStats {
    var totalCount: Int
    var moodCounts: [String: Int]
    var mostCommonMood: String?
    var averageNoteLength: Double
}

class MoodDatabase {
    private var db: OpaquePointer?

    init() {
        openDatabase()
        createMoodOptionTable()
        createMoodEntryTable()
        insertDefaultMoods()
        createIndexes()
        createStatsView()
    }

    // MARK: - Database Setup

    private func openDatabase() {
        let fileURL = try! FileManager.default
            .url(for: .documentDirectory,
                 in: .userDomainMask,
                 appropriateFor: nil,
                 create: false)
            .appendingPathComponent("moods.sqlite")

        // Debug print:
        print("🗄️ SQLite DB path: \(fileURL.path)")

        if sqlite3_open(fileURL.path, &db) != SQLITE_OK {
            print("Error opening database at \(fileURL.path)")
        }
    }


    private func createMoodOptionTable() {
        let sql = """
        CREATE TABLE IF NOT EXISTS MoodOption(
          id   INTEGER PRIMARY KEY AUTOINCREMENT,
          name TEXT UNIQUE
        );
        """
        exec(sql)
    }

    private func createMoodEntryTable() {
        let sql = """
        CREATE TABLE IF NOT EXISTS MoodEntry(
          id       TEXT PRIMARY KEY,
          date     REAL,
          mood     TEXT,
          note     TEXT,
          user_id  TEXT
        );
        """
        exec(sql)
    }

    private func exec(_ sql: String) {
        var stmt: OpaquePointer?
        if sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK {
            if sqlite3_step(stmt) != SQLITE_DONE {
                print("Could not exec: \(sql)")
            }
        } else {
            print("Could not prepare: \(sql)")
        }
        sqlite3_finalize(stmt)
    }

    // MARK: - MoodOption CRUD

    private func insertDefaultMoods() {
        let defaults = ["Happy","Sad","Anxious","Excited","Tired"]
        for mood in defaults {
            if !moodExists(mood) {
                insertMood(mood)
            }
        }
    }

    private func moodExists(_ mood: String) -> Bool {
        let sql = "SELECT 1 FROM MoodOption WHERE name = ? LIMIT 1;"
        var stmt: OpaquePointer?
        var exists = false

        if sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK {
            sqlite3_bind_text(stmt, 1, (mood as NSString).utf8String, -1, nil)
            if sqlite3_step(stmt) == SQLITE_ROW {
                exists = true
            }
        }
        sqlite3_finalize(stmt)
        return exists
    }

    func insertMood(_ mood: String) {
        let sql = "INSERT OR IGNORE INTO MoodOption(name) VALUES(?);"
        var stmt: OpaquePointer?
        if sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK {
            sqlite3_bind_text(stmt, 1, (mood as NSString).utf8String, -1, nil)
            sqlite3_step(stmt)
        }
        sqlite3_finalize(stmt)
    }

    func fetchMoods() -> [String] {
        let sql = "SELECT name FROM MoodOption ORDER BY name;"
        var stmt: OpaquePointer?
        var results = [String]()

        if sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK {
            while sqlite3_step(stmt) == SQLITE_ROW {
                if let c = sqlite3_column_text(stmt, 0) {
                    results.append(String(cString: c))
                }
            }
        }
        sqlite3_finalize(stmt)
        return results
    }

    func deleteMood(_ mood: String) {
        let sql = "DELETE FROM MoodOption WHERE name = ?;"
        var stmt: OpaquePointer?
        if sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK {
            sqlite3_bind_text(stmt, 1, (mood as NSString).utf8String, -1, nil)
            sqlite3_step(stmt)
        }
        sqlite3_finalize(stmt)
    }

    // MARK: - MoodEntry Sync & CRUD

    func clearEntries() {
        exec("DELETE FROM MoodEntry;")
    }

    func insertEntry(_ entry: MoodEntry) {
        let sql = """
        INSERT OR REPLACE INTO MoodEntry(id, date, mood, note, user_id)
        VALUES(?,?,?,?,?);
        """
        var stmt: OpaquePointer?
        if sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK {
            sqlite3_bind_text(stmt, 1, (entry.id as NSString).utf8String, -1, nil)
            sqlite3_bind_double(stmt, 2, entry.date.timeIntervalSince1970)
            sqlite3_bind_text(stmt, 3, (entry.mood as NSString).utf8String, -1, nil)
            sqlite3_bind_text(stmt, 4, (entry.note as NSString).utf8String, -1, nil)
            sqlite3_bind_text(stmt, 5, (entry.id as NSString).utf8String, -1, nil) // user_id not used here
            sqlite3_step(stmt)
        }
        sqlite3_finalize(stmt)
    }

    /// Pulls down all moodEntries from Firestore into the local SQLite table
    func syncEntriesFromFirestore(completion: @escaping ()->Void) {
        let dbFs = Firestore.firestore()
        dbFs.collection("moodEntries").getDocuments { snapshot, error in
            guard let docs = snapshot?.documents else {
                completion(); return
            }
            self.clearEntries()
            for doc in docs {
                let data = doc.data()
                let id   = doc.documentID
                let date = (data["date"] as? Timestamp)?.dateValue() ?? Date()
                let mood = data["mood"] as? String ?? ""
                let note = data["note"] as? String ?? ""
                let entry = MoodEntry(id: id, date: date, mood: mood, note: note)
                self.insertEntry(entry)
            }
            completion()
        }
    }

    // MARK: - Reporting Queries (Prepared Statements)

    func queryEntries(from: Date, to: Date, mood: String?) -> [MoodEntry] {
        var sql = """
        SELECT id, date, mood, note FROM MoodEntry
        WHERE date BETWEEN ? AND ?
        """
        if let _ = mood {
            sql += " AND mood = ?"
        }
        sql += " ORDER BY date DESC;"

        var stmt: OpaquePointer?
        var results = [MoodEntry]()
        if sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK {
            sqlite3_bind_double(stmt, 1, from.timeIntervalSince1970)
            sqlite3_bind_double(stmt, 2, to.timeIntervalSince1970)
            if let mood = mood {
                sqlite3_bind_text(stmt, 3, (mood as NSString).utf8String, -1, nil)
            }
            while sqlite3_step(stmt) == SQLITE_ROW {
                let id   = String(cString: sqlite3_column_text(stmt, 0))
                let d    = sqlite3_column_double(stmt, 1)
                let mood = String(cString: sqlite3_column_text(stmt, 2))
                let note = String(cString: sqlite3_column_text(stmt, 3))
                results.append(MoodEntry(id: id,
                                         date: Date(timeIntervalSince1970: d),
                                         mood: mood,
                                         note: note))
            }
        }
        sqlite3_finalize(stmt)
        return results
    }

    func computeStats(from: Date, to: Date) -> ReportStats {
        // 1) total count
        let all = queryEntries(from: from, to: to, mood: nil)
        let total = all.count

        // 2) mood counts
        var counts = [String:Int]()
        for e in all { counts[e.mood, default:0] += 1 }
        let most = counts.max { $0.value < $1.value }?.key

        // 3) average note length
        let avgLen: Double
        if total > 0 {
            let sum = all.reduce(0) { $0 + $1.note.count }
            avgLen = Double(sum) / Double(total)
        } else {
            avgLen = 0
        }

        return ReportStats(totalCount: total,
                           moodCounts: counts,
                           mostCommonMood: most,
                           averageNoteLength: avgLen)
    }
    
    private func createIndexes() {
      exec("CREATE INDEX IF NOT EXISTS idx_moodentry_date ON MoodEntry(date);")
      exec("CREATE INDEX IF NOT EXISTS idx_moodentry_mood ON MoodEntry(mood);")
    }

    
    private func createStatsView() {
        let sql = """
        CREATE VIEW IF NOT EXISTS MoodEntryStats AS
          SELECT
            mood,
            COUNT(*)             AS entryCount,
            AVG(LENGTH(note))    AS avgNoteLength
          FROM MoodEntry
          GROUP BY mood;
        """
        exec(sql)
    }
    
    func fetchMoodEntryStats() -> [String: (count: Int, avgNoteLen: Double)] {
        let sql = "SELECT mood, entryCount, avgNoteLength FROM MoodEntryStats;"
        var stmt: OpaquePointer?
        var result = [String:(Int,Double)]()

        if sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK {
            while sqlite3_step(stmt) == SQLITE_ROW {
                let mood = String(cString: sqlite3_column_text(stmt, 0))
                let count = Int(sqlite3_column_int(stmt, 1))
                let avgLen = sqlite3_column_double(stmt, 2)
                result[mood] = (count, avgLen)
            }
        }
        sqlite3_finalize(stmt)
        return result
    }



}
