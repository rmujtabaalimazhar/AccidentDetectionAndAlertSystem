import SwiftUI

struct NodeData: Codable {
    let Node_Id: Int
    let Node_Position: String?
    let Force: Double?

    enum CodingKeys: String, CodingKey {
        case Node_Id = "node_Id"
        case Node_Position = "node_Position"
        case Force = "force"
    }
}

struct NodesResponse: Codable {
    let Nodes: [NodeData]
    let Weight: Double?

    enum CodingKeys: String, CodingKey {
        case Nodes = "nodes"
        case Weight = "weight"
    }
}

struct NodeModel: Identifiable {
    let id: Int
    let name: String
    var force: String
}

struct ConfigureNodes: View {
    @Environment(\.presentationMode) var presentationMode
    let categoryId: Int
    let carName: String
    let carType: String
    var onLogout: () -> Void = {}
    
    @State private var carWeight: String = ""
    @State private var nodes: [NodeModel] = []
    
    func fetchData() {
        guard let url = URL(string: "\(AppConfig.apiBaseURL)/ConfigureNodes/GetNodes?categoryId=\(categoryId)") else { return }
        
        URLSession.shared.dataTask(with: url) { data, response, error in
                DispatchQueue.main.async {
                    do {
                        guard let data = data else {
                            print("No data received: \(error?.localizedDescription ?? "Unknown error")")
                            return
                        }
                        
                        if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode >= 400 {
                            let serverMsg = String(data: data, encoding: .utf8) ?? ""
                            print("Server returned error \(httpResponse.statusCode): \(serverMsg)")
                            return
                        }
                        
                        let responseData = try JSONDecoder().decode(NodesResponse.self, from: data)
                        self.nodes = responseData.Nodes.map { 
                            NodeModel(id: $0.Node_Id, name: $0.Node_Position ?? "Unknown", force: String($0.Force ?? 0.0)) 
                        }
                        self.carWeight = String(responseData.Weight ?? 0.0)
                    } catch {
                        print("Error decoding: \(error)")
                        if let data = data, let str = String(data: data, encoding: .utf8) {
                            print("Raw server response: \(str)")
                        }
                    }
                }
        }.resume()
    }
    
    struct SaveNodePayload: Encodable {
        let Node_Id: Int
        let Category_Id: Int
        let Node_Position: String
        let Force: Double

        enum CodingKeys: String, CodingKey {
            case Node_Id = "node_Id"
            case Category_Id = "category_Id"
            case Node_Position = "node_Position"
            case Force = "force"
        }
    }
    
    func saveConfiguration() {
        let payload = nodes.map { 
            SaveNodePayload(Node_Id: $0.id, Category_Id: categoryId, Node_Position: $0.name, Force: Double($0.force) ?? 0.0)
        }
        
        let weightVal = Double(carWeight) ?? 0.0
        guard let url = URL(string: "\(AppConfig.apiBaseURL)/ConfigureNodes/SaveConfiguration?weight=\(weightVal)") else { return }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try? JSONEncoder().encode(payload)
        
        URLSession.shared.dataTask(with: request) { data, response, error in
            DispatchQueue.main.async {
                if let error = error {
                    print("Network error during save: \(error.localizedDescription)")
                    return
                }
                
                if let httpResponse = response as? HTTPURLResponse {
                    if httpResponse.statusCode >= 200 && httpResponse.statusCode < 300 {
                        print("Configuration saved successfully!")
                        fetchData()
                    } else {
                        let serverMsg = String(data: data ?? Data(), encoding: .utf8) ?? ""
                        print("Failed to save. Status: \(httpResponse.statusCode). Server response: \(serverMsg)")
                    }
                }
            }
        }.resume()
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // HEADER
            HStack {
                HStack {
                    Text("A")
                        .bold()
                        .foregroundColor(.white)
                        .frame(width: 40, height: 40)
                        .background(Color(red: 255/255, green: 59/255, blue: 0))
                        .cornerRadius(10)
                        .padding(.trailing, 10)
                    
                    VStack(alignment: .leading) {
                        Text("Admin Dashboard").bold()
                        Text("Configure Sensors").foregroundColor(.gray).font(.system(size: 12))
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
            
            // CAR HEADER
            HStack {
                Button(action: { presentationMode.wrappedValue.dismiss() }) {
                    Image(systemName: "arrow.left").font(.system(size: 22)).foregroundColor(.black)
                }
                
                VStack(alignment: .leading) {
                    Text(carName).bold()
                    Text(carType).foregroundColor(.gray).font(.system(size: 12))
                }.padding(.leading, 10)
                
                Spacer()
                
                Button(action: saveConfiguration) {
                    Text("Save")
                        .foregroundColor(.white)
                        .padding(10)
                        .background(Color(red: 255/255, green: 59/255, blue: 0))
                        .cornerRadius(8)
                }
            }
            .padding(15)
            .background(Color.white)
            
            ScrollView {
                VStack(spacing: 10) {
                    // IMAGE
                    VStack(alignment: .leading) {
                        Text("Sensor Positions").bold().padding(.bottom, 10)
                        Image(carType.lowercased())
                            .resizable()
                            .scaledToFit()
                            .frame(height: 300)
                        Text("Tap a sensor below to configure").foregroundColor(.gray).frame(maxWidth: .infinity, alignment: .center).padding(.top, 10)
                    }
                    .padding(15).background(Color.white).cornerRadius(16).padding(10)
                    
                    // VEHICLE WEIGHT
                    VStack(alignment: .leading) {
                        Text("Vehicle Weight").bold().padding(.bottom, 10)
                        HStack {
                            TextField("", text: $carWeight)
                                .keyboardType(.decimalPad)
                                .multilineTextAlignment(.center)
                                .frame(width: 120)
                                .padding(.vertical, 10).padding(.horizontal, 12).background(Color(white: 0.933)).cornerRadius(8)
                            Text("kg").foregroundColor(Color(white: 0.333)).padding(.leading, 12)
                        }
                    }
                    .padding(15).background(Color.white).cornerRadius(16).padding(10)
                    
                    // NODE LIST
                    VStack(alignment: .leading) {
                        Text("Configure Sensors").bold().padding(.bottom, 10)
                        
                        ForEach($nodes) { $node in
                            HStack {
                                Text(String($node.wrappedValue.id))
                                    .font(.system(size: 10))
                                    .foregroundColor(.white)
                                    .frame(width: 24, height: 24)
                                    .background(Color.blue)
                                    .clipShape(Circle())
                                    .padding(.trailing, 8)
                                
                                Text($node.wrappedValue.name).font(.body.weight(.semibold))
                                
                                Spacer()
                                
                                TextField("", text: $node.force)
                                    .keyboardType(.decimalPad)
                                    .multilineTextAlignment(.center)
                                    .frame(width: 80)
                                    .padding(.vertical, 10).padding(.horizontal, 12).background(Color(white: 0.933)).cornerRadius(8)
                                    
                                Text("N").foregroundColor(Color(white: 0.333)).padding(.leading, 4)
                            }
                            .padding(12).background(Color.white).cornerRadius(10)
                            .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color(white: 0.867), lineWidth: 1))
                            .padding(.bottom, 10)
                        }
                    }
                    .padding(15).background(Color.white).cornerRadius(16).padding(10)
                }
            }
        }
        .background(Color(red: 243/255, green: 244/255, blue: 246/255).edgesIgnoringSafeArea(.bottom))
        .navigationBarHidden(true)
        .onAppear {
            fetchData()
        }
    }
}
