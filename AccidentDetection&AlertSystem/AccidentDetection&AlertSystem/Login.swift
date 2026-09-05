import SwiftUI

struct LoginView: View {
    
    var onLoginSuccess: (String, String) -> Void
    var onShowSignup: () -> Void
    var onShowForgotPassword: () -> Void
    
    @State private var email: String = ""
    @State private var password: String = ""
    @State private var message: String = ""
    
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
                        Image(systemName: "checkmark.shield.fill")
                            .resizable()
                            .scaledToFit()
                            .frame(width: 35, height: 35)
                            .foregroundColor(.white)
                    )
                // Title
                Text("Accident Detection")
                    .font(.title2.weight(.bold))
                
                Text("Login to your account")
                    .foregroundColor(.gray)
                
                // Card Style Box
                VStack(spacing: 15) {
                  
                    
                    // Email
                    VStack(alignment: .leading) {
                        Text("Email")
                            .font(.caption)
                        
                        TextField("Enter your email", text: $email)
                            .padding()
                            .background(Color(.systemGray6))
                            .cornerRadius(10)
                    }
                    
                    // Password
                    VStack(alignment: .leading) {
                        HStack {
                            Text("Password")
                                .font(.caption)
                            
                            Spacer()
                            
                            Button("Forgot?") {
                                onShowForgotPassword()
                            }
                            .font(.caption)
                            .foregroundColor(.blue)
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
                            Text("Login")
                                .font(.body.weight(.semibold))
                        }
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(
                            LinearGradient(
                                colors: [Color.red, Color.orange],
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
            message = "Please enter both email and password"
            return
        }
        
        // ✅ Email validation
        if !isValidEmail(email) {
            message = "Please enter a valid email address"
            return
        }
        
        if email == ADMIN_EMAIL && password == ADMIN_PASSWORD {
            message = "Welcome Admin!"
                onLoginSuccess("admin", email)
        } else {
            loginUser()
        }
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
                        
                        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                            onLoginSuccess(loggedInUser.role.lowercased(), loggedInUser.uid)
                        }
                    } else {
                        message = "Login successful!"
                        
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
