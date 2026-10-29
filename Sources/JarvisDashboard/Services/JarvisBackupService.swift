import AppKit
import Foundation
import SwiftData
import SwiftUI
import UniformTypeIdentifiers

struct JarvisBackupDocument: Codable, Equatable, Sendable {
    static let currentSchemaVersion = 1

    let schemaVersion: Int
    let appVersion: String
    let exportedAt: Date
    let tasks: [TaskBackupRecord]
    let projects: [ProjectBackupRecord]
    let savedLocations: [LocationBackupRecord]
    let preferences: [String: BackupPreferenceValue]
}

struct TaskBackupRecord: Codable, Equatable, Sendable {
    let id: UUID
    let title: String
    let notes: String
    let dueDate: Date?
    let priorityRawValue: Int
    let isCompleted: Bool
    let createdAt: Date
    let projectID: UUID?
    let isBlocked: Bool
    let blockedReason: String

    init(_ task: TaskItem) {
        id = task.id
        title = task.title
        notes = task.notes
        dueDate = task.dueDate
        priorityRawValue = task.priorityRawValue
        isCompleted = task.isCompleted
        createdAt = task.createdAt
        projectID = task.projectID
        isBlocked = task.isBlocked
        blockedReason = task.blockedReason
    }
}

struct ProjectBackupRecord: Codable, Equatable, Sendable {
    let id: UUID
    let name: String
    let client: String
    let type: String
    let summary: String
    let statusRawValue: String
    let priorityRawValue: String
    let modeRawValue: String
    let progress: Double
    let nextAction: String
    let startDate: Date?
    let dueDate: Date?
    let tagsRawValue: String
    let createdAt: Date
    let updatedAt: Date
    let archivedAt: Date?
    let statusChangedAt: Date
    let repositoryPath: String
    let repositoryBookmarkData: Data?
    let monitoringWebsiteURL: String
    let monitoringPlatformRawValue: String
    let monitoringSiteID: String
    let monitoringConnectedAt: Date?

    init(_ project: ProjectItem) {
        id = project.id
        name = project.name
        client = project.client
        type = project.type
        summary = project.summary
        statusRawValue = project.statusRawValue
        priorityRawValue = project.priorityRawValue
        modeRawValue = project.modeRawValue
        progress = project.progress
        nextAction = project.nextAction
        startDate = project.startDate
        dueDate = project.dueDate
        tagsRawValue = project.tagsRawValue
        createdAt = project.createdAt
        updatedAt = project.updatedAt
        archivedAt = project.archivedAt
        statusChangedAt = project.statusChangedAt
        repositoryPath = project.repositoryPath
        repositoryBookmarkData = project.repositoryBookmarkData
        monitoringWebsiteURL = project.monitoringWebsiteURL
        monitoringPlatformRawValue = project.monitoringPlatformRawValue
        monitoringSiteID = project.monitoringSiteID
        monitoringConnectedAt = project.monitoringConnectedAt
    }
}

struct LocationBackupRecord: Codable, Equatable, Sendable {
    let stableID: String
    let name: String
    let latitude: Double
    let longitude: Double
    let isPrimary: Bool

    init(_ location: SavedLocation) {
        name = location.name
        latitude = location.latitude
        longitude = location.longitude
        isPrimary = location.isPrimary
        stableID = Self.makeStableID(name: name, latitude: latitude, longitude: longitude)
    }

    static func makeStableID(name: String, latitude: Double, longitude: Double) -> String {
        "\(name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased())|\(latitude.bitPattern)|\(longitude.bitPattern)"
    }
}

enum BackupPreferenceValue: Codable, Equatable, Sendable {
    case bool(Bool)
    case integer(Int)
    case double(Double)
    case string(String)
    case strings([String])

    private enum CodingKeys: String, CodingKey { case type, value }
    private enum Kind: String, Codable { case bool, integer, double, string, strings }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        switch try container.decode(Kind.self, forKey: .type) {
        case .bool: self = .bool(try container.decode(Bool.self, forKey: .value))
        case .integer: self = .integer(try container.decode(Int.self, forKey: .value))
        case .double: self = .double(try container.decode(Double.self, forKey: .value))
        case .string: self = .string(try container.decode(String.self, forKey: .value))
        case .strings: self = .strings(try container.decode([String].self, forKey: .value))
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case let .bool(value):
            try container.encode(Kind.bool, forKey: .type)
            try container.encode(value, forKey: .value)
        case let .integer(value):
            try container.encode(Kind.integer, forKey: .type)
            try container.encode(value, forKey: .value)
        case let .double(value):
            try container.encode(Kind.double, forKey: .type)
            try container.encode(value, forKey: .value)
        case let .string(value):
            try container.encode(Kind.string, forKey: .type)
            try container.encode(value, forKey: .value)
        case let .strings(value):
            try container.encode(Kind.strings, forKey: .type)
            try container.encode(value, forKey: .value)
        }
    }
}

struct ImportEntityPreview: Equatable, Sendable {
    let new: Int
    let updated: Int
    let skipped: Int
}

struct JarvisImportPreview: Equatable, Sendable {
    let tasks: ImportEntityPreview
    let projects: ImportEntityPreview
    let locations: ImportEntityPreview
    let changedPreferences: Int
}

enum JarvisImportMode: Sendable {
    case merge
    case replace
}

enum JarvisBackupError: LocalizedError, Equatable {
    case newerSchema(Int)
    case unsupportedSchema(Int)
    case malformedFile
    case duplicateRecord(String)
    case invalidRecord(String)
    case replaceConfirmationRequired

    var errorDescription: String? {
        switch self {
        case let .newerSchema(version):
            "This backup uses schema version \(version). Update JARVIS before importing it."
        case let .unsupportedSchema(version):
            "Schema version \(version) is not supported."
        case .malformedFile:
            "This is not a valid JARVIS backup file. No data was changed."
        case let .duplicateRecord(record):
            "The backup contains a duplicate \(record). No data was changed."
        case let .invalidRecord(record):
            "The backup contains an invalid \(record). No data was changed."
        case .replaceConfirmationRequired:
            "Type REPLACE to confirm replacement."
        }
    }
}

enum PreferenceBackupStore {
    private enum ValueKind { case bool, integer, double, string, strings }

    private static let keys: [(String, ValueKind)] = [
        ("showWakeBriefing", .bool),
        ("minimumSleepForBriefing", .double),
        ("projects.sort", .string),
        ("sites.notifyOnChange", .bool),
        ("intelligence.selectedPage", .string),
        ("intelligence.newsCategory", .string),
        ("intelligence.watchlist", .string),
        ("intelligence.earthquakeThreshold", .double),
        ("intelligence.rainThreshold", .integer),
        ("intelligence.notificationsEnabled", .bool),
        ("intelligence.quietStart", .integer),
        ("intelligence.quietEnd", .integer),
        ("intelligence.readIDs", .string),
        ("intelligence.savedIDs", .string),
        ("intelligence.dismissedIDs", .string),
        ("speech.isEnabled", .bool),
        ("speech.speakWakeBriefings", .bool),
        ("speech.speakCriticalAlerts", .bool),
        ("speech.quietHoursEnabled", .bool),
        ("speech.quietStartHour", .integer),
        ("speech.quietEndHour", .integer),
        ("speech.voiceIdentifier", .string),
        ("speech.rate", .double),
        ("speech.pitch", .double),
        ("speech.volume", .double),
        ("speech.spokenCriticalAlertIDs", .strings),
        ("backup.retentionCount", .integer)
    ]

    static func export(from defaults: UserDefaults) -> [String: BackupPreferenceValue] {
        var result: [String: BackupPreferenceValue] = [:]
        for (key, kind) in keys where defaults.object(forKey: key) != nil {
            switch kind {
            case .bool: result[key] = .bool(defaults.bool(forKey: key))
            case .integer: result[key] = .integer(defaults.integer(forKey: key))
            case .double: result[key] = .double(defaults.double(forKey: key))
            case .string: result[key] = .string(defaults.string(forKey: key) ?? "")
            case .strings: result[key] = .strings(defaults.stringArray(forKey: key) ?? [])
            }
        }
        return result
    }

    static func apply(_ preferences: [String: BackupPreferenceValue], to defaults: UserDefaults) {
        let allowed = Set(keys.map(\.0))
        for (key, value) in preferences where allowed.contains(key) {
            switch value {
            case let .bool(value): defaults.set(value, forKey: key)
            case let .integer(value): defaults.set(value, forKey: key)
            case let .double(value): defaults.set(value, forKey: key)
            case let .string(value): defaults.set(value, forKey: key)
            case let .strings(value): defaults.set(value, forKey: key)
            }
        }
    }

    static func isValid(_ preferences: [String: BackupPreferenceValue]) -> Bool {
        let expected = Dictionary(uniqueKeysWithValues: keys)
        return preferences.allSatisfy { key, value in
            guard let kind = expected[key] else { return false }
            switch (kind, value) {
            case (.bool, .bool), (.integer, .integer), (.double, .double),
                 (.string, .string), (.strings, .strings):
                return true
            default:
                return false
            }
        }
    }
}

@MainActor
struct JarvisBackupService {
    let defaults: UserDefaults
    let fileManager: FileManager
    let now: () -> Date
    let appVersion: String

    init(
        defaults: UserDefaults = .standard,
        fileManager: FileManager = .default,
        now: @escaping () -> Date = { .now },
        appVersion: String = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "development"
    ) {
        self.defaults = defaults
        self.fileManager = fileManager
        self.now = now
        self.appVersion = appVersion
    }

    func makeDocument(context: ModelContext) throws -> JarvisBackupDocument {
        JarvisBackupDocument(
            schemaVersion: JarvisBackupDocument.currentSchemaVersion,
            appVersion: appVersion,
            exportedAt: now(),
            tasks: try context.fetch(FetchDescriptor<TaskItem>()).map(TaskBackupRecord.init),
            projects: try context.fetch(FetchDescriptor<ProjectItem>()).map(ProjectBackupRecord.init),
            savedLocations: try context.fetch(FetchDescriptor<SavedLocation>()).map(LocationBackupRecord.init),
            preferences: PreferenceBackupStore.export(from: defaults)
        )
    }

    func encode(_ document: JarvisBackupDocument) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(document)
    }

    func decode(_ data: Data) throws -> JarvisBackupDocument {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let document: JarvisBackupDocument
        do {
            document = try decoder.decode(JarvisBackupDocument.self, from: data)
        } catch {
            throw JarvisBackupError.malformedFile
        }
        try validate(document)
        return document
    }

    func preview(_ document: JarvisBackupDocument, context: ModelContext) throws -> JarvisImportPreview {
        try validate(document)
        let currentTasks = Dictionary(uniqueKeysWithValues: try context.fetch(FetchDescriptor<TaskItem>()).map { ($0.id, TaskBackupRecord($0)) })
        let currentProjects = Dictionary(uniqueKeysWithValues: try context.fetch(FetchDescriptor<ProjectItem>()).map { ($0.id, ProjectBackupRecord($0)) })
        try validateRelationships(document, existingProjectIDs: Set(currentProjects.keys), mode: .merge)
        let currentLocations = Dictionary(uniqueKeysWithValues: try context.fetch(FetchDescriptor<SavedLocation>()).map { (LocationBackupRecord($0).stableID, LocationBackupRecord($0)) })
        let currentPreferences = PreferenceBackupStore.export(from: defaults)

        return JarvisImportPreview(
            tasks: counts(incoming: document.tasks, current: currentTasks, id: \.id),
            projects: counts(incoming: document.projects, current: currentProjects, id: \.id),
            locations: counts(incoming: document.savedLocations, current: currentLocations, id: \.stableID),
            changedPreferences: document.preferences.filter { currentPreferences[$0.key] != $0.value }.count
        )
    }

    @discardableResult
    func apply(
        _ document: JarvisBackupDocument,
        mode: JarvisImportMode,
        confirmation: String = "",
        context: ModelContext,
        backupFolder: URL? = nil,
        retentionCount: Int? = nil
    ) throws -> URL? {
        try validate(document)
        let existingProjectIDs = Set(try context.fetch(FetchDescriptor<ProjectItem>()).map(\.id))
        try validateRelationships(document, existingProjectIDs: existingProjectIDs, mode: mode)
        var safetyBackup: URL?
        if mode == .replace {
            guard confirmation == "REPLACE" else { throw JarvisBackupError.replaceConfirmationRequired }
            safetyBackup = try backupNow(
                context: context,
                folder: backupFolder,
                retentionCount: retentionCount
            )
        }

        do {
            let existingTasks = try context.fetch(FetchDescriptor<TaskItem>())
            let existingProjects = try context.fetch(FetchDescriptor<ProjectItem>())
            let existingLocations = try context.fetch(FetchDescriptor<SavedLocation>())

            if mode == .replace {
                existingTasks.forEach(context.delete)
                existingProjects.forEach(context.delete)
                existingLocations.forEach(context.delete)
                document.projects.forEach { context.insert(makeProject(from: $0)) }
                document.tasks.forEach { context.insert(makeTask(from: $0)) }
                document.savedLocations.forEach { context.insert(makeLocation(from: $0)) }
            } else {
                mergeProjects(document.projects, into: existingProjects, context: context)
                mergeTasks(document.tasks, into: existingTasks, context: context)
                mergeLocations(document.savedLocations, into: existingLocations, context: context)
            }

            try context.save()
            PreferenceBackupStore.apply(document.preferences, to: defaults)
            return safetyBackup
        } catch {
            context.rollback()
            throw error
        }
    }

    @discardableResult
    func backupNow(
        context: ModelContext,
        folder: URL? = nil,
        retentionCount: Int? = nil
    ) throws -> URL {
        let destinationFolder = try folder ?? backupFolderURL()
        try fileManager.createDirectory(at: destinationFolder, withIntermediateDirectories: true)
        let stamp = ISO8601DateFormatter().string(from: now()).replacingOccurrences(of: ":", with: "-")
        let destination = destinationFolder.appendingPathComponent("JARVIS-Backup-\(stamp)-\(UUID().uuidString.prefix(8)).jarvisbackup")
        try encode(makeDocument(context: context)).write(to: destination, options: .atomic)
        defaults.set(now(), forKey: "backup.lastBackupAt")
        try rotateBackups(in: destinationFolder, keeping: retentionCount ?? configuredRetentionCount)
        return destination
    }

    func backupIfDue(context: ModelContext) throws -> URL? {
        if let lastBackup = defaults.object(forKey: "backup.lastBackupAt") as? Date,
           now().timeIntervalSince(lastBackup) < 24 * 60 * 60 {
            return nil
        }
        return try backupNow(context: context)
    }

    func backupFolderURL() throws -> URL {
        if let path = defaults.string(forKey: "backup.folderPath"), !path.isEmpty {
            return URL(fileURLWithPath: path, isDirectory: true)
        }
        return try fileManager.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        ).appendingPathComponent("JARVIS Dashboard/Backups", isDirectory: true)
    }

    func setBackupFolder(_ url: URL) {
        defaults.set(url.path, forKey: "backup.folderPath")
    }

    func rotateBackups(in folder: URL, keeping requestedCount: Int) throws {
        let keepCount = max(1, requestedCount)
        let files = try fileManager.contentsOfDirectory(
            at: folder,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]
        ).filter { $0.pathExtension == "jarvisbackup" }
        let sorted = try files.sorted {
            let lhs = try $0.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate ?? .distantPast
            let rhs = try $1.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate ?? .distantPast
            return lhs > rhs
        }
        for file in sorted.dropFirst(keepCount) { try fileManager.removeItem(at: file) }
    }

    private var configuredRetentionCount: Int {
        max(1, defaults.object(forKey: "backup.retentionCount") == nil ? 14 : defaults.integer(forKey: "backup.retentionCount"))
    }

    private func validate(_ document: JarvisBackupDocument) throws {
        if document.schemaVersion > JarvisBackupDocument.currentSchemaVersion {
            throw JarvisBackupError.newerSchema(document.schemaVersion)
        }
        guard document.schemaVersion == JarvisBackupDocument.currentSchemaVersion else {
            throw JarvisBackupError.unsupportedSchema(document.schemaVersion)
        }
        guard Set(document.tasks.map(\.id)).count == document.tasks.count else {
            throw JarvisBackupError.duplicateRecord("task id")
        }
        guard Set(document.projects.map(\.id)).count == document.projects.count else {
            throw JarvisBackupError.duplicateRecord("project id")
        }
        guard Set(document.savedLocations.map(\.stableID)).count == document.savedLocations.count else {
            throw JarvisBackupError.duplicateRecord("saved location")
        }
        guard document.tasks.allSatisfy({ !$0.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) else {
            throw JarvisBackupError.invalidRecord("task title")
        }
        guard document.tasks.allSatisfy({ TaskPriority(rawValue: $0.priorityRawValue) != nil }) else {
            throw JarvisBackupError.invalidRecord("task priority")
        }
        guard document.projects.allSatisfy({
            !$0.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                && $0.progress.isFinite && (0...1).contains($0.progress)
        }) else {
            throw JarvisBackupError.invalidRecord("project")
        }
        guard document.savedLocations.allSatisfy({
            !$0.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                && $0.latitude.isFinite && (-90...90).contains($0.latitude)
                && $0.longitude.isFinite && (-180...180).contains($0.longitude)
                && $0.stableID == LocationBackupRecord.makeStableID(name: $0.name, latitude: $0.latitude, longitude: $0.longitude)
        }) else {
            throw JarvisBackupError.invalidRecord("saved location")
        }
        guard PreferenceBackupStore.isValid(document.preferences) else {
            throw JarvisBackupError.invalidRecord("preference")
        }
    }

    private func validateRelationships(
        _ document: JarvisBackupDocument,
        existingProjectIDs: Set<UUID>,
        mode: JarvisImportMode
    ) throws {
        var availableProjectIDs = Set(document.projects.map(\.id))
        if mode == .merge { availableProjectIDs.formUnion(existingProjectIDs) }
        guard document.tasks.allSatisfy({ task in
            guard let projectID = task.projectID else { return true }
            return availableProjectIDs.contains(projectID)
        }) else {
            throw JarvisBackupError.invalidRecord("task-to-project relationship")
        }
    }

    private func counts<Record: Equatable, ID: Hashable>(
        incoming: [Record],
        current: [ID: Record],
        id: KeyPath<Record, ID>
    ) -> ImportEntityPreview {
        var new = 0
        var updated = 0
        var skipped = 0
        for record in incoming {
            guard let existing = current[record[keyPath: id]] else { new += 1; continue }
            existing == record ? (skipped += 1) : (updated += 1)
        }
        return ImportEntityPreview(new: new, updated: updated, skipped: skipped)
    }

    private func makeTask(from record: TaskBackupRecord) -> TaskItem {
        let task = TaskItem(
            title: record.title,
            notes: record.notes,
            dueDate: record.dueDate,
            priority: TaskPriority(rawValue: record.priorityRawValue) ?? .normal,
            isCompleted: record.isCompleted,
            createdAt: record.createdAt,
            projectID: record.projectID,
            isBlocked: record.isBlocked,
            blockedReason: record.blockedReason
        )
        task.id = record.id
        task.priorityRawValue = record.priorityRawValue
        return task
    }

    private func update(_ task: TaskItem, from record: TaskBackupRecord) {
        task.title = record.title
        task.notes = record.notes
        task.dueDate = record.dueDate
        task.priorityRawValue = record.priorityRawValue
        task.isCompleted = record.isCompleted
        task.createdAt = record.createdAt
        task.projectID = record.projectID
        task.isBlocked = record.isBlocked
        task.blockedReason = record.blockedReason
    }

    private func makeProject(from record: ProjectBackupRecord) -> ProjectItem {
        let project = ProjectItem(name: record.name)
        update(project, from: record)
        project.id = record.id
        return project
    }

    private func update(_ project: ProjectItem, from record: ProjectBackupRecord) {
        project.name = record.name
        project.client = record.client
        project.type = record.type
        project.summary = record.summary
        project.statusRawValue = record.statusRawValue
        project.priorityRawValue = record.priorityRawValue
        project.modeRawValue = record.modeRawValue
        project.progress = record.progress
        project.nextAction = record.nextAction
        project.startDate = record.startDate
        project.dueDate = record.dueDate
        project.tagsRawValue = record.tagsRawValue
        project.createdAt = record.createdAt
        project.updatedAt = record.updatedAt
        project.archivedAt = record.archivedAt
        project.statusChangedAt = record.statusChangedAt
        project.repositoryPath = record.repositoryPath
        project.repositoryBookmarkData = record.repositoryBookmarkData
        project.monitoringWebsiteURL = record.monitoringWebsiteURL
        project.monitoringPlatformRawValue = record.monitoringPlatformRawValue
        project.monitoringSiteID = record.monitoringSiteID
        project.monitoringConnectedAt = record.monitoringConnectedAt
    }

    private func makeLocation(from record: LocationBackupRecord) -> SavedLocation {
        SavedLocation(name: record.name, latitude: record.latitude, longitude: record.longitude, isPrimary: record.isPrimary)
    }

    private func update(_ location: SavedLocation, from record: LocationBackupRecord) {
        location.name = record.name
        location.latitude = record.latitude
        location.longitude = record.longitude
        location.isPrimary = record.isPrimary
    }

    private func mergeTasks(_ records: [TaskBackupRecord], into current: [TaskItem], context: ModelContext) {
        let byID = Dictionary(uniqueKeysWithValues: current.map { ($0.id, $0) })
        for record in records {
            if let task = byID[record.id] { update(task, from: record) }
            else { context.insert(makeTask(from: record)) }
        }
    }

    private func mergeProjects(_ records: [ProjectBackupRecord], into current: [ProjectItem], context: ModelContext) {
        let byID = Dictionary(uniqueKeysWithValues: current.map { ($0.id, $0) })
        for record in records {
            if let project = byID[record.id] { update(project, from: record) }
            else { context.insert(makeProject(from: record)) }
        }
    }

    private func mergeLocations(_ records: [LocationBackupRecord], into current: [SavedLocation], context: ModelContext) {
        let byID = Dictionary(uniqueKeysWithValues: current.map { (LocationBackupRecord($0).stableID, $0) })
        for record in records {
            if let location = byID[record.stableID] { update(location, from: record) }
            else { context.insert(makeLocation(from: record)) }
        }
    }
}

struct JarvisBackupFile: FileDocument {
    static var readableContentTypes: [UTType] {
        [UTType(filenameExtension: "jarvisbackup") ?? .json, .json]
    }

    let data: Data

    init(data: Data = Data()) { self.data = data }

    init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents else {
            throw JarvisBackupError.malformedFile
        }
        self.data = data
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}

@MainActor
final class BackupCoordinator: ObservableObject {
    @Published private(set) var lastBackupAt: Date?
    @Published private(set) var lastError: String?

    private let service: JarvisBackupService

    init() {
        let service = JarvisBackupService()
        self.service = service
        lastBackupAt = service.defaults.object(forKey: "backup.lastBackupAt") as? Date
    }

    init(service: JarvisBackupService) {
        self.service = service
        lastBackupAt = service.defaults.object(forKey: "backup.lastBackupAt") as? Date
    }

    func performAutomaticBackupIfDue(context: ModelContext) {
        do {
            if try service.backupIfDue(context: context) != nil {
                lastBackupAt = service.defaults.object(forKey: "backup.lastBackupAt") as? Date
            }
            lastError = nil
        } catch {
            lastError = error.localizedDescription
        }
    }

    func runAutomaticBackups(context: ModelContext) async {
        while !Task.isCancelled {
            performAutomaticBackupIfDue(context: context)
            do {
                try await Task.sleep(for: .seconds(6 * 60 * 60))
            } catch {
                return
            }
        }
    }
}
