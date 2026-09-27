import SwiftUI

struct FamilyMemberRecord: Identifiable, Decodable {
    var id: Int { family_Id }
    let family_Id: Int
    let uid: String
    let guardian_Id: String
    let relationship: String
    let guardianName: String
    let guardianContact: String
}

struct FamilyMembersView: View {
    let uid: String
    @Environment(\.presentationMode) var presentationMode
    
    @State private var members: [FamilyMemberRecord] = []
    @State private var guardianEmail: String = ""
    @State private var selectedRelationship: String = "Parent"
    @State private var isLoading = false
    @State private var message: String = ""
    @State private var isErrorMessage = false
    @State private var isShowingGuardianAlerts = false
    
    let relationships = ["Parent", "Father", "Mother", "Spouse", "Sibling", "Brother", "Sister", "Child", "Friend", "Guardian"]
    let API = AppConfig.apiBaseURL
    
    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 20) {
                    // Guardian Mode Card
                    HStack(spacing: 14) {
                        Image(systemName: "bell.badge.fill")
                            .font(.system(size: 28))
                            .foregroundColor(.red)
                        
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Guardian Alert Monitor")
                                .font(.headline.weight(.bold))
                                .foregroundColor(.black)
                            Text("View emergency alerts from loved ones who added you")
                                .font(.caption)
                                .foregroundColor(.gray)
                        }
                        
                        Spacer()
                        
                        Button(action: { isShowingGuardianAlerts = true }) {
                            Text("Open")
                                .font(.system(size: 13, weight: .bold))
                                .foregroundColor(.white)
                                .padding(.horizontal, 14)
                                .padding(.vertical, 8)
                                .background(Color.red)
                                .cornerRadius(8)
                        }
                    }
                    .padding(14)
                    .background(Color.white)
                    .cornerRadius(14)
                    .shadow(color: Color.black.opacity(0.04), radius: 5, y: 2)
                    .padding(.horizontal, 16)
                    .padding(.top, 12)
                    
                    // Add Family Member Card
                    VStack(alignment: .leading, spacing: 14) {
                        HStack {
                            Image(systemName: "person.badge.plus.fill")
                                .foregroundColor(.blue)
                            Text("Add Loved One / Guardian")
                                .font(.headline.weight(.bold))
                        }
                        
                        Text("When you are in an accident, your emergency alert and live location will be shared immediately with this person.")
                            .font(.caption)
                            .foregroundColor(.gray)
                        
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Guardian User ID (Email)")
                                .font(.caption.weight(.semibold))
                                .foregroundColor(.gray)
                            
                            TextField("Enter guardian user email", text: $guardianEmail)
                                .autocapitalization(.none)
                                .disableAutocorrection(true)
                                .keyboardType(.emailAddress)
                                .padding(12)
                                .background(Color(.systemGray6))
                                .cornerRadius(10)
                        }
                        
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Relationship")
                                .font(.caption.weight(.semibold))
                                .foregroundColor(.gray)
                            
                            Picker("Relationship", selection: $selectedRelationship) {
                                ForEach(relationships, id: \.self) { r in
                                    Text(r).tag(r)
                                }
                            }
                            .pickerStyle(MenuPickerStyle())
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(10)
                            .background(Color(.systemGray6))
                            .cornerRadius(10)
                        }
                        
                        if !message.isEmpty {
                            Text(message)
                                .font(.caption)
                                .foregroundColor(isErrorMessage ? .red : .green)
                        }
                        
                        Button(action: addMember) {
                            HStack {
                                if isLoading {
                                    ProgressView()
                                        .progressViewStyle(CircularProgressViewStyle(tint: .white))
                                } else {
                                    Image(systemName: "plus.circle.fill")
                                    Text("Add Guardian")
                                        .font(.system(size: 15, weight: .bold))
                                }
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .background(Color.blue)
                            .foregroundColor(.white)
                            .cornerRadius(10)
                        }
                        .disabled(isLoading || guardianEmail.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                    .padding(16)
                    .background(Color.white)
                    .cornerRadius(14)
                    .shadow(color: Color.black.opacity(0.04), radius: 5, y: 2)
                    .padding(.horizontal, 16)
                    
                    // Current Guardians List
                    VStack(alignment: .leading, spacing: 12) {
                        Text("My Registered Guardians (\(members.count))")
                            .font(.headline.weight(.bold))
                            .padding(.horizontal, 16)
                        
                        if members.isEmpty {
                            VStack(spacing: 8) {
                                Image(systemName: "person.2.slash")
                                    .font(.system(size: 36))
                                    .foregroundColor(.gray)
                                Text("No guardians added yet")
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundColor(.gray)
                                Text("Add a family member above so they receive instant alerts and location tracking if an accident occurs.")
                                    .font(.caption)
                                    .foregroundColor(.gray.opacity(0.8))
                                    .multilineTextAlignment(.center)
                                    .padding(.horizontal, 30)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 32)
                            .background(Color.white)
                            .cornerRadius(14)
                            .padding(.horizontal, 16)
                        } else {
                            VStack(spacing: 10) {
                                ForEach(members) { member in
                                    HStack(spacing: 12) {
                                        Circle()
                                            .fill(Color.blue.opacity(0.12))
                                            .frame(width: 44, height: 44)
                                            .overlay(
                                                Text(member.guardianName.prefix(1).uppercased())
                                                    .font(.system(size: 18, weight: .bold))
                                                    .foregroundColor(.blue)
                                            )
                                        
                                        VStack(alignment: .leading, spacing: 2) {
                                            HStack {
                                                Text(member.guardianName)
                                                    .font(.system(size: 15, weight: .bold))
                                                Text("• \(member.relationship)")
                                                    .font(.caption.weight(.semibold))
                                                    .foregroundColor(.blue)
                                            }
                                            Text(member.guardian_Id)
                                                .font(.caption)
                                                .foregroundColor(.gray)
                                            if !member.guardianContact.isEmpty {
                                                Text(member.guardianContact)
                                                    .font(.caption2)
                                                    .foregroundColor(.gray)
                                            }
                                        }
                                        
                                        Spacer()
                                        
                                        Button(action: { removeMember(member) }) {
                                            Image(systemName: "trash")
                                                .foregroundColor(.red)
                                                .padding(8)
                                        }
                                    }
                                    .padding(12)
                                    .background(Color.white)
                                    .cornerRadius(12)
                                    .shadow(color: Color.black.opacity(0.03), radius: 3)
                                }
                            }
                            .padding(.horizontal, 16)
                        }
                    }
                }
                .padding(.bottom, 24)
            }
            .background(Color(red: 245/255, green: 246/255, blue: 250/255).edgesIgnoringSafeArea(.all))
            .navigationTitle("Family & Guardians")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        presentationMode.wrappedValue.dismiss()
                    }
                }
            }
            .sheet(isPresented: $isShowingGuardianAlerts) {
                AlertsView(mode: .guardian, identifier: uid, onLogout: {
                    isShowingGuardianAlerts = false
                }, onDismiss: {
                    isShowingGuardianAlerts = false
                })
            }
            .onAppear {
                fetchMembers()
            }
        }
    }
    
    // ================= API CALLS =================
    private func fetchMembers() {
        guard let url = URL(string: "\(API)/FamilyMembers?uid=\(uid.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? uid)") else { return }
        
        URLSession.shared.dataTask(with: url) { data, _, error in
            guard let data = data, error == nil else { return }
            do {
                let decoded = try JSONDecoder().decode([FamilyMemberRecord].self, from: data)
                DispatchQueue.main.async {
                    self.members = decoded
                }
            } catch {
                print("Decode error in family members: \(error)")
            }
        }.resume()
    }
    
    private func addMember() {
        guard !guardianEmail.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        isLoading = true
        message = ""
        
        guard let url = URL(string: "\(API)/FamilyMembers/Add") else {
            isLoading = false
            return
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let body: [String: Any] = [
            "Uid": uid.trimmingCharacters(in: .whitespaces),
            "GuardianId": guardianEmail.trimmingCharacters(in: .whitespaces),
            "Relationship": selectedRelationship
        ]
        
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)
        
        URLSession.shared.dataTask(with: request) { data, response, error in
            DispatchQueue.main.async {
                self.isLoading = false
                if let error = error {
                    self.message = "Error: \(error.localizedDescription)"
                    self.isErrorMessage = true
                    return
                }
                
                guard let httpResponse = response as? HTTPURLResponse else { return }
                
                if (200...299).contains(httpResponse.statusCode) {
                    self.message = "Guardian added successfully!"
                    self.isErrorMessage = false
                    self.guardianEmail = ""
                    self.fetchMembers()
                } else {
                    if let data = data,
                       let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                       let msg = json["message"] as? String {
                        self.message = msg
                    } else {
                        self.message = "Failed to add guardian. Please check the User ID."
                    }
                    self.isErrorMessage = true
                }
            }
        }.resume()
    }
    
    private func removeMember(_ member: FamilyMemberRecord) {
        guard let url = URL(string: "\(API)/FamilyMembers/Remove?uid=\(uid.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? uid)&guardianId=\(member.guardian_Id.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? member.guardian_Id)") else { return }
        
        var request = URLRequest(url: url)
        request.httpMethod = "DELETE"
        
        URLSession.shared.dataTask(with: request) { _, response, error in
            if error == nil {
                DispatchQueue.main.async {
                    withAnimation {
                        self.members.removeAll { $0.family_Id == member.family_Id }
                    }
                }
            }
        }.resume()
    }
}
