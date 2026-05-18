import Foundation
import SwiftData

public enum FocusModelContainer {
    /// CloudKit container identifier — must match the iCloud entitlement
    /// configured in App Store Connect / the Xcode project settings.
    public static let cloudKitContainerID = "iCloud.com.magnus.focus"

    /// Build the SwiftData container. When `cloudKitSync` is true, data syncs
    /// to the user's iCloud private database. Requires the iCloud entitlement
    /// to be present in the host app's signing.
    public static func make(cloudKitSync: Bool) throws -> ModelContainer {
        let schema = Schema(FocusSchema.allModels)
        let cloud: ModelConfiguration.CloudKitDatabase =
            cloudKitSync ? .private(cloudKitContainerID) : .none

        let config = ModelConfiguration(
            schema: schema,
            isStoredInMemoryOnly: false,
            cloudKitDatabase: cloud
        )
        return try ModelContainer(for: schema, configurations: [config])
    }
}
