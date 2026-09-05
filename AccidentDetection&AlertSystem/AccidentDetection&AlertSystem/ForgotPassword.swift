import SwiftUI

struct ForgotPasswordView: View {
    
    // MARK: - Callbacks
    var onBackToLogin: () -> Void
    var onSuccess: (String) -> Void
    
    // MARK: - State
    @State private var email = ""
    @State private var newPassword = ""
    @State private var confirmPassword = ""
    
    @State private var isLoading = false
    @State private var alertMessage = ""
    @State private var showAlert = false
    
    var body: some View {
        VStack {
            resetFormView
        }
        .alert(isPresented: $showAlert) {
            Alert(
                title: Text("Error"),
                message: Text(alertMessage),
                dismissButton: .default(Text("OK"))
            )
        }
    }
    
    // MARK: - UI
    var resetFormView: some View {
        VStack(spacing: 20) {
            
            // Back button
            HStack {
                Button(action: {
                    onBackToLogin()
                }) {
                    HStack {
                        Image(systemName: "arrow.left")
                        Text("Back")
                    }
                }
                Spacer()
            }
            .padding()
            
            Image(systemName: "key.fill")
                .resizable()
                .frame(width: 50, height: 70)
                .foregroundColor(.blue)
            
            Text("Reset Password")
                .font(.title)
                .bold()
            
            Text("Enter your email and new password")
                .font(.subheadline)
                .foregroundColor(.gray)
            
            VStack(spacing: 15) {
                
                TextField("Email Address", text: $email)
                    .keyboardType(.emailAddress)
                    .autocapitalization(.none)
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                
                SecureField("New Password", text: $newPassword)
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                
                SecureField("Confirm Password", text: $confirmPassword)
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                
                Text("Must be at least 6 characters long")
                    .font(.caption)
                    .foregroundColor(.gray)
                    .frame(maxWidth: .infinity, alignment: .leading)
                
                Button(action: {
                    handleResetPassword()
                }) {
                    HStack {
                        if isLoading {
                            ProgressView()
                        } else {
                            Image(systemName: "key.fill")
                            Text("Reset Password")
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.blue)
                    .foregroundColor(.white)
                    .cornerRadius(10)
                }
                .disabled(isLoading)
            }
            .padding()
            
            Spacer()
        }
        .padding()
    }
    
    // MARK: - Validation
    func handleResetPassword() {
        
        if email.isEmpty || newPassword.isEmpty || confirmPassword.isEmpty {
            showError("Please fill in all fields")
            return
        }
        
        let emailRegex = #"^[^\s@]+@[^\s@]+\.[^\s@]+$"#
        let emailPredicate = NSPredicate(format: "SELF MATCHES %@", emailRegex)
        
        if !emailPredicate.evaluate(with: email) {
            showError("Please enter a valid email address")
            return
        }
        
        if newPassword != confirmPassword {
            showError("Passwords do not match")
            return
        }
        
        if newPassword.count < 6 {
            showError("Password must be at least 6 characters long")
            return
        }
        
        // API call to C# backend
        isLoading = true
        
        // Build the URL with query parameters
        guard var urlComponents = URLComponents(string: "\(AppConfig.apiBaseURL)/Auth/ForgotPassword") else {
            showError("Invalid API URL")
            isLoading = false
            return
        }
        
        urlComponents.queryItems = [
            URLQueryItem(name: "email", value: email),
            URLQueryItem(name: "newPassword", value: newPassword),
            URLQueryItem(name: "confirmPassword", value: confirmPassword)
        ]
        
        guard let url = urlComponents.url else {
            showError("Invalid parameters")
            isLoading = false
            return
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        
        URLSession.shared.dataTask(with: request) { data, response, error in
            DispatchQueue.main.async {
                isLoading = false
                
                if let error = error {
                    showError("Network error: \(error.localizedDescription)")
                    return
                }
                
                guard let httpResponse = response as? HTTPURLResponse else {
                    showError("Invalid response from server")
                    return
                }
                
                if (200...299).contains(httpResponse.statusCode) {
                    // Password updated successfully! Redirect to login screen.
                    onSuccess(email)
                } else {
                    // Try to extract the error message from the backend (e.g., "Email not found")
                    if let data = data, let errorMessage = String(data: data, encoding: .utf8), !errorMessage.isEmpty {
                        showError(errorMessage)
                    } else {
                        showError("Failed to reset password. Server returned status: \(httpResponse.statusCode)")
                    }
                }
            }
        }.resume()
    }
    
    func showError(_ message: String) {
        alertMessage = message
        showAlert = true
    }
}
