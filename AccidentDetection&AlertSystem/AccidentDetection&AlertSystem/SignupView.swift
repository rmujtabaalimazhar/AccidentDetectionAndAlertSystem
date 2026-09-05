import SwiftUI

struct SignupView: View {
    
    var onBackToLogin: () -> Void
    var onSignupSuccess: () -> Void
    
    @State private var name: String = ""
    @State private var contact: String = ""
    @State private var email: String = ""
    @State private var password: String = ""
    @State private var message: String = ""
    
    var body: some View {
        ZStack {
            // Background Gradient
            LinearGradient(
                colors: [Color.red.opacity(0.1), Color.orange.opacity(0.1)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()
            
            VStack(spacing: 20) {
                
                // Back Button
                HStack {
                    Button("← Back") {
                        onBackToLogin()
                    }
                    Spacer()
                }
                .padding(.horizontal)
                
                Spacer()
                
                // Icon
                Circle()
                    .fill(LinearGradient(
                        colors: [Color.red, Color.orange],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing))
                    .frame(width: 70, height: 70)
                    .overlay(
                        Image(systemName: "person.badge.plus")
                            .font(.system(size: 28))
                            .foregroundColor(.white)
                    )
                Text("Create Account")
                    .font(.title2.weight(.bold))
                
                Text("Register to get started")
                    .foregroundColor(.gray)
                
                // Form Card
                VStack(spacing: 15) {
                    
                    // Name
                    HStack(spacing: 15) {
                        Image(systemName: "person")
                            .foregroundColor(.blue)
                        
                        TextField("Full Name", text: $name)
                    }
                    .padding()
                    .background(Color(.systemGray6))
                    .cornerRadius(10)
                    
                    
                    // Contact
                    HStack(spacing: 15) {
                        Image(systemName: "phone")
                            .foregroundColor(.blue)
                        
                        TextField("Contact Number", text: $contact)
                            .keyboardType(.phonePad)
                    }
                    .padding()
                    .background(Color(.systemGray6))
                    .cornerRadius(10)
                    
                    
                    // Email
                    HStack(spacing: 15) {
                        Image(systemName: "envelope")
                            .foregroundColor(.blue)
                        
                        TextField("Email", text: $email)
                            .keyboardType(.emailAddress)
                            .autocapitalization(.none)
                    }
                    .padding()
                    .background(Color(.systemGray6))
                    .cornerRadius(10)
                    
                    
                    // Password
                    HStack(spacing: 15) {
                        Image(systemName: "lock")
                            .foregroundColor(.blue)
                        
                        SecureField("Password", text: $password)
                    }
                    .padding()
                    .background(Color(.systemGray6))
                    .cornerRadius(10)
                    
                    
                    // Register Button
                    Button(action: handleSubmit) {
                        HStack {
                            Image(systemName: "person.badge.plus")
                            Text("Register")
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
                    
                    // Message
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
                
                Spacer()
            }
            .padding()
        }
    }
    
    
    //func  for correct input pattern
    func isValidEmail(_ email: String) -> Bool {
        let emailRegex = "^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\\.[A-Za-z]{2,}$"
        return NSPredicate(format: "SELF MATCHES %@", emailRegex).evaluate(with: email)
    }
    
    func isValidPhone(_ phone: String) -> Bool {
        let phoneRegex = "^[0-9]{11}$"
        return NSPredicate(format: "SELF MATCHES %@", phoneRegex).evaluate(with: phone)
    }
    
    
    // MARK: - Logic
    
    func handleSubmit() {
        if name.isEmpty || contact.isEmpty || email.isEmpty || password.isEmpty {
            message = "Please fill all fields"
            return
        }
        
        // Phone validation
        if !isValidPhone(contact) {
            message = "Phone must be 11 digits"
            return
        }
        
        // Email validation
        if !isValidEmail(email) {
            message = "Invalid email format"
            return
        }
        
        // Call the backend API
        registerUser()
    }
    
    func registerUser() {
        // IMPORTANT: If testing on a physical iOS device, replace "localhost" with your Mac's local IP address (e.g., 192.168.1.100).
        // Since launchsettings.json defines the http port as 5192, we use that here.
        guard let url = URL(string: "\(AppConfig.apiBaseURL)/Auth/CreateUser") else {
            message = "Invalid API URL"
            return
        }
        
        // Prepare the user model object
        let newUser = User(
            uid: email,           // Uid acts as email in the database
            name: name,
            password: password,
            role: "User",         // Default role
            contactNo: contact
        )
        
        guard let jsonData = try? JSONEncoder().encode(newUser) else {
            message = "Failed to encode user data"
            return
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = jsonData
        
        // Perform the network request
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
                
                // 201 Created is the standard response for a successful POST creation
                if (200...299).contains(httpResponse.statusCode) {
                    message = "Registration Successful!"
                    
                    // Delay slightly to let the user read the success message
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                        onSignupSuccess()
                    }
                } else {
                    message = "Registration failed. Server returned status: \(httpResponse.statusCode)"
                }
            }
        }.resume()
    }
}
#Preview {
    SignupView(
        onBackToLogin: {},
        onSignupSuccess: {}
    )
}
