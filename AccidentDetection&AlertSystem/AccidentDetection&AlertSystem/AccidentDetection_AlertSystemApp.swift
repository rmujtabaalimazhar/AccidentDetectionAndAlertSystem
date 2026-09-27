//
//  AccidentDetection_AlertSystemApp.swift
//  AccidentDetection&AlertSystem
//
//  Created by M@C on 03/04/2026.
//

import SwiftUI
import UIKit
import BackgroundTasks

class AppDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey : Any]? = nil
    ) -> Bool {
        // Register background task for alert polling when app is closed / suspended
        BGTaskScheduler.shared.register(
            forTaskWithIdentifier: NotificationManager.backgroundTaskIdentifier,
            using: nil
        ) { task in
            if let refreshTask = task as? BGAppRefreshTask {
                NotificationManager.shared.handleBackgroundAppRefresh(task: refreshTask)
            }
        }
        
        // Request notification permissions
        NotificationManager.shared.requestAuthorization()
        
        // Resume alert polling if user was already logged in
        if NotificationManager.shared.currentUserIdentifier != nil {
            NotificationManager.shared.startActivePolling()
        }
        
        return true
    }
    
    func application(
        _ application: UIApplication,
        didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data
    ) {
        NotificationManager.shared.didRegisterRemoteToken(deviceToken)
    }
    
    func application(
        _ application: UIApplication,
        didFailToRegisterForRemoteNotificationsWithError error: Error
    ) {
        print("[AppDelegate] Failed to register for remote notifications: \(error.localizedDescription)")
    }
    
    // Background fetch handler when remote notification or silent background wake arrives
    func application(
        _ application: UIApplication,
        didReceiveRemoteNotification userInfo: [AnyHashable : Any],
        fetchCompletionHandler completionHandler: @escaping (UIBackgroundFetchResult) -> Void
    ) {
        print("[AppDelegate] Received remote notification in background: \(userInfo)")
        NotificationManager.shared.checkForNewAlerts { hasNew in
            completionHandler(hasNew ? .newData : .noData)
        }
    }
    
    func applicationDidEnterBackground(_ application: UIApplication) {
        NotificationManager.shared.scheduleBackgroundAlertCheck()
    }
}

@main
struct AccidentDetection_AlertSystemApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var notificationManager = NotificationManager.shared
    
    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(notificationManager)
        }
    }
}
