import Foundation
import SwiftData

enum JarvisSchemaV1: VersionedSchema {
    static let versionIdentifier = Schema.Version(1, 0, 0)

    static var models: [any PersistentModel.Type] {
        [TaskItem.self, ProjectItem.self, SavedLocation.self]
    }
}

enum JarvisMigrationPlan: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] {
        [JarvisSchemaV1.self]
    }

    static var stages: [MigrationStage] { [] }
}

enum JarvisDataStore {
    static let schema = Schema(versionedSchema: JarvisSchemaV1.self)

    static func makeContainer() throws -> ModelContainer {
        try ModelContainer(for: schema, migrationPlan: JarvisMigrationPlan.self)
    }

    static func makeContainer(configuration: ModelConfiguration) throws -> ModelContainer {
        try ModelContainer(
            for: schema,
            migrationPlan: JarvisMigrationPlan.self,
            configurations: configuration
        )
    }
}

enum MigrationSafetyBackup {
    private static let markerKey = "backup.preMigrationSchemaVersion"

    static func createIfNeeded(
        targetVersion: String,
        defaults: UserDefaults = .standard,
        fileManager: FileManager = .default,
        applicationSupportURL: URL? = nil
    ) throws {
        guard defaults.string(forKey: markerKey) != targetVersion else { return }

        let applicationSupport = try applicationSupportURL ?? fileManager.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let storeURL = applicationSupport.appendingPathComponent("default.store")
        guard fileManager.fileExists(atPath: storeURL.path) else {
            defaults.set(targetVersion, forKey: markerKey)
            return
        }

        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        let destination = applicationSupport
            .appendingPathComponent("JARVIS Dashboard/Backups", isDirectory: true)
            .appendingPathComponent("pre-migration-\(formatter.string(from: .now))-\(targetVersion)", isDirectory: true)
        try fileManager.createDirectory(at: destination, withIntermediateDirectories: true)

        for suffix in ["", "-wal", "-shm"] {
            let source = URL(fileURLWithPath: storeURL.path + suffix)
            guard fileManager.fileExists(atPath: source.path) else { continue }
            try fileManager.copyItem(
                at: source,
                to: destination.appendingPathComponent(source.lastPathComponent)
            )
        }

        defaults.set(targetVersion, forKey: markerKey)
    }
}
