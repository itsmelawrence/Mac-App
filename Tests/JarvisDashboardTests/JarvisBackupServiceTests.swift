import Foundation
import SwiftData
import Testing
@testable import JarvisDashboard

@MainActor
struct JarvisBackupServiceTests {
    @Test func exportReplaceRoundTripPreservesRecordsAndRelationships() throws {
        let harness = try Harness()
        defer { harness.cleanUp() }
        let project = ProjectItem(
            name: "Client Site",
            client: "Client",
            type: "Website Build",
            summary: "A complete record",
            status: .waitingOnClient,
            priority: .urgent,
            mode: .ongoing,
            progress: 0.42,
            nextAction: "Await copy",
            startDate: Date(timeIntervalSince1970: 1_700_000_000),
            dueDate: Date(timeIntervalSince1970: 1_800_000_000),
            tags: ["WordPress", "Retainer"]
        )
        project.repositoryPath = "/tmp/client"
        project.repositoryBookmarkData = Data("bookmark".utf8)
        project.monitoringWebsiteURL = "https://example.com"
        project.monitoringPlatform = .wordpress
        project.monitoringSiteID = "site-42"
        project.monitoringConnectedAt = Date(timeIntervalSince1970: 1_750_000_000)
        let task = TaskItem(
            title: "Receive copy",
            notes: "Homepage",
            dueDate: project.dueDate,
            priority: .critical,
            projectID: project.id,
            isBlocked: true,
            blockedReason: "Waiting for client"
        )
        let location = SavedLocation(name: "Manila", latitude: 14.5995, longitude: 120.9842, isPrimary: true)
        harness.context.insert(project)
        harness.context.insert(task)
        harness.context.insert(location)
        try harness.context.save()

        let document = try harness.service.makeDocument(context: harness.context)
        try harness.service.apply(
            document,
            mode: .replace,
            confirmation: "REPLACE",
            context: harness.context,
            backupFolder: harness.folder,
            retentionCount: 14
        )

        let restoredProject = try #require(harness.context.fetch(FetchDescriptor<ProjectItem>()).first)
        let restoredTask = try #require(harness.context.fetch(FetchDescriptor<TaskItem>()).first)
        let restoredLocation = try #require(harness.context.fetch(FetchDescriptor<SavedLocation>()).first)
        #expect(ProjectBackupRecord(restoredProject) == ProjectBackupRecord(project))
        #expect(TaskBackupRecord(restoredTask) == TaskBackupRecord(task))
        #expect(restoredTask.projectID == restoredProject.id)
        #expect(LocationBackupRecord(restoredLocation) == LocationBackupRecord(location))
    }

    @Test func exportExcludesCredentialLikeDefaults() throws {
        let harness = try Harness()
        defer { harness.cleanUp() }
        harness.defaults.set("NEWS-SECRET-123", forKey: "news.apiKey")
        harness.defaults.set("MONITORING-SECRET-456", forKey: "monitoring.token")
        harness.defaults.set("REPORTER-SECRET-789", forKey: "reporter.token")
        harness.defaults.set(false, forKey: "sites.notifyOnChange")

        let document = try harness.service.makeDocument(context: harness.context)
        let text = String(decoding: try harness.service.encode(document), as: UTF8.self)
        #expect(!text.contains("NEWS-SECRET-123"))
        #expect(!text.contains("MONITORING-SECRET-456"))
        #expect(!text.contains("REPORTER-SECRET-789"))
        #expect(document.preferences["sites.notifyOnChange"] == .bool(false))
    }

    @Test func malformedAndNewerFilesChangeNothing() throws {
        let harness = try Harness()
        defer { harness.cleanUp() }
        harness.context.insert(TaskItem(title: "Keep me"))
        try harness.context.save()

        #expect(throws: JarvisBackupError.malformedFile) {
            try harness.service.decode(Data("not json".utf8))
        }
        #expect(try harness.context.fetchCount(FetchDescriptor<TaskItem>()) == 1)

        let newer = JarvisBackupDocument(
            schemaVersion: 999,
            appVersion: "future",
            exportedAt: .now,
            tasks: [],
            projects: [],
            savedLocations: [],
            preferences: [:]
        )
        #expect(throws: JarvisBackupError.newerSchema(999)) {
            _ = try harness.service.preview(newer, context: harness.context)
        }
        #expect(try harness.context.fetchCount(FetchDescriptor<TaskItem>()) == 1)
    }

    @Test func mergingTwiceIsIdempotent() throws {
        let harness = try Harness()
        defer { harness.cleanUp() }
        let task = TaskItem(title: "One task")
        harness.context.insert(task)
        try harness.context.save()
        let document = try harness.service.makeDocument(context: harness.context)

        try harness.service.apply(document, mode: .merge, context: harness.context)
        try harness.service.apply(document, mode: .merge, context: harness.context)

        #expect(try harness.context.fetchCount(FetchDescriptor<TaskItem>()) == 1)
        let preview = try harness.service.preview(document, context: harness.context)
        #expect(preview.tasks.skipped == 1)
        #expect(preview.tasks.new == 0)
        #expect(preview.tasks.updated == 0)
    }

    @Test func replaceRequiresConfirmationAndBacksUpFirst() throws {
        let harness = try Harness()
        defer { harness.cleanUp() }
        harness.context.insert(TaskItem(title: "Current"))
        try harness.context.save()
        let empty = JarvisBackupDocument(
            schemaVersion: 1,
            appVersion: "test",
            exportedAt: .now,
            tasks: [],
            projects: [],
            savedLocations: [],
            preferences: [:]
        )

        #expect(throws: JarvisBackupError.replaceConfirmationRequired) {
            try harness.service.apply(
                empty,
                mode: .replace,
                confirmation: "replace",
                context: harness.context,
                backupFolder: harness.folder
            )
        }
        #expect(try harness.context.fetchCount(FetchDescriptor<TaskItem>()) == 1)

        let safetyBackup = try harness.service.apply(
            empty,
            mode: .replace,
            confirmation: "REPLACE",
            context: harness.context,
            backupFolder: harness.folder
        )
        let backup = try #require(safetyBackup)
        #expect(FileManager.default.fileExists(atPath: backup.path))
        #expect(try harness.context.fetchCount(FetchDescriptor<TaskItem>()) == 0)
    }

    @Test func rotationKeepsExactlyRequestedCount() throws {
        let harness = try Harness()
        defer { harness.cleanUp() }
        for index in 0..<6 {
            let file = harness.folder.appendingPathComponent("backup-\(index).jarvisbackup")
            try Data("\(index)".utf8).write(to: file)
            try FileManager.default.setAttributes(
                [.modificationDate: Date(timeIntervalSince1970: TimeInterval(index))],
                ofItemAtPath: file.path
            )
        }

        try harness.service.rotateBackups(in: harness.folder, keeping: 3)
        let remaining = try FileManager.default.contentsOfDirectory(at: harness.folder, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "jarvisbackup" }
        #expect(remaining.count == 3)
        #expect(Set(remaining.map(\.lastPathComponent)) == ["backup-3.jarvisbackup", "backup-4.jarvisbackup", "backup-5.jarvisbackup"])
    }

    @Test func automaticBackupRunsOncePerDay() throws {
        let suite = "JarvisDailyBackupTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        defaults.set(folder.path, forKey: "backup.folderPath")
        var clock = Date(timeIntervalSince1970: 1_900_000_000)
        let configuration = ModelConfiguration(schema: JarvisDataStore.schema, isStoredInMemoryOnly: true)
        let container = try JarvisDataStore.makeContainer(configuration: configuration)
        let context = ModelContext(container)
        let service = JarvisBackupService(defaults: defaults, now: { clock }, appVersion: "test")

        #expect(try service.backupIfDue(context: context) != nil)
        #expect(try service.backupIfDue(context: context) == nil)
        clock.addTimeInterval(86_401)
        #expect(try service.backupIfDue(context: context) != nil)
    }

    @Test func createsRawStoreCopyBeforeMigrationOnlyOnce() throws {
        let suite = "JarvisMigrationBackupTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        try Data("store".utf8).write(to: folder.appendingPathComponent("default.store"))
        try Data("wal".utf8).write(to: folder.appendingPathComponent("default.store-wal"))

        try MigrationSafetyBackup.createIfNeeded(
            targetVersion: "1.0.0",
            defaults: defaults,
            applicationSupportURL: folder
        )
        try MigrationSafetyBackup.createIfNeeded(
            targetVersion: "1.0.0",
            defaults: defaults,
            applicationSupportURL: folder
        )

        let backupRoot = folder.appendingPathComponent("JARVIS Dashboard/Backups", isDirectory: true)
        let backups = try FileManager.default.contentsOfDirectory(at: backupRoot, includingPropertiesForKeys: nil)
        #expect(backups.count == 1)
        let backup = try #require(backups.first)
        #expect(FileManager.default.fileExists(atPath: backup.appendingPathComponent("default.store").path))
        #expect(FileManager.default.fileExists(atPath: backup.appendingPathComponent("default.store-wal").path))
    }

    @Test func opensStoreCreatedWithPreviousUnversionedSchema() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let storeURL = folder.appendingPathComponent("legacy.store")
        let legacySchema = Schema([TaskItem.self, ProjectItem.self, SavedLocation.self])

        do {
            let configuration = ModelConfiguration("legacy", schema: legacySchema, url: storeURL)
            let container = try ModelContainer(for: legacySchema, configurations: configuration)
            let context = ModelContext(container)
            let project = ProjectItem(name: "0.1.18 Project")
            context.insert(project)
            context.insert(TaskItem(title: "0.1.18 Task", projectID: project.id))
            context.insert(SavedLocation(name: "Cebu", latitude: 10.3157, longitude: 123.8854))
            try context.save()
        }

        let configuration = ModelConfiguration("legacy", schema: JarvisDataStore.schema, url: storeURL)
        let migrated = try JarvisDataStore.makeContainer(configuration: configuration)
        let context = ModelContext(migrated)
        #expect(try context.fetchCount(FetchDescriptor<ProjectItem>()) == 1)
        #expect(try context.fetchCount(FetchDescriptor<TaskItem>()) == 1)
        #expect(try context.fetchCount(FetchDescriptor<SavedLocation>()) == 1)
        let task = try #require(context.fetch(FetchDescriptor<TaskItem>()).first)
        let project = try #require(context.fetch(FetchDescriptor<ProjectItem>()).first)
        #expect(task.projectID == project.id)
    }
}

@MainActor
private final class Harness {
    let container: ModelContainer
    let context: ModelContext
    let defaults: UserDefaults
    let folder: URL
    let service: JarvisBackupService
    private let suiteName: String

    init() throws {
        let suite = "JarvisBackupServiceTests.\(UUID().uuidString)"
        suiteName = suite
        defaults = try #require(UserDefaults(suiteName: suite))
        defaults.removePersistentDomain(forName: suite)
        folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let configuration = ModelConfiguration(schema: JarvisDataStore.schema, isStoredInMemoryOnly: true)
        container = try JarvisDataStore.makeContainer(configuration: configuration)
        context = ModelContext(container)
        service = JarvisBackupService(
            defaults: defaults,
            now: { Date(timeIntervalSince1970: 1_900_000_000) },
            appVersion: "test"
        )
    }

    func cleanUp() {
        try? FileManager.default.removeItem(at: folder)
        defaults.removePersistentDomain(forName: suiteName)
    }
}
