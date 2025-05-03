//
//  MoodEntry.swift
//  MoodJournal3
//
//  Created by Ishwarya Samavedhi on 3/31/25.
//

import Foundation
import FirebaseFirestore

struct MoodEntry: Identifiable {
    var id: String
    var date: Date
    var mood: String
    var note: String
}
