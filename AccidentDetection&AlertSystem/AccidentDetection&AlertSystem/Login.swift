import SwiftUI

struct LoginView: View {
    
    var onLoginSuccess: (String, String) -> Void
    var onShowSignup: () -> Void
    var onShowForgotPassword: () -> Void
    
    @State private var email: String = ""
    @State private var password: String = ""
    @State private var message: String = ""
    @State private var isRescueLogin: Bool = false
    
    let ADMIN_EMAIL = "admin@gmail.com"
    let ADMIN_PASSWORD = "admin1234"
    
    var body: some View {
        ZStack {
            // Background Gradient
            LinearGradient(
                colors: [Color.red.opacity(0.2), Color.orange.opacity(0.3)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()
            
            VStack(spacing: 20) {
                
                Spacer()
                
                // Logo
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [Color.red, Color.orange],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 80, height: 80)
                    .overlay(
                        Image(systemName: isRescueLogin ? "cross.case.fill" : "checkmark.shield.fill")
                            .resizable()
                            .scaledToFit()
                            .frame(width: 35, height: 35)
                            .foregroundColor(.white)
                    )
                // Title
                Text(isRescueLogin ? "Rescue Portal" : "Accident Detection")
                    .font(.title2.weight(.bold))
                
                Text(isRescueLogin ? "Login to access emergency dispatches" : "Login to your account")
                    .foregroundColor(.gray)
                
                // Segmented control
                Picker("Account Type", selection: $isRescueLogin) {
                    Text("Driver / User").tag(false)
                    Text("Rescue Team").tag(true)
                }
                .pickerStyle(SegmentedPickerStyle())
                .padding(.horizontal)
                
                // Card Style Box
                VStack(spacing: 15) {
                    
                    // Identifier Field
                    VStack(alignment: .leading) {
                        Text(isRescueLogin ? "Rescue ID (Rid)" : "Email")
                            .font(.caption)
                        
                        TextField(isRescueLogin ? "Enter your Rescue ID (e.g. 1)" : "Enter your email", text: $email)
                            .padding()
                            .background(Color(.systemGray6))
                            .cornerRadius(10)
                            .autocapitalization(.none)
                            .keyboardType(isRescueLogin ? .numberPad : .emailAddress)
                    }
                    
                    // Password
                    VStack(alignment: .leading) {
                        HStack {
                            Text("Password")
                                .font(.caption)
                            
                            Spacer()
                            
                            if !isRescueLogin {
                                Button("Forgot?") {
                                    onShowForgotPassword()
                                }
                                .font(.caption)
                                .foregroundColor(.blue)
                            }
                        }
                        
                        SecureField("Enter your password", text: $password)
                            .padding()
                            .background(Color(.systemGray6))
                            .cornerRadius(10)
                    }
                    
                    // Login Button
                    Button(action: handleLogin) {
                        HStack {
                            Image(systemName: "arrow.right.circle")
                            Text(isRescueLogin ? "Login as Rescue" : "Login")
                                .font(.body.weight(.semibold))
                        }
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(
                            LinearGradient(
                                colors: isRescueLogin ? [Color.red, Color.purple] : [Color.red, Color.orange],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .foregroundColor(.white)
                        .cornerRadius(10)
                    }
                    
                    // Message (Toast replacement)
                    if !message.isEmpty {
                        Text(message)
                            .foregroundColor(.red)
                            .font(.caption)
                    }
                }
                .padding()
                .background(Color.white)
                .cornerRadius(15)
                .shadow(radius: 5)
                
                // Signup
                HStack {
                    Text("Don't have an account?")
                    
                    Button("Register Now") {
                        onShowSignup()
                    }
                    .foregroundColor(.red)
                    .font(.footnote.weight(.semibold))
                }
                .font(.footnote)
                
                Spacer()
            }
            .padding()
        }
    }
    
    func isValidEmail(_ email: String) -> Bool {
        let emailRegex = "^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\\.[A-Za-z]{2,}$"
        return NSPredicate(format: "SELF MATCHES %@", emailRegex).evaluate(with: email)
    }
    // MARK: - Logic (Same as React)
    
    func handleLogin() {
        if email.isEmpty || password.isEmpty {
            message = "Please enter both credentials"
            return
        }
        
        if isRescueLogin {
            loginRescue()
            return
        }
        
        // ✅ Email validation for regular user
        if !isValidEmail(email) {
            message = "Please enter a valid email address"
            return
        }
        
        if email == ADMIN_EMAIL && password == ADMIN_PASSWORD {
            message = "Welcome Admin!"
            NotificationManager.shared.setUserSession(role: "admin", identifier: email)
            onLoginSuccess("admin", email)
        } else {
            loginUser()
        }
    }
    
    func loginRescue() {
        guard let rid = Int(email.trimmingCharacters(in: .whitespaces)), rid > 0 else {
            message = "Please enter a valid numeric Rescue ID (e.g. 1)"
            return
        }
        
        guard let url = URL(string: "\(AppConfig.apiBaseURL)/Rescue/Login") else {
            message = "Invalid API URL"
            return
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let body: [String: Any] = [
            "Rid": rid,
            "Password": password
        ]
        
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)
        
        URLSession.shared.dataTask(with: request) { data, response, error in
            DispatchQueue.main.async {
                if let error = error {
                    message = "Network error: \(error.localizedDescription)"
                    return
                }
                guard let httpResponse = response as? HTTPURLResponse else {
                    message = "Invalid response from server"
                    return
                }
                if (200...299).contains(httpResponse.statusCode) {
                    message = "Rescue verified! Loading dispatches..."
                    NotificationManager.shared.setUserSession(role: "rescue", identifier: String(rid))
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
                        onLoginSuccess("rescue", String(rid))
                    }
                } else {
                    message = "Invalid Rescue ID or password"
                }
            }
        }.resume()
    }
    
    func loginUser() {
        // Build the URL with query parameters since the ASP.NET backend expects string arguments
        guard var urlComponents = URLComponents(string: "\(AppConfig.apiBaseURL)/Auth/Login") else {
            message = "Invalid API URL"
            return
        }
        
        urlComponents.queryItems = [
            URLQueryItem(name: "email", value: email),
            URLQueryItem(name: "pas", value: password)
        ]
        
        guard let url = urlComponents.url else {
            message = "Invalid parameters"
            return
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        
        URLSession.shared.dataTask(with: request) { data, response, error in
            DispatchQueue.main.async {
                if let error = error {
                    message = "Network error: \(error.localizedDescription)"
                    return
                }
                
                guard let httpResponse = response as? HTTPURLResponse else {
                    message = "Invalid response from server"
                    return
                }
                
                if (200...299).contains(httpResponse.statusCode) {
                    if let data = data, let loggedInUser = try? JSONDecoder().decode(User.self, from: data) {
                        message = "Welcome \(loggedInUser.name)!"
                        NotificationManager.shared.setUserSession(role: loggedInUser.role.lowercased(), identifier: loggedInUser.uid)
                        
                        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                            onLoginSuccess(loggedInUser.role.lowercased(), loggedInUser.uid)
                        }
                    } else {
                        message = "Login successful!"
                        NotificationManager.shared.setUserSession(role: "user", identifier: email)
                        
                        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                            onLoginSuccess("user", email)
                        }
                    }
                } else if httpResponse.statusCode == 401 {
                    message = "Invalid email or password"
                } else if httpResponse.statusCode >= 500 {
                    message = "Server error occurred. Please try again later."
                    print("Server Exception:", String(data: data ?? Data(), encoding: .utf8) ?? "No data")
                } else {
                    if let data = data, let errorMessage = String(data: data, encoding: .utf8), !errorMessage.isEmpty {
                        message = errorMessage
                    } else {
                        message = "Login failed. Server returned status: \(httpResponse.statusCode)"
                    }
                }
            }
        }.resume()
    }}

#Preview {
    LoginView(
        onLoginSuccess: { role, uid in
            print("Logged in as \(role) with uid \(uid)")
        },
        onShowSignup: {
            print("Go to Signup")
        },
        onShowForgotPassword: {
            print("Go to Forgot Password")
        }
    )
}
