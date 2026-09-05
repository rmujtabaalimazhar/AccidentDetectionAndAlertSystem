

import SwiftUI

enum AppState {
    case login
    case signup
    case forgotPassword
    case selectVehicle
    case adminDashboard
}

struct ContentView: View {
    
    @State private var appState: AppState = .login
    @State private var loggedInUid: String = ""
    
    var body: some View {
        switch appState {
            
        case .login:
            LoginView(
                onLoginSuccess: { role, uid in
                    loggedInUid = uid
                    if role == "admin" {
                        appState = .adminDashboard
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
            VehicleScreen(uid: loggedInUid, onLogout: { appState = .login })
            
        case .adminDashboard:
            AdminDashboard(onLogout: { appState = .login })
        }
    }
}

#Preview {
    ContentView()
}
