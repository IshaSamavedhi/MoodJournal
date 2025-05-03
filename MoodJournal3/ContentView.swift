//
//  ContentView.swift
//  MoodJournal3
//
//  Created by Ishwarya Samavedhi on 3/31/25.
//

import SwiftUI
import FirebaseCore
import FirebaseFirestore
import FirebaseAppCheck

class AppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        FirebaseApp.configure()

        #if DEBUG
        let providerFactory = AppCheckDebugProviderFactory()
        AppCheck.setAppCheckProviderFactory(providerFactory)
        #endif

        return true
    }
}

struct ContentView: View {
    init() {
        if FirebaseApp.app() == nil {
            FirebaseApp.configure()
        }
    }

    @UIApplicationDelegateAdaptor(AppDelegate.self) var delegate

    // MARK: — Data & State
    @State private var selectedMood: String = ""
    @State private var note = ""
    @State private var entries: [MoodEntry] = []
    @State private var moodOptions: [String] = []
    @State private var newMoodOption: String = ""

    @State private var showEditEntrySheet = false
    @State private var entryBeingEdited: MoodEntry?
    @State private var editedNote: String = ""
    @State private var editedMood: String = ""

    @State private var showEditMoodSheet = false
    @State private var moodToEdit: String = ""
    @State private var newMoodName: String = ""

    // For later reporting sync
    private let moodDB = MoodDatabase()

    var body: some View {
        NavigationView {
            ZStack {
                Color(.systemPink).opacity(0.1).edgesIgnoringSafeArea(.all)

                ScrollView {
                    VStack(spacing: 20) {
                        // MARK: — Title
                        Text("💖 Mood Journal 💖")
                            .font(.custom("Snell Roundhand", size: 36))
                            .foregroundColor(.pink)
                            .padding()
                            .background(Color.white.opacity(0.85))
                            .cornerRadius(12)
                            .overlay(
                                RoundedRectangle(cornerRadius: 12)
                                    .stroke(Color.pink, lineWidth: 2)
                            )
                            .padding(.top)

                        // MARK: — Mood Picker
                        if !moodOptions.isEmpty {
                            VStack(alignment: .leading) {
                                Text("Select Your Mood")
                                    .font(.headline)
                                    .foregroundColor(.pink)

                                Menu {
                                    ForEach(moodOptions, id: \.self) { option in
                                        Button(action: {
                                            selectedMood = option
                                        }) {
                                            Text(option)
                                        }
                                    }
                                } label: {
                                    HStack {
                                        Text(selectedMood.isEmpty ? "Choose a mood" : selectedMood)
                                            .foregroundColor(selectedMood.isEmpty ? .gray : .black)
                                        Spacer()
                                        Image(systemName: "chevron.down")
                                            .foregroundColor(.pink)
                                    }
                                    .padding()
                                    .background(Color.white)
                                    .cornerRadius(10)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 10)
                                            .stroke(Color.pink, lineWidth: 2)
                                    )
                                }
                            }
                            .padding(.horizontal)
                        }

                        // MARK: — Note Input
                        TextField("Write a note...", text: $note)
                            .textFieldStyle(RoundedBorderTextFieldStyle())
                            .padding(.horizontal)

                        Button(action: addMoodEntry) {
                            Text("Save Mood")
                                .frame(maxWidth: .infinity)
                                .padding()
                                .background(Color.pink)
                                .foregroundColor(.white)
                                .cornerRadius(10)
                        }
                        .padding(.horizontal)

                        Divider()

                        // MARK: — Add New Mood Option
                        VStack(spacing: 10) {
                            Text("💡 Add a New Mood")
                                .font(.headline)
                                .foregroundColor(.pink)

                            TextField("e.g., Chill, Motivated...", text: $newMoodOption)
                                .padding()
                                .background(Color.white)
                                .cornerRadius(10)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 10)
                                        .stroke(Color.pink, lineWidth: 1)
                                )
                                .padding(.horizontal)

                            Button(action: insertMoodOption) {
                                Text("➕ Add Mood Option")
                                    .font(.subheadline)
                                    .padding()
                                    .frame(maxWidth: .infinity)
                                    .background(Color.pink.opacity(0.9))
                                    .foregroundColor(.white)
                                    .cornerRadius(10)
                            }
                            .padding(.horizontal)
                        }

                        Divider()

                        // MARK: — Mood Options List (with Edit/Delete)
                        Text("🌈 Your Mood Options")
                            .font(.headline)
                            .foregroundColor(.pink)

                        List {
                            ForEach(moodOptions, id: \.self) { mood in
                                HStack {
                                    Text(mood)
                                    Spacer()
                                    Button("Edit") {
                                        moodToEdit = mood
                                        newMoodName = mood
                                        showEditMoodSheet = true
                                    }
                                    .foregroundColor(.blue)
                                }
                            }
                            .onDelete(perform: deleteMoodOption)
                        }
                        .frame(height: 200)

                        // MARK: — Mood Entries List (with tap to edit)
                        Text("📝 Your Mood Entries")
                            .font(.headline)
                            .foregroundColor(.pink)

                        List {
                            ForEach(entries) { entry in
                                VStack(alignment: .leading) {
                                    Text(entry.mood)
                                        .font(.headline)
                                    Text(entry.note)
                                        .font(.subheadline)
                                    Text(entry.date, style: .date)
                                        .font(.caption)
                                }
                                .padding(.vertical, 4)
                                .onTapGesture {
                                    entryBeingEdited = entry
                                    editedNote = entry.note
                                    editedMood = entry.mood
                                    showEditEntrySheet = true
                                }
                            }
                            .onDelete(perform: deleteMoodEntry)
                        }
                        .frame(height: 300)
                    }
                    .padding()
                }
            }
            .navigationBarTitle("", displayMode: .inline)
            .navigationBarItems(
                leading:
                    NavigationLink(destination: ReportView()) {
                        Text("Report")
                            .foregroundColor(.pink)
                    },
                trailing: EditButton()
            )
        }
        .onAppear {
            fetchMoodOptions()
            fetchMoodEntries()
        }
        // MARK: — Edit Sheets
        .sheet(isPresented: $showEditEntrySheet) {
            VStack(spacing: 20) {
                Text("Edit Entry")
                    .font(.title2)
                    .padding()

                TextField("Mood", text: $editedMood)
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                    .padding(.horizontal)

                TextField("Note", text: $editedNote)
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                    .padding(.horizontal)

                Button("Save Changes") {
                    if let entry = entryBeingEdited {
                        updateMoodEntry(entryID: entry.id,
                                        newMood: editedMood,
                                        newNote: editedNote)
                    }
                    showEditEntrySheet = false
                }
                .padding()
                .background(Color.pink)
                .foregroundColor(.white)
                .cornerRadius(10)
            }
            .padding()
        }
        .sheet(isPresented: $showEditMoodSheet) {
            VStack(spacing: 20) {
                Text("Edit Mood Option")
                    .font(.title2)
                    .padding()

                TextField("Mood", text: $newMoodName)
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                    .padding(.horizontal)

                Button("Save") {
                    updateMoodOption(oldMood: moodToEdit,
                                     newMood: newMoodName)
                    showEditMoodSheet = false
                }
                .padding()
                .background(Color.pink)
                .foregroundColor(.white)
                .cornerRadius(10)
            }
            .padding()
        }
    }

    // MARK: — Firestore CRUD Methods

    func addMoodEntry() {
        let db = Firestore.firestore()
        db.collection("moodEntries").addDocument(data: [
            "date": Timestamp(date: Date()),
            "mood": selectedMood,
            "note": note,
            "user_id": "user123"
        ]) { error in
            if let error = error {
                print("Error saving mood entry: \(error.localizedDescription)")
            } else {
                note = ""
            }
        }
    }

    func fetchMoodEntries() {
        let db = Firestore.firestore()
        db.collection("moodEntries")
            .order(by: "date", descending: true)
            .addSnapshotListener { snapshot, error in
                if let error = error {
                    print("Error fetching mood entries: \(error.localizedDescription)")
                    return
                }
                guard let documents = snapshot?.documents else { return }
                self.entries = documents.map { doc in
                    let data = doc.data()
                    return MoodEntry(
                        id: doc.documentID,
                        date: (data["date"] as? Timestamp)?.dateValue() ?? Date(),
                        mood: data["mood"] as? String ?? "Unknown",
                        note: data["note"] as? String ?? ""
                    )
                }
            }
    }

    func deleteMoodEntry(at offsets: IndexSet) {
        let db = Firestore.firestore()
        offsets.forEach { index in
            let entry = entries[index]
            db.collection("moodEntries").document(entry.id).delete { error in
                if let error = error {
                    print("Error deleting mood entry: \(error.localizedDescription)")
                }
            }
        }
    }

    func insertMoodOption() {
        guard !newMoodOption.isEmpty else { return }
        let db = Firestore.firestore()
        db.collection("moodOptions").addDocument(data: [
            "name": newMoodOption
        ]) { error in
            if let error = error {
                print("Error inserting mood option: \(error.localizedDescription)")
            } else {
                newMoodOption = ""
                fetchMoodOptions()
            }
        }
    }

    func fetchMoodOptions() {
        let db = Firestore.firestore()
        db.collection("moodOptions")
            .order(by: "name")
            .getDocuments { snapshot, error in
                if let error = error {
                    print("Error fetching mood options: \(error.localizedDescription)")
                    return
                }
                guard let documents = snapshot?.documents else { return }
                self.moodOptions = documents.compactMap { doc in
                    doc.data()["name"] as? String
                }
                if self.selectedMood.isEmpty, let first = moodOptions.first {
                    self.selectedMood = first
                }
            }
    }

    func deleteMoodOption(at offsets: IndexSet) {
        let db = Firestore.firestore()
        offsets.forEach { index in
            let moodToDelete = moodOptions[index]
            db.collection("moodOptions")
                .whereField("name", isEqualTo: moodToDelete)
                .getDocuments { snapshot, error in
                    if let error = error {
                        print("Error finding mood to delete: \(error.localizedDescription)")
                        return
                    }
                    snapshot?.documents.forEach { doc in
                        db.collection("moodOptions").document(doc.documentID).delete { err in
                            if let err = err {
                                print("Error deleting mood option: \(err.localizedDescription)")
                            } else {
                                fetchMoodOptions()
                            }
                        }
                    }
                }
        }
    }

    func updateMoodEntry(entryID: String, newMood: String, newNote: String) {
        let db = Firestore.firestore()
        db.collection("moodEntries").document(entryID).updateData([
            "mood": newMood,
            "note": newNote
        ]) { error in
            if let error = error {
                print("Error updating mood entry: \(error.localizedDescription)")
            } else {
                fetchMoodEntries()
            }
        }
    }

    func updateMoodOption(oldMood: String, newMood: String) {
        let db = Firestore.firestore()
        db.collection("moodOptions")
            .whereField("name", isEqualTo: oldMood)
            .getDocuments { snapshot, error in
                if let error = error {
                    print("Error finding mood to update: \(error.localizedDescription)")
                    return
                }
                snapshot?.documents.forEach { doc in
                    db.collection("moodOptions").document(doc.documentID).updateData([
                        "name": newMood
                    ]) { err in
                        if let err = err {
                            print("Error updating mood option: \(err.localizedDescription)")
                        } else {
                            fetchMoodOptions()
                        }
                    }
                }
            }
    }
}
