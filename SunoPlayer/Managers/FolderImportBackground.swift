import Foundation
import BackgroundTasks
import UIKit

enum FolderImportBackground {
    static let identifier = "com.thomas.sunoplayer.folder-import"
}

final class SunoPlayerAppDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        BGTaskScheduler.shared.register(
            forTaskWithIdentifier: FolderImportBackground.identifier,
            using: nil
        ) { task in
            guard let processing = task as? BGProcessingTask else {
                task.setTaskCompleted(success: false)
                return
            }
            Task { @MainActor in
                FolderImportCoordinator.shared.handleBackgroundTask(processing)
            }
        }
        return true
    }
}
