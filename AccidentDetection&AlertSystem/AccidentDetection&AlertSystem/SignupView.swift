import SwiftUI

struct SignupView: View {
    
    var onBackToLogin: () -> Void
    var onSignupSuccess: () -> Void
    
    @State private var name: String = ""
    @State private var contact: String = ""
    @State private var email: String = ""
    @State private var password: String = ""
    @State private var message: String = ""
    @State private var isRescueSignup: Bool = false
    @State private var rescueLocation: String = ""
    @StateObject private var geo = GeolocationService.shared
    
    var body: some View {
        ZStack {
            // Background Gradient
            LinearGradient(
                colors: [Color.red.opacity(0.1), Color.orange.opacity(0.1)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()
            
            VStack(spacing: 16) {
                
                // Back Button
                HStack {
                    Button("← Back") {
                        onBackToLogin()
                    }
                    Spacer()
                }
                .padding(.horizontal)
                
                // Icon
                Circle()
                    .fill(LinearGradient(
                        colors: [Color.red, Color.orange],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing))
                    .frame(width: 64, height: 64)
                    .overlay(
                        Image(systemName: isRescueSignup ? "cross.case.fill" : "person.badge.plus")
                            .font(.system(size: 26))
                            .foregroundColor(.white)
                    )
                Text(isRescueSignup ? "Register Rescue Unit" : "Create Account")
                    .font(.title2.weight(.bold))
                
                Text(isRescueSignup ? "Register your rescue team with current location" : "Register to get started")
                    .foregroundColor(.gray)
                    .font(.caption)
                
                // Segmented picker
                Picker("Account Type", selection: $isRescueSignup) {
                    Text("Driver / User").tag(false)
                    Text("Rescue Team").tag(true)
                }
                .pickerStyle(SegmentedPickerStyle())
                .padding(.horizontal)
                
                // Form Card
                VStack(spacing: 14) {
                    
                    if !isRescueSignup {
                        // Regular user fields
                        HStack(spacing: 15) {
                            Image(systemName: "person").foregroundColor(.blue)
                            TextField("Full Name", text: $name)
                        }
                        .padding(12).background(Color(.systemGray6)).cornerRadius(10)
                        
                        HStack(spacing: 15) {
                            Image(systemName: "phone").foregroundColor(.blue)
                            TextField("Contact Number", text: $contact)
                                .keyboardType(.phonePad)
                        }
                        .padding(12).background(Color(.systemGray6)).cornerRadius(10)
                        
                        HStack(spacing: 15) {
                            Image(systemName: "envelope").foregroundColor(.blue)
                            TextField("Email", text: $email)
                                .keyboardType(.emailAddress)
                                .autocapitalization(.none)
                        }
                        .padding(12).background(Color(.systemGray6)).cornerRadius(10)
                    } else {
                        // Rescue specific location field
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                Text("Current Rescue Base Location").font(.caption.weight(.semibold)).foregroundColor(.gray)
                                Spacer()
                                if let coord = geo.currentCoordinate {
                                    Button("Use GPS") {
                                        rescueLocation = GeolocationService.formatCoordinate(coord)
                                    }
                                    .font(.caption2.bold())
                                    .foregroundColor(.blue)
                                }
                            }
                            
                            HStack(spacing: 12) {
                                Image(systemName: "location.fill").foregroundColor(.red)
                                TextField("e.g. 33.6844,73.0479", text: $rescueLocation)
                                    .autocapitalization(.none)
                            }
                            .padding(12).background(Color(.systemGray6)).cornerRadius(10)
                        }
                    }
                    
                    // Password
                    HStack(spacing: 15) {
                        Image(systemName: "lock").foregroundColor(.blue)
                        SecureField("Password", text: $password)
                    }
                    .padding(12).background(Color(.systemGray6)).cornerRadius(10)
                    
                    // Register Button
                    Button(action: handleSubmit) {
                        HStack {
                            Image(systemName: isRescueSignup ? "cross.case.fill" : "person.badge.plus")
                            Text(isRescueSignup ? "Register Rescue Unit" : "Register")
                                .font(.body.weight(.semibold))
                        }
                        .frame(maxWidth: .infinity)
                        .padding(12)
                        .background(
                            LinearGradient(
                                colors: isRescueSignup ? [Color.red, Color.purple] : [Color.red, Color.orange],
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
            .onAppear {
                if let coord = geo.currentCoordinate {
                    rescueLocation = GeolocationService.formatCoordinate(coord)
                }
            }
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
        if isRescueSignup {
            if password.isEmpty {
                message = "Please enter a password for rescue registration"
                return
            }
            registerRescue()
            return
        }
        
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
    
    func registerRescue() {
        guard let url = URL(string: "\(AppConfig.apiBaseURL)/Rescue/Register") else {
            message = "Invalid API URL"
            return
        }
        
        let loc = rescueLocation.trimmingCharacters(in: .whitespaces).isEmpty ? "0.0,0.0" : rescueLocation.trimmingCharacters(in: .whitespaces)
        let body: [String: Any] = [
            "Password": password,
            "Location": loc
        ]
        
        guard let jsonData = try? JSONSerialization.data(withJSONObject: body) else { return }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = jsonData
        
        URLSession.shared.dataTask(with: request) { data, response, error in
            DispatchQueue.main.async {
                if let error = error {
                    message = "Network error: \(error.localizedDescription)"
                    return
                }
                
                guard let httpResponse = response as? HTTPURLResponse else {
                    message = "Invalid server response"
                    return
                }
                
                if (200...299).contains(httpResponse.statusCode) {
                    if let data = data,
                       let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                       let rid = json["rid"] as? Int {
                        message = "Rescue Unit Registered! Your Rescue ID is #\(rid). Save it to login."
                    } else {
                        message = "Rescue Unit Registered Successfully!"
                    }
                    
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
                        onSignupSuccess()
                    }
                } else {
                    message = "Failed to register rescue unit"
                }
            }
        }.resume()
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
