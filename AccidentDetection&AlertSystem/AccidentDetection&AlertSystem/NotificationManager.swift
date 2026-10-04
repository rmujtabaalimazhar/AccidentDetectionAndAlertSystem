import Foundation
import UserNotifications
import UIKit
import BackgroundTasks
import Combine

class NotificationManager: NSObject, ObservableObject, UNUserNotificationCenterDelegate {
    static let shared = NotificationManager()
    
    static let backgroundTaskIdentifier = "com.fyp.accidentdetection.alertcheck"
    
    // Deep-linking / navigation state
    @Published var activeAlertId: Int? = nil
    @Published var navigateToAlerts: Bool = false
    @Published var deviceToken: String? = nil
    
    private var pollingTimer: Timer?
    private var lastSeenAlertId: Int {
        get { UserDefaults.standard.integer(forKey: "lastSeenAlertId") }
        set { UserDefaults.standard.set(newValue, forKey: "lastSeenAlertId") }
    } 
    
    var currentUserRole: String? {
        UserDefaults.standard.string(forKey: "savedUserRole")
    }
    
    var currentUserIdentifier: String? {
        UserDefaults.standard.string(forKey: "savedUserIdentifier")
    }
    
    private override init() {
        super.init()
        UNUserNotificationCenter.current().delegate = self
    }
    
    // MARK: - Permissions & Remote Notifications
    
    func requestAuthorization() {
        let center = UNUserNotificationCenter.current()
        center.requestAuthorization(options: [.alert, .sound, .badge]) { granted, error in
            if let error = error {
                print("[NotificationManager] Authorization error: \(error.localizedDescription)")
            } else if granted {
                print("[NotificationManager] Notification permissions granted.")
                DispatchQueue.main.async {
                    UIApplication.shared.registerForRemoteNotifications()
                }
            } else {
                print("[NotificationManager] Notification permissions denied.")
            }
        }
    }
     
    func didRegisterRemoteToken(_ tokenData: Data) {
        let tokenString = tokenData.map { String(format: "%02.2hhx", $0) }.joined()
        self.deviceToken = tokenString
        UserDefaults.standard.set(tokenString, forKey: "savedDeviceToken")
        print("[NotificationManager] Registered Device Token: \(tokenString)")
        
        
        // Sync with backend if user already logged in
        if let role = currentUserRole, let id = currentUserIdentifier {
            syncTokenWithBackend(token: tokenString, role: role, identifier: id)
        }
    }
    
    func setUserSession(role: String, identifier: String) {
        UserDefaults.standard.set(role, forKey: "savedUserRole")
        UserDefaults.standard.set(identifier, forKey: "savedUserIdentifier")
        
        // Sync cached device token if available
        let token = deviceToken ?? UserDefaults.standard.string(forKey: "savedDeviceToken") ?? UUID().uuidString
        syncTokenWithBackend(token: token, role: role, identifier: identifier)
        
        // Start proactive polling for alerts while app is active or in background
        startActivePolling()
        
        // Request authorization if not done already
        requestAuthorization()
    }
    
    func clearUserSession() {
        UserDefaults.standard.removeObject(forKey: "savedUserRole")
        UserDefaults.standard.removeObject(forKey: "savedUserIdentifier")
        stopActivePolling()
    }
    
    // MARK: - Backend Token Sync
    
    func syncTokenWithBackend(token: String, role: String, identifier: String) {
        guard let url = URL(string: "\(AppConfig.apiBaseURL)/Notifications/RegisterToken") else { return }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let normalizedType: String
        if role.lowercased() == "rescue" {
            normalizedType = "Rescue"
        } else {
            normalizedType = "Guardian"
        }
        
        let body: [String: Any] = [
            "UserIdentifier": identifier,
            "UserType": normalizedType,
            "Token": token,
            "Platform": "iOS"
        ]
        
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)
        
        URLSession.shared.dataTask(with: request) { data, response, error in
            if let error = error {
                print("[NotificationManager] Failed to register token: \(error.localizedDescription)")
            } else {
                print("[NotificationManager] Device token successfully registered on backend.")
            }
        }.resume()
    }
    
    // MARK: - Polling & Checking Alerts (Foreground / Background)
    
    func startActivePolling() {
        stopActivePolling()
        // Check every 10 seconds while active or running in background
        pollingTimer = Timer.scheduledTimer(withTimeInterval: 10.0, repeats: true) { [weak self] _ in
            self?.checkForNewAlerts()
        }
        // Run first check immediately
        checkForNewAlerts()
    }
    
    func stopActivePolling() {
        pollingTimer?.invalidate()
        pollingTimer = nil
    }
    
    func checkForNewAlerts(completion: ((Bool) -> Void)? = nil) {
        guard let role = currentUserRole, let identifier = currentUserIdentifier else {
            completion?(false)
            return
        }
        
        let userType = (role.lowercased() == "rescue") ? "Rescue" : "Guardian"
        let encodedId = identifier.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? identifier
        let currentLastId = self.lastSeenAlertId
        
        let urlString = "\(AppConfig.apiBaseURL)/Notifications/CheckPending?userType=\(userType)&id=\(encodedId)&lastAlertId=\(currentLastId)"
        guard let url = URL(string: urlString) else {
            completion?(false)
            return
        }
        
        URLSession.shared.dataTask(with: url) { [weak self] data, response, error in
            guard let self = self, let data = data, error == nil else {
                completion?(false)
                return
            }
            
            do {
                if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let hasNew = json["hasNewAlerts"] as? Bool, hasNew,
                   let alerts = json["alerts"] as? [[String: Any]], !alerts.isEmpty {
                    
                    var maxAlertId = currentLastId
                    
                    for alert in alerts {
                        let alertId = alert["alertId"] as? Int ?? 0
                        let accidentId = alert["accidentId"] as? Int ?? 0
                        let driverName = alert["driverName"] as? String ?? "Driver"
                        let carMake = alert["carMake"] as? String ?? "Vehicle"
                        let plateNo = alert["plateNumber"] as? String ?? ""
                        let location = alert["location"] as? String ?? "Unknown"
                        let severity = alert["severity"] as? String ?? "High"
                        let impactForce = alert["impactForce"] as? Double ?? 0
                        
                        if alertId > maxAlertId {
                            maxAlertId = alertId
                        }
                        
                        // Fire native system notification popup
                        let title: String
                        let body: String
                        if userType == "Rescue" {
                            title = "🚑 PRIORITY RESCUE DISPATCH!"
                            body = "Crash detected for \(driverName) (\(carMake) #\(plateNo)) at \(location). Severity: \(severity), Force: \(Int(impactForce))N. Tap to respond."
                        } else {
                            title = "🚨 EMERGENCY: Family Accident Alert!"
                            body = "\(driverName) was involved in an accident! Location: \(location) (Severity: \(severity)). Tap to view details and track."
                        }
                        
                        self.fireLocalEmergencyNotification(
                            title: title,
                            body: body,
                            alertId: alertId,
                            accidentId: accidentId
                        )
                    }
                    
                    self.lastSeenAlertId = maxAlertId
                    completion?(true)
                } else {
                    completion?(false)
                }
            } catch {
                print("[NotificationManager] Error decoding pending alerts: \(error)")
                completion?(false)
            }
        }.resume()
    }
    
    // MARK: - System Notification Dispatch
    
    func fireLocalEmergencyNotification(title: String, body: String, alertId: Int, accidentId: Int) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = UNNotificationSound.defaultCritical
        content.badge = 1
        content.categoryIdentifier = "EMERGENCY_ALERT_CATEGORY"
        content.userInfo = [
            "alertId": alertId,
            "accidentId": accidentId,
            "type": "accident_alert"
        ]
        
        // Immediate trigger (0.1s)
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 0.1, repeats: false)
        let request = UNNotificationRequest(
            identifier: "EmergencyAlert_\(alertId)_\(Date().timeIntervalSince1970)",
            content: content,
            trigger: trigger
        )
        
        UNUserNotificationCenter.current().add(request) { error in
            if let error = error {
                print("[NotificationManager] Error scheduling notification: \(error.localizedDescription)")
            } else {
                print("[NotificationManager] Emergency popup notification scheduled for Alert #\(alertId).")
            }
        }
    }
    
    // MARK: - Background Tasks Scheduling
    
    func scheduleBackgroundAlertCheck() {
        let request = BGAppRefreshTaskRequest(identifier: NotificationManager.backgroundTaskIdentifier)
        // Request earliest trigger in 1 minute
        request.earliestBeginDate = Date(timeIntervalSinceNow: 60)
        
        do {
            try BGTaskScheduler.shared.submit(request)
            print("[NotificationManager] Background alert check scheduled successfully.")
        } catch {
            print("[NotificationManager] Could not schedule background task: \(error.localizedDescription)")
        }
    }
    
    func handleBackgroundAppRefresh(task: BGAppRefreshTask) {
        // Schedule next background check
        scheduleBackgroundAlertCheck()
        
        task.expirationHandler = {
            task.setTaskCompleted(success: false)
        }
        
        checkForNewAlerts { hasNew in
            task.setTaskCompleted(success: hasNew)
        }
    }
    
    // MARK: - UNUserNotificationCenterDelegate
    
    // Always present banner and sound even when app is open (foreground)
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        if #available(iOS 14.0, *) {
            completionHandler([.banner, .sound, .badge, .list])
        } else {
            completionHandler([.alert, .sound, .badge])
        }
    }
    
    // Handle user tapping on the popup notification (from closed, background, or lock screen)
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let userInfo = response.notification.request.content.userInfo
        print("[NotificationManager] User tapped notification with userInfo: \(userInfo)")
        
        if let alertId = userInfo["alertId"] as? Int {
            DispatchQueue.main.async {
                self.activeAlertId = alertId
                self.navigateToAlerts = true
            }
        }
        
        completionHandler()
    }
}
