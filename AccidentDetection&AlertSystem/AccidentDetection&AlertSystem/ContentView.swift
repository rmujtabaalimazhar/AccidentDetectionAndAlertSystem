import SwiftUI

enum AppState {
    case login
    case signup
    case forgotPassword
    case selectVehicle
    case adminDashboard
    case rescueAlerts
}

struct ContentView: View {
    
    @ObservedObject private var notificationManager = NotificationManager.shared
    @State private var appState: AppState = .login
    @State private var loggedInUid: String = ""
    @State private var showGuardianAlertsSheet: Bool = false
    
    var body: some View {
        ZStack {
            mainContent
        }
        .onAppear {
            restoreSessionIfAvailable()
        }
        .onReceive(notificationManager.$navigateToAlerts) { shouldNavigate in
            if shouldNavigate {
                handleNotificationDeepLink()
            }
        }
        .sheet(isPresented: $showGuardianAlertsSheet) {
            AlertsView(
                mode: .guardian,
                identifier: loggedInUid,
                onLogout: {
                    showGuardianAlertsSheet = false
                    logout()
                },
                onDismiss: {
                    showGuardianAlertsSheet = false
                }
            )
        }
    }
    
    @ViewBuilder
    private var mainContent: some View {
        switch appState {
            
        case .login:
            LoginView(
                onLoginSuccess: { role, uid in
                    loggedInUid = uid
                    if role == "admin" {
                        appState = .adminDashboard
                    } else if role == "rescue" {
                        appState = .rescueAlerts
                    } else { 
                        appState = .selectVehicle
                    }
                },
                
                onShowSignup: {
                    appState = .signup
                },
                
                onShowForgotPassword: {
                    appState = .forgotPassword
                }
            )
            
        case .signup:
            SignupView(
                onBackToLogin: {
                    appState = .login
                },
                onSignupSuccess: {
                    appState = .login
                }
            )
            
        case .forgotPassword:
            ForgotPasswordView(
                onBackToLogin: {
                    appState = .login
                },
                onSuccess: { _ in
                    appState = .login
                }
            )
            
        case .selectVehicle:
            VehicleScreen(uid: loggedInUid, onLogout: logout)
            
        case .adminDashboard:
            AdminDashboard(onLogout: logout)
            
        case .rescueAlerts:
            AlertsView(mode: .rescue, identifier: loggedInUid, onLogout: logout)
        }
    }
    
    private func logout() {
        notificationManager.clearUserSession()
        loggedInUid = ""
        appState = .login
    }
    
    private func restoreSessionIfAvailable() {
        if let savedRole = notificationManager.currentUserRole,
           let savedId = notificationManager.currentUserIdentifier,
           !savedId.isEmpty {
            loggedInUid = savedId
            if savedRole.lowercased() == "admin" {
                appState = .adminDashboard
            } else if savedRole.lowercased() == "rescue" {
                appState = .rescueAlerts
            } else {
                appState = .selectVehicle
            }
        }
    }
    
    private func handleNotificationDeepLink() {
        guard !loggedInUid.isEmpty else { return }
        
        let role = notificationManager.currentUserRole?.lowercased() ?? ""
        if role == "rescue" {
            appState = .rescueAlerts
        } else {
            showGuardianAlertsSheet = true
        }
        
        notificationManager.navigateToAlerts = false
    }
}

#Preview {
    ContentView()
}
