import SwiftUI

struct AdminDashboard: View {
    var onLogout: () -> Void = {}
    
    @State private var selectedVehicle: String = "SUV"
    
    let vehicles = [
        ("SUV", "Sport Utility Vehicle", "car.fill", Color(red: 34/255, green: 197/255, blue: 94/255)),
        ("Sedan", "Four-door Passenger Car", "car", Color(red: 59/255, green: 130/255, blue: 246/255)),
        ("Hatchback", "Compact Car with Rear Door", "car", Color(red: 249/255, green: 115/255, blue: 22/255))
    ]
    
    func getCategoryDetails(for type: String) -> (id: Int, model: String) {
        switch type {
        case "Sedan": return (1, "Toyota Corolla")
        case "SUV": return (2, "Honda CR-V")
        case "Hatchback": return (3, "Suzuki Swift")
        default: return (1, "Unknown")
        }
    }
    
    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                // Header
                HStack {
                    HStack {
                        Text("A")
                            .font(.body.weight(.bold))
                            .foregroundColor(.white)
                            .frame(width: 40, height: 40)
                            .background(Color(red: 255/255, green: 59/255, blue: 0))
                            .cornerRadius(10)
                            .padding(.trailing, 10)
                        
                        VStack(alignment: .leading) {
                            Text("Admin Dashboard")
                                .font(.body.weight(.bold))
                            Text("Configure Sensors")
                                .foregroundColor(.gray)
                                .font(.system(size: 12))
                        }
                    }
                    Spacer()
                    Button(action: onLogout) {
                        Image(systemName: "rectangle.portrait.and.arrow.right")
                            .font(.system(size: 22))
                            .foregroundColor(.red)
                    }
                }
                .padding(15)
                .background(Color.white)
                
                ScrollView {
                    VStack(spacing: 15) {
                        Text("Select Vehicle")
                            .font(.system(size: 20, weight: .bold))
                            .multilineTextAlignment(.center)
                            .padding(.top, 15)
                        
                        Text("Choose a vehicle type and model to configure sensors")
                            .foregroundColor(.gray)
                            .multilineTextAlignment(.center)
                            .padding(.bottom, 15)
                        
                        ForEach(vehicles, id: \.0) { v in
                            let isSelected = selectedVehicle == v.0
                            
                            Button(action: {
                                selectedVehicle = v.0
                            }) {
                                HStack {
                                    Image(systemName: v.2)
                                        .foregroundColor(v.3)
                                        .font(.system(size: 22))
                                        .frame(width: 50, height: 50)
                                        .background(v.3.opacity(0.2))
                                        .cornerRadius(12)
                                        .padding(.trailing, 10)
                                    
                                    VStack(alignment: .leading) {
                                        Text(v.0).font(.body.weight(.bold)).foregroundColor(.black)
                                        Text(v.1).foregroundColor(.gray).font(.system(size: 12))
                                    }
                                    
                                    Spacer()
                                    
                                    if isSelected {
                                        Image(systemName: "checkmark").foregroundColor(.green).font(.system(size: 20))
                                    }
                                }
                                .padding(15)
                                .background(Color.white)
                                .cornerRadius(16)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 16)
                                        .stroke(isSelected ? Color(red: 239/255, green: 68/255, blue: 68/255) : Color(white: 0.867), lineWidth: isSelected ? 2 : 1)
                                )
                            }
                        }
                        
                        VStack(alignment: .leading) {
                            Text("Selected Model")
                                .font(.body.weight(.bold))
                            
                            Text(getCategoryDetails(for: selectedVehicle).model)
                                .foregroundColor(.gray)
                                .padding(.bottom, 10)
                            
                            let details = getCategoryDetails(for: selectedVehicle)
                            
                            NavigationLink(destination: ConfigureNodes(categoryId: details.id, carName: details.model, carType: selectedVehicle, onLogout: onLogout)) {
                                Text("Configure Sensors")
                                    .font(.body.weight(.bold))
                                    .foregroundColor(.white)
                                    .frame(maxWidth: .infinity)
                                    .padding(14)
                                    .background(Color(red: 255/255, green: 59/255, blue: 0))
                                    .cornerRadius(10)
                            }
                        }
                        .padding(15)
                        .background(Color.white)
                        .cornerRadius(16)
                        .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color(red: 255/255, green: 59/255, blue: 0), lineWidth: 2))
                        .padding(.top, 15)
                    }
                    .padding(15)
                }
            }
            .background(Color(red: 243/255, green: 244/255, blue: 246/255).edgesIgnoringSafeArea(.bottom))
            .navigationBarHidden(true)
        }
    }
}
