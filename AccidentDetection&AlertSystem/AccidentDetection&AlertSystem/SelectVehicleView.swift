import SwiftUI



struct VehicleScreen: View {
    let API = AppConfig.apiBaseURL
    var uid: String = ""
    var onLogout: () -> Void = {}
    
    @State private var plateNumber = ""
    @State private var make = ""
    @State private var selectedCarType: String? = nil
    @State private var vehicles: [Car] = []
    @State private var showDropdown = false
    
    let carTypes = ["SUV", "Hatchback", "Sedan"]
    
    // For navigation in SwiftUI
    @State private var navigateToDashboard = false
    @State private var selectedCarForDashboard: Car? = nil
    
    func categoryName(id: Int) -> String {
        switch id {
        case 1: return "SUV"
        case 2: return "Hatchback"
        case 3: return "Sedan"
        default: return "Unknown"
        }
    }
    
    func categoryId(name: String) -> Int {
        switch name {
        case "SUV": return 1
        case "Hatchback": return 2
        case "Sedan": return 3
        default: return 1
        }
    }
    
    func fetchUserVehicles() {
        guard !uid.isEmpty else {
            print("⚠️ UID missing")
            return
        }
        
        print("📡 Fetching vehicles for UID: \(uid)")
        
        guard let url = URL(string: "\(API)/SelectVehicle/UserVehicles?uid=\(uid)") else { return }
        
        URLSession.shared.dataTask(with: url) { data, response, error in
            if let error = error {
                print("❌ Fetch error: \(error)")
                return
            }
            guard let data = data else { return }
            do {
                let fetchedCars = try JSONDecoder().decode([Car].self, from: data)
                DispatchQueue.main.async {
                    self.vehicles = fetchedCars
                }
            } catch {
                print("❌ Fetch decode error: \(error)")
            }
        }.resume()
    }
    
    func addVehicle() {
        guard let carType = selectedCarType, !plateNumber.isEmpty, !make.isEmpty else {
            // Alert fill all fields
            return
        }
        
        print("➕ Adding vehicle...")
        guard let url = URL(string: "\(API)/SelectVehicle/AddVehicle") else { return }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let body: [String: Any] = [
            "Registration_No": plateNumber,
            "Make": make,
            "Uid": uid,
            "Category_Id": categoryId(name: carType)
        ]
        
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)
        
        URLSession.shared.dataTask(with: request) { data, response, error in
            if let error = error {
                print("❌ Add error: \(error)")
                return
            }
            if let httpResponse = response as? HTTPURLResponse, (200...299).contains(httpResponse.statusCode) {
                DispatchQueue.main.async {
                    fetchUserVehicles()
                    clearForm()
                }
            }
        }.resume()
    }
    
    func removeCar(id: Int) {
        print("🗑 Removing car: \(id)")
        guard let url = URL(string: "\(API)/SelectVehicle/RemoveVehicle?carId=\(id)") else { return }
        
        var request = URLRequest(url: url)
        request.httpMethod = "DELETE"
        
        URLSession.shared.dataTask(with: request) { data, response, error in
            if let error = error {
                print("❌ Delete error: \(error)")
                return
            }
            if let httpResponse = response as? HTTPURLResponse, (200...299).contains(httpResponse.statusCode) {
                DispatchQueue.main.async {
                    self.vehicles.removeAll { $0.carId == id }
                }
            }
        }.resume()
    }
    
    func clearForm() {
        plateNumber = ""
        make = ""
        selectedCarType = nil
    }

    @ViewBuilder
    private var monitoringDestination: some View {
        MonitoringScreen(
            email: uid,
            carId: selectedCarForDashboard?.carId ?? 0,
            uid: uid,
            make: selectedCarForDashboard?.make ?? "",
            plate: selectedCarForDashboard?.registrationNo ?? "",
            onLogout: onLogout
        )
    }
    
    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 16) {
                    ForEach(vehicles) { car in
                        CarCardView(car: car, onSelect: {
                            self.selectedCarForDashboard = car
                            self.navigateToDashboard = true
                        }, onRemove: {
                            if let id = car.carId { removeCar(id: id) }
                        }, categoryName: categoryName(id: car.categoryId))
                    }
                    
                    VStack(alignment: .leading) {
                        Text("Add New Vehicle").font(.headline.weight(.bold))
                        
                        Text("Car Type").padding(.top, 10)
                        Menu {
                            ForEach(carTypes, id: \.self) { type in
                                Button(type) { selectedCarType = type }
                            }
                        } label: {
                            HStack {
                                Text(selectedCarType ?? "Select car type").foregroundColor(.black)
                                Spacer()
                                Image(systemName: "chevron.down").foregroundColor(.black)
                            }
                            .padding(12)
                            .background(Color(white: 0.933))
                            .cornerRadius(8)
                        }
                        
                        Text("Car Model").padding(.top, 10)
                        TextField("Honda Civic", text: $make)
                            .padding(12)
                            .background(Color(white: 0.933))
                            .cornerRadius(8)
                        
                        Text("Plate Number").padding(.top, 10)
                        TextField("ABC-1234", text: $plateNumber)
                            .padding(12)
                            .background(Color(white: 0.933))
                            .cornerRadius(8)
                        
                        HStack {
                            Button(action: addVehicle) {
                                Text("+ Add Car")
                                    .foregroundColor(.white)
                                    .frame(maxWidth: .infinity)
                                    .padding(12)
                                    .background(Color(red: 255/255, green: 59/255, blue: 0))
                                    .cornerRadius(10)
                            }
                            
                            Button(action: clearForm) {
                                Text("Cancel")
                                    .foregroundColor(.black)
                                    .padding(12)
                                    .background(Color(white: 0.933))
                                    .cornerRadius(10)
                            }
                        }.padding(.top, 10)
                    }
                    .padding(15)
                    .background(Color.white)
                    .cornerRadius(16)
                    .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color(red: 255/255, green: 59/255, blue: 0), lineWidth: 1))
                    .padding(.top, 10)
                }
                .padding(15)
                .background(
                    NavigationLink(
                        destination: monitoringDestination,
                        isActive: $navigateToDashboard,
                        label: { EmptyView() }
                    )
                )
                .navigationTitle("Select Vehicle")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Button(action: onLogout) {
                            Image(systemName: "rectangle.portrait.and.arrow.right")
                                .foregroundColor(.red)
                        }
                    }
                }
            }
            .navigationViewStyle(StackNavigationViewStyle())
            .background(Color(red: 233/255, green: 227/255, blue: 221/255).edgesIgnoringSafeArea(.all))
            .onAppear {
                fetchUserVehicles()
            }
        }
    }
    
    struct CarCardView: View {
        var car: Car
        var onSelect: () -> Void
        var onRemove: () -> Void
        var categoryName: String
        
        var body: some View {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Image(systemName: "car.fill")
                        .padding(10)
                        .background(Color(red: 255/255, green: 77/255, blue: 0))
                        .foregroundColor(.white)
                        .clipShape(Circle())
                    
                    VStack(alignment: .leading) {
                        Text(car.make ?? "").bold()
                        Text(categoryName).foregroundColor(.gray)
                    }
                    Spacer()
                    Button(action: onRemove) {
                        Image(systemName: "trash").foregroundColor(.red).font(.system(size: 22))
                    }
                }
                
                Text("Plate Number").foregroundColor(.gray).padding(.top, 10)
                Text(car.registrationNo).bold()
                
                Button(action: onSelect) {
                    HStack {
                        Image(systemName: "checkmark").foregroundColor(.white)
                        Text("Select This Car").foregroundColor(.white)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(12)
                    .background(Color(red: 255/255, green: 59/255, blue: 0))
                    .cornerRadius(10)
                }.padding(.top, 10)
            }
            .padding(15)
            .background(Color(red: 240/255, green: 239/255, blue: 238/255))
            .cornerRadius(14)
        }
    }
}
