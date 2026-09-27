/*
import SwiftUI

// MARK: - Node Coordinates Database & Fallback
struct NodeCoordinate {
    let x: Double // Percentage from left (0 - 100)
    let y: Double // Percentage from top (0 - 100)
}

struct CarNodeCoordinates {
    // Exact percentage coordinates calibrated for each wireframe image:
    
    // Category 1: Sedan (30 nodes)
    static let sedan: [Int: NodeCoordinate] = [
        1:  NodeCoordinate(x: 51.36, y: 3.13),
        2:  NodeCoordinate(x: 25.37, y: 9.82),
        3:  NodeCoordinate(x: 77.43, y: 9.67),
        4:  NodeCoordinate(x: 51.37, y: 13.73),
        5:  NodeCoordinate(x: 51.38, y: 24.14),
        6:  NodeCoordinate(x: 27.06, y: 26.58),
        7:  NodeCoordinate(x: 75.77, y: 26.58),
        8:  NodeCoordinate(x: 26.30, y: 34.51),
        9:  NodeCoordinate(x: 77.29, y: 34.66),
        10: NodeCoordinate(x: 32.95, y: 40.52),
        11: NodeCoordinate(x: 70.49, y: 40.37),
        12: NodeCoordinate(x: 51.36, y: 41.72),
        13: NodeCoordinate(x: 51.33, y: 57.49),
        14: NodeCoordinate(x: 34.25, y: 54.62),
        15: NodeCoordinate(x: 23.13, y: 53.32),
        16: NodeCoordinate(x: 70.50, y: 54.62),
        17: NodeCoordinate(x: 79.79, y: 53.15),
        18: NodeCoordinate(x: 33.66, y: 65.49),
        19: NodeCoordinate(x: 23.72, y: 71.05),
        20: NodeCoordinate(x: 70.95, y: 65.48),
        21: NodeCoordinate(x: 79.86, y: 71.35),
        22: NodeCoordinate(x: 51.38, y: 71.64),
        23: NodeCoordinate(x: 51.38, y: 81.07),
        24: NodeCoordinate(x: 31.68, y: 77.21),
        25: NodeCoordinate(x: 73.57, y: 77.21),
        26: NodeCoordinate(x: 27.62, y: 84.93),
        27: NodeCoordinate(x: 76.35, y: 84.95),
        28: NodeCoordinate(x: 31.64, y: 92.24),
        29: NodeCoordinate(x: 72.42, y: 92.24),
        30: NodeCoordinate(x: 51.33, y: 95.63)
    ]
    
    // Category 2: SUV (25 nodes)
    static let suv: [Int: NodeCoordinate] = [
        1:  NodeCoordinate(x: 48.55, y: 4.25),
        2:  NodeCoordinate(x: 75.07, y: 6.36),
        3:  NodeCoordinate(x: 21.29, y: 7.99),
        4:  NodeCoordinate(x: 48.07, y: 22.98),
        5:  NodeCoordinate(x: 19.10, y: 27.01),
        6:  NodeCoordinate(x: 79.22, y: 27.75),
        7:  NodeCoordinate(x: 24.95, y: 34.04),
        8:  NodeCoordinate(x: 48.30, y: 33.15),
        9:  NodeCoordinate(x: 72.38, y: 34.05),
        10: NodeCoordinate(x: 16.86, y: 48.41),
        11: NodeCoordinate(x: 24.24, y: 48.24),
        12: NodeCoordinate(x: 73.30, y: 48.10),
        13: NodeCoordinate(x: 80.52, y: 47.81),
        14: NodeCoordinate(x: 48.25, y: 55.15), // Roof Center
        15: NodeCoordinate(x: 23.98, y: 62.47),
        16: NodeCoordinate(x: 73.09, y: 63.06),
        17: NodeCoordinate(x: 16.15, y: 67.87),
        18: NodeCoordinate(x: 81.20, y: 66.82),
        19: NodeCoordinate(x: 21.99, y: 78.20),
        20: NodeCoordinate(x: 48.54, y: 77.00), // Rear Cabin Center
        21: NodeCoordinate(x: 76.08, y: 78.19),
        22: NodeCoordinate(x: 48.30, y: 84.62), // Rear Center Upper
        23: NodeCoordinate(x: 20.09, y: 92.85),
        24: NodeCoordinate(x: 48.51, y: 94.50), // Spare Wheel Area
        25: NodeCoordinate(x: 78.03, y: 93.01)
    ]
    
    // Category 3: Hatchback (23 nodes)
    static let hatchback: [Int: NodeCoordinate] = [
        1:  NodeCoordinate(x: 44.75, y: 5.04),
        2:  NodeCoordinate(x: 27.08, y: 9.08),
        3:  NodeCoordinate(x: 64.52, y: 9.09),
        4:  NodeCoordinate(x: 44.57, y: 14.78),
        5:  NodeCoordinate(x: 44.57, y: 23.64),
        6:  NodeCoordinate(x: 25.52, y: 27.23),
        7:  NodeCoordinate(x: 65.93, y: 27.10),
        8:  NodeCoordinate(x: 30.24, y: 36.53),
        9:  NodeCoordinate(x: 45.26, y: 36.53), // Center Cabin
        10: NodeCoordinate(x: 60.51, y: 35.93),
        11: NodeCoordinate(x: 26.20, y: 50.93),
        12: NodeCoordinate(x: 65.57, y: 49.13),
        13: NodeCoordinate(x: 31.10, y: 55.60),
        14: NodeCoordinate(x: 45.47, y: 53.18), // Cabin Floor Center (Roof Center)
        15: NodeCoordinate(x: 61.89, y: 53.93),
        16: NodeCoordinate(x: 24.26, y: 70.43),
        17: NodeCoordinate(x: 65.76, y: 70.75),
        18: NodeCoordinate(x: 31.40, y: 76.89),
        19: NodeCoordinate(x: 44.91, y: 75.85), // Rear Seat Center
        20: NodeCoordinate(x: 58.74, y: 75.85),
        21: NodeCoordinate(x: 26.91, y: 87.84),
        22: NodeCoordinate(x: 64.37, y: 87.41),
        23: NodeCoordinate(x: 45.60, y: 92.39)  // Rear Center
    ]
    
    static func getCoordinate(for categoryId: Int, carType: String, nodeId: Int) -> NodeCoordinate {
        let typeLower = carType.lowercased()
        if categoryId == 1 || typeLower.contains("sedan") {
            return sedan[nodeId] ?? NodeCoordinate(x: 51.36, y: 50)
        } else if categoryId == 2 || typeLower.contains("suv") {
            return suv[nodeId] ?? NodeCoordinate(x: 48.25, y: 50)
        } else {
            return hatchback[nodeId] ?? NodeCoordinate(x: 45.47, y: 50)
        }
    }
    
    static func defaultNodes(for categoryId: Int, carType: String) -> [NodeModel] {
        let typeLower = carType.lowercased()
        let isSedan = categoryId == 1 || typeLower.contains("sedan")
        let isSuv = categoryId == 2 || typeLower.contains("suv")
        
        if isSedan {
            let names = [
                1: "Front-Left", 2: "Front-Center", 3: "Front-Right", 4: "Engine",
                5: "Mid-Left", 6: "Mid-Center", 7: "Mid-Right", 8: "Left-A",
                9: "Right-A", 10: "Left-B", 11: "Right-B", 12: "Center-A",
                13: "Core", 14: "Left-C", 15: "Right-C", 16: "Left-D",
                17: "Right-D", 18: "Left-E", 19: "Right-E", 20: "Center-B",
                21: "Left-F", 22: "Center-C", 23: "Rear-Core", 24: "Rear-Left",
                25: "Rear-Right", 26: "Back-A", 27: "Back-B", 28: "Back-C",
                29: "Back-D", 30: "Back-End"
            ]
            return (1...30).map { id in
                let coord = sedan[id] ?? NodeCoordinate(x: 50, y: 50)
                return NodeModel(id: id, name: names[id] ?? "Node \(id)", force: "2", x: coord.x, y: coord.y)
            }
        } else if isSuv {
            let names = [
                1: "Front Center", 2: "Front Right Corner", 3: "Front Left Corner", 4: "Dashboard Center",
                5: "Front Left Door", 6: "Front Right Door", 7: "Left Side Upper", 8: "Engine Center",
                9: "Right Side Upper", 10: "Left Mirror Area", 11: "Left Door Mid", 12: "Right Door Mid",
                13: "Right Mirror Area", 14: "Roof Center", 15: "Left Rear Door", 16: "Right Rear Door",
                17: "Left Back Pillar", 18: "Right Back Pillar", 19: "Rear Left Side", 20: "Rear Cabin Center",
                21: "Rear Right Side", 22: "Rear Center Upper", 23: "Rear Left Corner", 24: "Spare Wheel Area",
                25: "Rear Right Corner"
            ]
            return (1...25).map { id in
                let coord = suv[id] ?? NodeCoordinate(x: 50, y: 50)
                return NodeModel(id: id, name: names[id] ?? "Node \(id)", force: "10", x: coord.x, y: coord.y)
            }
        } else { // Hatchback
            let names = [
                1: "Front Center", 2: "Front Left Corner", 3: "Front Right Corner", 4: "Engine Top",
                5: "Dashboard Center", 6: "Left Pillar Front", 7: "Right Pillar Front", 8: "Left Door Upper",
                9: "Center Cabin", 10: "Right Door Upper", 11: "Left Door Middle", 12: "Right Door Middle",
                13: "Left Door Lower", 14: "Cabin Floor Center", 15: "Right Door Lower", 16: "Left Rear Door",
                17: "Right Rear Door", 18: "Rear Seat Left", 19: "Rear Seat Center", 20: "Rear Seat Right",
                21: "Rear Left Corner", 22: "Rear Right Corner", 23: "Rear Center"
            ]
            return (1...23).map { id in
                let coord = hatchback[id] ?? NodeCoordinate(x: 50, y: 50)
                return NodeModel(id: id, name: names[id] ?? "Node \(id)", force: "8", x: coord.x, y: coord.y)
            }
        }
    }
}

// MARK: - Network Models
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
    var name: String
    var force: String
    var x: Double
    var y: Double
}

// MARK: - ConfigureNodes Main View
struct ConfigureNodes: View {
    @Environment(\.presentationMode) var presentationMode
    let categoryId: Int
    let carName: String
    let carType: String
    var onLogout: () -> Void = {}
    
    @State private var carWeight: String = "1.50"
    @State private var nodes: [NodeModel] = []
    @State private var selectedNodeId: Int? = nil
    @State private var isSaving: Bool = false
    @State private var saveMessage: String? = nil
    @State private var showSaveAlert: Bool = false
    @State private var syncStatus: String = "Ready"
    @State private var scale: CGFloat = 1
    
    private var isSedan: Bool {
        categoryId == 1 || carType.lowercased().contains("sedan")
    }
    private var isSuv: Bool {
        categoryId == 2 || carType.lowercased().contains("suv")
    }
    private var isHatchback: Bool {
        categoryId == 3 || carType.lowercased().contains("hatchback")
    }
    
    private var carImageName: String {
        if isSedan { return "sedan" }
        if isSuv { return "suv" }
        return "hatchback"
    }
    
    // Exact Aspect Ratio for each Car Wireframe
    private var carAspectRatio: CGFloat {
        if isSedan {
            return 948.0 / 1659.0
        } else if isSuv {
            return 624.0 / 1024.0
        } else {
            return 878.0 / 1024.0
        }
    }
    
    // MARK: - API Calls
    func fetchData() {
        syncStatus = "Loading from server..."
        guard let url = URL(string: "\(AppConfig.apiBaseURL)/ConfigureNodes/GetNodes?categoryId=\(categoryId)") else {
            syncStatus = "Invalid API URL"
            return
        }
        
        var request = URLRequest(url: url)
        request.timeoutInterval = 8
        
        URLSession.shared.dataTask(with: request) { data, response, error in
            DispatchQueue.main.async {
                if let error = error {
                    self.syncStatus = "Using Local Defaults (API Offline)"
                    print("Fetch failed: \(error.localizedDescription)")
                    return
                }
                
                guard let data = data else {
                    self.syncStatus = "No data from server"
                    return
                }
                
                if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode >= 400 {
                    let serverMsg = String(data: data, encoding: .utf8) ?? ""
                    self.syncStatus = "Server error \(httpResponse.statusCode)"
                    print("Server returned error \(httpResponse.statusCode): \(serverMsg)")
                    return
                }
                
                do {
                    let responseData = try JSONDecoder().decode(NodesResponse.self, from: data)
                    
                    // Always start with canonical model-specific nodes
                    var currentNodes = CarNodeCoordinates.defaultNodes(for: self.categoryId, carType: self.carType)
                    
                    // If database has saved values, update the force values
                    if !responseData.Nodes.isEmpty {
                        for i in 0..<currentNodes.count {
                            if let serverNode = responseData.Nodes.first(where: { $0.Node_Id == currentNodes[i].id }),
                               let serverForce = serverNode.Force {
                                currentNodes[i].force = String(format: "%.0f", serverForce)
                            }
                        }
                        self.syncStatus = "Synced with Database"
                    }
                    self.nodes = currentNodes
                    
                    if let w = responseData.Weight {
                        self.carWeight = String(format: "%.2f", w)
                    }
                } catch {
                    self.syncStatus = "Data parsed with fallback"
                    print("Error decoding: \(error)")
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
        isSaving = true
        let payload = nodes.map {
            SaveNodePayload(
                Node_Id: $0.id,
                Category_Id: categoryId,
                Node_Position: $0.name,
                Force: Double($0.force) ?? 0.0
            )
        }
        
        let weightVal = Double(carWeight) ?? 0.0
        guard let url = URL(string: "\(AppConfig.apiBaseURL)/ConfigureNodes/SaveConfiguration?weight=\(weightVal)") else {
            isSaving = false
            return
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 10
        request.httpBody = try? JSONEncoder().encode(payload)
        
        URLSession.shared.dataTask(with: request) { data, response, error in
            DispatchQueue.main.async {
                isSaving = false
                if let error = error {
                    self.saveMessage = "Network error: \(error.localizedDescription)"
                    self.showSaveAlert = true
                    return
                }
                
                if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode >= 200 && httpResponse.statusCode < 300 {
                    self.saveMessage = "Configuration saved successfully to Database!"
                    self.showSaveAlert = true
                    fetchData()
                } else {
                    let serverMsg = String(data: data ?? Data(), encoding: .utf8) ?? ""
                    self.saveMessage = "Failed to save: \(serverMsg)"
                    self.showSaveAlert = true
                }
            }
        }.resume()
    }
    
    // MARK: - Main Body
    var body: some View {
        ScrollViewReader { scrollProxy in
            VStack(spacing: 0) {
                // 1. TOP BAR
                headerView
                
                // 2. SUB-HEADER (Back, Car Name, Save)
                carSubHeader
                
                // 3. FIXED & PINNED CAR DISPLAY (Stays on screen, does NOT scroll away!)
                fixedCarSection(scrollProxy: scrollProxy)
                    .zIndex(10) // Keeps car image fixed on top
                
                // 4. SCROLLABLE SENSOR TEXTBOXES SECTION (Scrolls underneath the car)
                ScrollView(.vertical, showsIndicators: true) {
                    VStack(spacing: 12) {
                        // Vehicle Weight Card
                        weightCard
                            .padding(.top, 6)
                        
                        // Section Divider / Header
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Sensor Thresholds")
                                    .font(.system(size: 14, weight: .bold))
                                    .foregroundColor(.black)
                                Text("Tap node on car above to jump directly to its textbox")
                                    .font(.system(size: 11))
                                    .foregroundColor(.gray)
                            }
                            Spacer()
                            Text("\(nodes.count) Sensors")
                                .font(.system(size: 11, weight: .bold))
                                .padding(.horizontal, 8)
                                .padding(.vertical, 3)
                                .background(Color.blue.opacity(0.12))
                                .foregroundColor(.blue)
                                .cornerRadius(6)
                        }
                        .padding(.horizontal, 4)
                        .padding(.top, 2)
                        
                        // The Node Textbox Cards
                        sensorCardsList
                    }
                    .padding(.horizontal, 12)
                    .padding(.bottom, 40)
                }
            }
        }
        .background(Color(red: 243/255, green: 244/255, blue: 246/255).edgesIgnoringSafeArea(.bottom))
        .navigationBarHidden(true)
        .alert(isPresented: $showSaveAlert) {
            Alert(
                title: Text("Node Configuration"),
                message: Text(saveMessage ?? ""),
                dismissButton: .default(Text("OK"))
            )
        }
        .onAppear {
            if self.nodes.isEmpty {
                self.nodes = CarNodeCoordinates.defaultNodes(for: categoryId, carType: carType)
            }
            fetchData()
        }
    }
    
    // MARK: - Header
    private var headerView: some View {
        HStack {
            HStack(spacing: 12) {
                Text("A")
                    .bold()
                    .foregroundColor(.white)
                    .frame(width: 38, height: 38)
                    .background(Color(red: 255/255, green: 59/255, blue: 0))
                    .cornerRadius(10)
                
                VStack(alignment: .leading, spacing: 2) {
                    Text("Admin Dashboard")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundColor(.black)
                    Text("Interactive Sensor Mapping")
                        .foregroundColor(.gray)
                        .font(.system(size: 11))
                }
            }
            Spacer()
            Button(action: onLogout) {
                Image(systemName: "rectangle.portrait.and.arrow.right")
                    .font(.system(size: 19, weight: .semibold))
                    .foregroundColor(.red)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(Color.white)
        .shadow(color: Color.black.opacity(0.04), radius: 2, y: 1)
    }
    
    // MARK: - Sub Header
    private var carSubHeader: some View {
        HStack {
            Button(action: { presentationMode.wrappedValue.dismiss() }) {
                HStack(spacing: 5) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 15, weight: .bold))
                    Text("Back")
                        .font(.system(size: 14, weight: .medium))
                }
                .foregroundColor(.black)
            }
            
            Spacer()
            
            VStack(alignment: .center, spacing: 1) {
                Text(carName)
                    .font(.system(size: 15, weight: .bold))
                    .foregroundColor(.black)
                Text(carType.uppercased())
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(Color(red: 255/255, green: 59/255, blue: 0))
            }
            
            Spacer()
            
            Button(action: saveConfiguration) {
                HStack(spacing: 4) {
                    if isSaving {
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle(tint: .white))
                            .scaleEffect(0.75)
                    } else {
                        Image(systemName: "checkmark")
                            .font(.system(size: 12, weight: .bold))
                    }
                    Text("Save")
                        .font(.system(size: 13, weight: .bold))
                }
                .foregroundColor(.white)
                .padding(.horizontal, 14)
                .padding(.vertical, 7)
                .background(Color(red: 255/255, green: 59/255, blue: 0))
                .cornerRadius(8)
            }
            .disabled(isSaving)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(Color.white)
    }
    
    // MARK: - FIXED CAR DISPLAY SECTION
    private func fixedCarSection(scrollProxy: ScrollViewProxy) -> some View {
        let imageHeight: CGFloat = 410 // Calibrated height so Hatchback width fits on all screens
        let imageWidth = imageHeight * carAspectRatio
        
        return VStack(spacing: 2) {
            // Selected Node & Status Indicator Banner
            HStack {
                Circle()
                    .fill(syncStatus.contains("Synced") ? Color.green : Color.orange)
                    .frame(width: 7, height: 7)
                Text(syncStatus)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.gray)
                
                Spacer()
                
                if let selected = selectedNodeId {
                    Text("Selected: Node \(selected)")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(Color(red: 255/255, green: 59/255, blue: 0))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 2)
                        .background(Color(red: 255/255, green: 59/255, blue: 0).opacity(0.12))
                        .cornerRadius(6)
                } else {
                    Text("Tap any node to jump to textbox")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.gray)
                }
            }
            .padding(.horizontal, 14)
            .padding(.top, 4)
            
            // Centered Car Visualizer
            ZStack {
                // The Car Image (scaled proportionally)
        /*        Image(carImageName)
                    .resizable()
                    .scaledToFit()
                    .frame(width: imageWidth, height: imageHeight)
            */
               
               
                Image(carImageName)
                    .resizable()
                    .scaledToFit()
                    .frame(width: imageWidth, height: imageHeight)
                    .scaleEffect(scale)
                    .gesture(
                        MagnificationGesture()
                            .onChanged { value in
                                scale = max(1, min(value, 4))
                            }
                    )
                
                // Clickable overlay buttons positioned with exact coordinates
                ForEach(nodes) { node in
                    let posX = (node.x / 100.0) * imageWidth
                    let posY = (node.y / 100.0) * imageHeight
                    let isSelected = selectedNodeId == node.id
                    
                    Button(action: {
                        selectNode(node.id, scrollProxy: scrollProxy)
                    }) {
                        ZStack {
                            // Selected Glowing Pulsing Ring
                            if isSelected {
                                Circle()
                                    .stroke(Color(red: 255/255, green: 59/255, blue: 0), lineWidth: 2.5)
                                    .frame(width: 32, height: 32)
                                    .background(
                                        Circle().fill(Color(red: 255/255, green: 59/255, blue: 0).opacity(0.35))
                                    )
                            }
                            
                            // Visual Node Badge
                            Circle()
                                .fill(isSelected ? Color(red: 255/255, green: 59/255, blue: 0) : Color.blue.opacity(0.9))
                                .frame(width: isSelected ? 26 : 22, height: isSelected ? 26 : 22)
                                .overlay(
                                    Circle().stroke(Color.white, lineWidth: 1.5)
                                )
                                .shadow(color: isSelected ? Color.red : Color.black.opacity(0.2), radius: isSelected ? 4 : 1.5)
                            
                            Text("\(node.id)")
                                .font(.system(size: isSelected ? 12 : 10, weight: .bold))
                                .foregroundColor(.white)
                        }
                        .frame(width: 44, height: 44) // Full 44x44 touch hit area
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(PlainButtonStyle())
                    .position(x: posX, y: posY)
                }
            }
            .frame(width: imageWidth, height: imageHeight)
            .padding(.bottom, 6)
        }
        .frame(maxWidth: .infinity)
        .background(Color.white)
        .cornerRadius(16)
        .shadow(color: Color.black.opacity(0.06), radius: 4, y: 2)
        .padding(.horizontal, 10)
        .padding(.top, 2)
        .padding(.bottom, 2)
    }
    
    // MARK: - Vehicle Weight Card
    private var weightCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Vehicle Weight")
                .font(.system(size: 13, weight: .bold))
                .foregroundColor(.black)
            
            HStack {
                TextField("0.0", text: $carWeight)
                    .keyboardType(.decimalPad)
                    .multilineTextAlignment(.center)
                    .font(.system(size: 15, weight: .semibold))
                    .frame(width: 110)
                    .padding(.vertical, 8)
                    .padding(.horizontal, 10)
                    .background(Color(white: 0.95))
                    .cornerRadius(8)
                
                Text("Ton")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(.gray)
                    .padding(.leading, 6)
                
                Spacer()
            }
        }
        .padding(12)
        .background(Color.white)
        .cornerRadius(12)
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color(white: 0.9), lineWidth: 1))
    }
    
    // MARK: - Sensor Node Textboxes List
    private var sensorCardsList: some View {
        LazyVStack(spacing: 8) {
            ForEach($nodes) { $node in
                let isSelected = selectedNodeId == node.id
                
                HStack(spacing: 12) {
                    // Node ID Badge
                    Text("\(node.id)")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundColor(.white)
                        .frame(width: 32, height: 32)
                        .background(isSelected ? Color(red: 255/255, green: 59/255, blue: 0) : Color.blue)
                        .clipShape(Circle())
                    
                    // Model-Specific Node Position Name
                    VStack(alignment: .leading, spacing: 2) {
                        Text(node.name)
                            .font(.system(size: 14, weight: .bold))
                            .foregroundColor(.black)
                        Text("Node ID: \(node.id)")
                            .font(.system(size: 11))
                            .foregroundColor(.gray)
                    }
                    
                    Spacer()
                    
                    // Editable Force Value Field
                    HStack(spacing: 4) {
                        TextField("0", text: $node.force)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.center)
                            .font(.system(size: 15, weight: .bold))
                            .frame(width: 80)
                            .padding(.vertical, 7)
                            .padding(.horizontal, 8)
                            .background(isSelected ? Color(red: 255/255, green: 59/255, blue: 0).opacity(0.1) : Color(white: 0.94))
                            .cornerRadius(8)
                            .overlay(
                                RoundedRectangle(cornerRadius: 8)
                                    .stroke(isSelected ? Color(red: 255/255, green: 59/255, blue: 0) : Color.clear, lineWidth: 2)
                            )
                            .onTapGesture {
                                selectedNodeId = node.id
                            }
                        
                        Text("N")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(.gray)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(isSelected ? Color(red: 255/255, green: 59/255, blue: 0).opacity(0.06) : Color.white)
                .cornerRadius(10)
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(isSelected ? Color(red: 255/255, green: 59/255, blue: 0) : Color(white: 0.88), lineWidth: isSelected ? 2 : 1)
                )
                .id("node_card_\(node.id)") // Anchored for ScrollViewReader
                .onTapGesture {
                    selectedNodeId = node.id
                }
            }
        }
    }
    
    // MARK: - Node Selection & Scroll Handler
    private func selectNode(_ id: Int, scrollProxy: ScrollViewProxy) {
        // 1. Physical Haptic Tap
        let generator = UIImpactFeedbackGenerator(style: .medium)
        generator.impactOccurred()
        
        // 2. Highlight Node
        selectedNodeId = id
        
        // 3. Automatically scroll the bottom textbox list so this node is centered/at top
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                scrollProxy.scrollTo("node_card_\(id)", anchor: .top)
            }
        }
    }
}


*/



import SwiftUI
import UIKit

// MARK: - Node Coordinates Database & Fallback

struct NodeCoordinate {

    let x: Double // Percentage from left (0 - 100)
    let y: Double // Percentage from top (0 - 100)

}

struct CarNodeCoordinates {

    // Exact percentage coordinates calibrated for each wireframe image:
    // Category 1: Sedan (30 nodes)

    static let sedan: [Int: NodeCoordinate] = [

        1:  NodeCoordinate(x: 51.36, y: 3.13),
        2:  NodeCoordinate(x: 25.37, y: 9.82),
        3:  NodeCoordinate(x: 77.43, y: 9.67),
        4:  NodeCoordinate(x: 51.37, y: 13.73),
        5:  NodeCoordinate(x: 51.38, y: 24.14),
        6:  NodeCoordinate(x: 27.06, y: 26.58),
        7:  NodeCoordinate(x: 75.77, y: 26.58),
        8:  NodeCoordinate(x: 26.30, y: 34.51),
        9:  NodeCoordinate(x: 77.29, y: 34.66),
        10: NodeCoordinate(x: 32.95, y: 40.52),
        11: NodeCoordinate(x: 70.49, y: 40.37),
        12: NodeCoordinate(x: 51.36, y: 41.72),
        13: NodeCoordinate(x: 51.33, y: 57.49),
        14: NodeCoordinate(x: 34.25, y: 54.62),
        15: NodeCoordinate(x: 23.13, y: 53.32),
        16: NodeCoordinate(x: 70.50, y: 54.62),
        17: NodeCoordinate(x: 79.79, y: 53.15),
        18: NodeCoordinate(x: 33.66, y: 65.49),
        19: NodeCoordinate(x: 23.72, y: 71.05),
        20: NodeCoordinate(x: 70.95, y: 65.48),
        21: NodeCoordinate(x: 79.86, y: 71.35),
        22: NodeCoordinate(x: 51.38, y: 71.64),
        23: NodeCoordinate(x: 51.38, y: 81.07),
        24: NodeCoordinate(x: 31.68, y: 77.21),
        25: NodeCoordinate(x: 73.57, y: 77.21),
        26: NodeCoordinate(x: 27.62, y: 84.93),
        27: NodeCoordinate(x: 76.35, y: 84.95),
        28: NodeCoordinate(x: 31.64, y: 92.24),
        29: NodeCoordinate(x: 72.42, y: 92.24),
        30: NodeCoordinate(x: 51.33, y: 95.63)
    ]

    // Category 2: SUV (25 nodes)

    static let suv: [Int: NodeCoordinate] = [

        1:  NodeCoordinate(x: 48.55, y: 4.25),
        2:  NodeCoordinate(x: 75.07, y: 6.36),
        3:  NodeCoordinate(x: 21.29, y: 7.99),
        4:  NodeCoordinate(x: 48.07, y: 22.98),
        5:  NodeCoordinate(x: 19.10, y: 27.01),
        6:  NodeCoordinate(x: 79.22, y: 27.75),
        7:  NodeCoordinate(x: 24.95, y: 34.04),
        8:  NodeCoordinate(x: 48.30, y: 33.15),
        9:  NodeCoordinate(x: 72.38, y: 34.05),
        10: NodeCoordinate(x: 16.86, y: 48.41),
        11: NodeCoordinate(x: 24.24, y: 48.24),
        12: NodeCoordinate(x: 73.30, y: 48.10),
        13: NodeCoordinate(x: 80.52, y: 47.81),
        14: NodeCoordinate(x: 48.25, y: 55.15), // Roof Center
        15: NodeCoordinate(x: 23.98, y: 62.47),
        16: NodeCoordinate(x: 73.09, y: 63.06),
        17: NodeCoordinate(x: 16.15, y: 67.87),
        18: NodeCoordinate(x: 81.20, y: 66.82),
        19: NodeCoordinate(x: 21.99, y: 78.20),
        20: NodeCoordinate(x: 48.54, y: 77.00), // Rear Cabin Center
        21: NodeCoordinate(x: 76.08, y: 78.19),
        22: NodeCoordinate(x: 48.30, y: 84.62), // Rear Center Upper
        23: NodeCoordinate(x: 20.09, y: 92.85),
        24: NodeCoordinate(x: 48.51, y: 94.50), // Spare Wheel Area
        25: NodeCoordinate(x: 78.03, y: 93.01),
        26:  NodeCoordinate(x: 48.07, y: 15),
    ]

    // Category 3: Hatchback (23 nodes)

    static let hatchback: [Int: NodeCoordinate] = [

        1:  NodeCoordinate(x: 44.75, y: 5.04),
        2:  NodeCoordinate(x: 27.08, y: 9.08),
        3:  NodeCoordinate(x: 64.52, y: 9.09),
        4:  NodeCoordinate(x: 44.57, y: 14.78),
        5:  NodeCoordinate(x: 44.57, y: 23.64),
        6:  NodeCoordinate(x: 25.52, y: 27.23),
        7:  NodeCoordinate(x: 65.93, y: 27.10),
        8:  NodeCoordinate(x: 30.24, y: 36.53),
        9:  NodeCoordinate(x: 45.26, y: 36.53), // Center Cabin
        10: NodeCoordinate(x: 60.51, y: 35.93),
        11: NodeCoordinate(x: 26.20, y: 50.93),
        12: NodeCoordinate(x: 65.57, y: 49.13),
        13: NodeCoordinate(x: 31.10, y: 55.60),
        14: NodeCoordinate(x: 45.47, y: 53.18), // Cabin Floor Center (Roof Center)
        15: NodeCoordinate(x: 61.89, y: 53.93),
        16: NodeCoordinate(x: 24.26, y: 70.43),
        17: NodeCoordinate(x: 65.76, y: 70.75),
        18: NodeCoordinate(x: 31.40, y: 76.89),
        19: NodeCoordinate(x: 44.91, y: 75.85), // Rear Seat Center
        20: NodeCoordinate(x: 58.74, y: 75.85),
        21: NodeCoordinate(x: 26.91, y: 87.84),
        22: NodeCoordinate(x: 64.37, y: 87.41),
        23: NodeCoordinate(x: 45.60, y: 92.39)  // Rear Center
    ]

    static func getCoordinate(for categoryId: Int, carType: String, nodeId: Int) -> NodeCoordinate {

        let typeLower = carType.lowercased()

        if categoryId == 1 || typeLower.contains("sedan") {
            return sedan[nodeId] ?? NodeCoordinate(x: 51.36, y: 50)
        } else if categoryId == 2 || typeLower.contains("suv") {
            return suv[nodeId] ?? NodeCoordinate(x: 48.25, y: 50)
        } else {
            return hatchback[nodeId] ?? NodeCoordinate(x: 45.47, y: 50)
        }
    }

    static func defaultNodes(for categoryId: Int, carType: String) -> [NodeModel] {

        let typeLower = carType.lowercased()

        let isSedan = categoryId == 1 || typeLower.contains("sedan")
        let isSuv = categoryId == 2 || typeLower.contains("suv")

        if isSedan {

        /*    let names = [
                1: "Front-Left", 2: "Front-Center", 3: "Front-Right", 4: "Engine",
                5: "Mid-Left", 6: "Mid-Center", 7: "Mid-Right", 8: "Left-A",
                9: "Right-A", 10: "Left-B", 11: "Right-B", 12: "Center-A",
                13: "Core", 14: "Left-C", 15: "Right-C", 16: "Left-D",
                17: "Right-D", 18: "Left-E", 19: "Right-E", 20: "Center-B",
                21: "Left-F", 22: "Center-C", 23: "Rear-Core", 24: "Rear-Left",
                25: "Rear-Right", 26: "Back-A", 27: "Back-B", 28: "Back-C",
                29: "Back-D", 30: "Back-End"
            ]*/
            let names = [
                1: "Front Bumper Center / Grille",
                2: "Front Left Headlight / Corner",
                3: "Front Right Headlight / Corner",
                4: "Engine Hood / Bonnet",
                5: "Windshield Base / Cowl",
                6: "Left A-Pillar (Lower / Front Fender Area)",
                7: "Right A-Pillar (Lower / Front Fender Area)",
                8: "Left Side Mirror / Front Door Forward Anchor",
                9: "Right Side Mirror / Front Door Forward Anchor",
                10: "Left A-Pillar (Upper / Windshield Frame)",
                11: "Right A-Pillar (Upper / Windshield Frame)",
                12: "Front Roof Crossmember / Header",
                13: "Main Roof Panel / Cabin Overhead",
                14: "Left B-Pillar (Upper / Center Roof Rail)",
                15: "Left B-Pillar (Exterior Side / Door Pillar)",
                16: "Right B-Pillar (Upper / Center Roof Rail)",
                17: "Right B-Pillar (Exterior Side / Door Pillar)",
                18: "Left C-Pillar (Upper / Rear Roof Rail)",
                19: "Left Rear Door / Quarter Panel Joint",
                20: "Right C-Pillar (Upper / Rear Roof Rail)",
                21: "Right Rear Door / Quarter Panel Joint",
                22: "Rear Windshield Top / Header",
                23: "Rear Windshield / Trunk Lid (Boot Lid)",
                24: "Left Rear Quarter Panel / C-Pillar Lower",
                25: "Right Rear Quarter Panel / C-Pillar Lower",
                26: "Left Rear Fender / Wheel Arch Area",
                27: "Right Rear Fender / Wheel Arch Area",
                28: "Rear Left Bumper Corner / Taillight",
                29: "Rear Right Bumper Corner / Taillight",
                30: "Rear Bumper Center"
            ]

            return (1...30).map { id in

                let coord = sedan[id] ?? NodeCoordinate(x: 50, y: 50)

                return NodeModel(
                    id: id,
                    name: names[id] ?? "Node \(id)",
                    force: "2",
                    x: coord.x,
                    y: coord.y
                )
            }

        } else if isSuv {

        /*    let names = [
                1: "Front Center", 2: "Front Right Corner", 3: "Front Left Corner", 4: "Dashboard Center",
                5: "Front Left Door", 6: "Front Right Door", 7: "Left Side Upper", 8: "Engine Center",
                9: "Right Side Upper", 10: "Left Mirror Area", 11: "Left Door Mid", 12: "Right Door Mid",
                13: "Right Mirror Area", 14: "Roof Center", 15: "Left Rear Door", 16: "Right Rear Door",
                17: "Left Back Pillar", 18: "Right Back Pillar", 19: "Rear Left Side", 20: "Rear Cabin Center",
                21: "Rear Right Side", 22: "Rear Center Upper", 23: "Rear Left Corner", 24: "Spare Wheel Area",
                25: "Rear Right Corner" , 26: "top left"
            ]
*/
            let names = [
                1: "Front Bumper Center / Grille",
                2: "Front Right Headlight / Corner",
                3: "Front Left Headlight / Corner",
                4: "Windshield Base Center / Cowl",
                5: "Left Front Fender / A-Pillar Lower Anchor",
                6: "Right Front Fender / A-Pillar Lower Anchor",
                7: "Left Windshield Pillar (A-Pillar Base)",
                8: "Windshield Header Center / Front Roof Rail",
                9: "Right Windshield Pillar (A-Pillar Base)",
                10: "Left Front Door / Exterior B-Pillar Outer",
                11: "Left Side Roof Rail (B-Pillar Upper)",
                12: "Right Side Roof Rail (B-Pillar Upper)",
                13: "Right Front Door / Exterior B-Pillar Outer",
                14: "Main Roof Center Panel",
                15: "Left Rear Roof Rail (C-Pillar Upper)",
                16: "Right Rear Roof Rail (C-Pillar Upper)",
                17: "Left Rear Door / Side Body Panel",
                18: "Right Rear Door / Side Body Panel",
                19: "Left C/D-Pillar / Quarter Panel Joint",
                20: "Rear Roof Crossmember / Antennas Area",
                21: "Right C/D-Pillar / Quarter Panel Joint",
                22: "Rear Hatch / Tailgate Glass Header",
                23: "Rear Left Bumper Corner / Taillight",
                24: "Rear Center Spare Tire Mount / Trunk Lid",
                25: "Rear Right Bumper Corner / Taillight",
                26: "Hood Center / Engine Bay Core"
            ]
            
            
            return (1...26).map { id in

                let coord = suv[id] ?? NodeCoordinate(x: 50, y: 50)

                return NodeModel(
                    id: id,
                    name: names[id] ?? "Node \(id)",
                    force: "10",
                    x: coord.x,
                    y: coord.y
                )
            }

        } else { // Hatchback

          /*  let names = [
                1: "Front Center", 2: "Front Left Corner", 3: "Front Right Corner", 4: "Engine Top",
                5: "Dashboard Center", 6: "Left Pillar Front", 7: "Right Pillar Front", 8: "Left Door Upper",
                9: "Center Cabin", 10: "Right Door Upper", 11: "Left Door Middle", 12: "Right Door Middle",
                13: "Left Door Lower", 14: "Cabin Floor Center", 15: "Right Door Lower", 16: "Left Rear Door",
                17: "Right Rear Door", 18: "Rear Seat Left", 19: "Rear Seat Center", 20: "Rear Seat Right",
                21: "Rear Left Corner", 22: "Rear Right Corner", 23: "Rear Center"
            ]
   */
            let names = [
                1: "Front Bumper Center / Grille",
                2: "Front Left Headlight / Corner",
                3: "Front Right Headlight / Corner",
                4: "Engine Hood / Bonnet",
                5: "Windshield Base / Cowl",
                6: "Left A-Pillar (Lower / Front Fender Joint)",
                7: "Right A-Pillar (Lower / Front Fender Joint)",
                8: "Left A-Pillar (Upper / Windshield Frame)",
                9: "Front Roof Crossmember / Windshield Header Center",
                10: "Right A-Pillar (Upper / Windshield Frame)",
                11: "Left Side Mirror / Front Door Upper Edge",
                12: "Right Side Mirror / Front Door Upper Edge",
                13: "Left B-Pillar (Roof Rail / Upper Pillar)",
                14: "Main Roof Center Panel",
                15: "Right B-Pillar (Roof Rail / Upper Pillar)",
                16: "Left Rear Door / B-Pillar Lower Outer",
                17: "Right Rear Door / B-Pillar Lower Outer",
                18: "Left C-Pillar (Upper Roof Rail Joint)",
                19: "Rear Roof Crossmember / Hatch Header Center",
                20: "Right C-Pillar (Upper Roof Rail Joint)",
                21: "Rear Left Quarter Panel / C-Pillar Lower",
                22: "Rear Right Quarter Panel / C-Pillar Lower",
                23: "Rear Bumper Center / Tailgate Base"
            ]
            
            return (1...23).map { id in

                let coord = hatchback[id] ?? NodeCoordinate(x: 50, y: 50)

                return NodeModel(
                    id: id,
                    name: names[id] ?? "Node \(id)",
                    force: "8",
                    x: coord.x,
                    y: coord.y
                )
            }
        }
    }
}

// MARK: - Network Models

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
    var name: String
    var force: String
    var x: Double
    var y: Double

}

// MARK: - ConfigureNodes Main View

struct ConfigureNodes: View {

    @Environment(\.presentationMode) var presentationMode

    let categoryId: Int
    let carName: String
    let carType: String
    var onLogout: () -> Void = {}

    @State private var carWeight: String = "1.50"
    @State private var nodes: [NodeModel] = []
    @State private var selectedNodeId: Int? = nil
    @State private var isSaving: Bool = false
    @State private var saveMessage: String? = nil
    @State private var showSaveAlert: Bool = false
    @State private var syncStatus: String = "Ready"
    //dor car div zoom
   
    @State private var scale: CGFloat = 1.0
    @State private var lastScale: CGFloat = 1.0
    @State private var offset: CGSize = .zero
    @State private var lastOffset: CGSize = .zero

    private var isSedan: Bool {
        categoryId == 1 || carType.lowercased().contains("sedan")
    }

    private var isSuv: Bool {
        categoryId == 2 || carType.lowercased().contains("suv")
    }

    private var isHatchback: Bool {
        categoryId == 3 || carType.lowercased().contains("hatchback")
    }

    private var carImageName: String {

        if isSedan {
            return "sedan"
        }

        if isSuv {
            return "suv"
        }

        return "hatchback"
    }

    // Exact Aspect Ratio for each Car Wireframe

    private var carAspectRatio: CGFloat {

        if isSedan {
            return 948.0 / 1659.0
        } else if isSuv {
            return 624.0 / 1024.0
        } else {
            return 878.0 / 1024.0
        }
    }

    // MARK: - API Calls

    func fetchData() {

        syncStatus = "Loading from server..."

        guard let url = URL(string: "\(AppConfig.apiBaseURL)/ConfigureNodes/GetNodes?categoryId=\(categoryId)") else {

            syncStatus = "Invalid API URL"

            return
        }

        var request = URLRequest(url: url)

        request.timeoutInterval = 8

        URLSession.shared.dataTask(with: request) { data, response, error in

            DispatchQueue.main.async {

                if let error = error {

                    self.syncStatus = "Using Local Defaults (API Offline)"

                    print("Fetch failed: \(error.localizedDescription)")

                    return
                }

                guard let data = data else {

                    self.syncStatus = "No data from server"

                    return
                }

                if let httpResponse = response as? HTTPURLResponse,
                   httpResponse.statusCode >= 400 {

                    let serverMsg = String(data: data, encoding: .utf8) ?? ""

                    self.syncStatus = "Server error \(httpResponse.statusCode)"

                    print("Server returned error \(httpResponse.statusCode): \(serverMsg)")

                    return
                }

                do {

                    let responseData = try JSONDecoder().decode(
                        NodesResponse.self,
                        from: data
                    )

                    // Always start with canonical model-specific nodes

                    var currentNodes = CarNodeCoordinates.defaultNodes(
                        for: self.categoryId,
                        carType: self.carType
                    )

                    // If database has saved values, update the force values

                    if !responseData.Nodes.isEmpty {

                        for i in 0..<currentNodes.count {

                            if let serverNode = responseData.Nodes.first(
                                where: { $0.Node_Id == currentNodes[i].id }
                            ),
                               let serverForce = serverNode.Force {

                                currentNodes[i].force = String(
                                    format: "%.0f",
                                    serverForce
                                )
                            }
                        }

                        self.syncStatus = "Synced with Database"
                    }

                    self.nodes = currentNodes

                    if let w = responseData.Weight {

                        self.carWeight = String(
                            format: "%.2f",
                            w
                        )
                    }

                } catch {

                    self.syncStatus = "Data parsed with fallback"

                    print("Error decoding: \(error)")
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

        isSaving = true

        let payload = nodes.map {

            SaveNodePayload(
                Node_Id: $0.id,
                Category_Id: categoryId,
                Node_Position: $0.name,
                Force: Double($0.force) ?? 0.0
            )
        }

        let weightVal = Double(carWeight) ?? 0.0

        guard let url = URL(
            string: "\(AppConfig.apiBaseURL)/ConfigureNodes/SaveConfiguration?weight=\(weightVal)"
        ) else {

            isSaving = false

            return
        }

        var request = URLRequest(url: url)

        request.httpMethod = "POST"

        request.setValue(
            "application/json",
            forHTTPHeaderField: "Content-Type"
        )

        request.timeoutInterval = 10

        request.httpBody = try? JSONEncoder().encode(payload)

        URLSession.shared.dataTask(with: request) { data, response, error in

            DispatchQueue.main.async {

                isSaving = false

                if let error = error {

                    self.saveMessage = "Network error: \(error.localizedDescription)"

                    self.showSaveAlert = true

                    return
                }

                if let httpResponse = response as? HTTPURLResponse,
                   httpResponse.statusCode >= 200 &&
                   httpResponse.statusCode < 300 {

                    self.saveMessage = "Configuration saved successfully to Database!"

                    self.showSaveAlert = true

                    fetchData()

                } else {

                    let serverMsg = String(
                        data: data ?? Data(),
                        encoding: .utf8
                    ) ?? ""

                    self.saveMessage = "Failed to save: \(serverMsg)"

                    self.showSaveAlert = true
                }
            }

        }.resume()
    }

    // MARK: - Main Body

    var body: some View {

        ScrollViewReader { scrollProxy in

            VStack(spacing: 0) {

                // 1. TOP BAR

                headerView

                // 2. SUB-HEADER (Back, Car Name, Save)

                carSubHeader

                // 3. FIXED & PINNED CAR DISPLAY
                // (Stays on screen, does NOT scroll away!)

                fixedCarSection(scrollProxy: scrollProxy)
                    .zIndex(10)

                // 4. SCROLLABLE SENSOR TEXTBOXES SECTION

                ScrollView(.vertical, showsIndicators: true) {

                    VStack(spacing: 12) {

                        // Vehicle Weight Card

                        weightCard
                            .padding(.top, 6)

                        // Section Divider / Header

                        HStack {

                            VStack(alignment: .leading, spacing: 2) {

                                Text("Sensor Thresholds")
                                    .font(.system(size: 14, weight: .bold))
                                    .foregroundColor(.black)

                                Text("Tap node on car above to jump directly to its textbox")
                                    .font(.system(size: 11))
                                    .foregroundColor(.gray)
                            }

                            Spacer()

                            Text("\(nodes.count) Sensors")
                                .font(.system(size: 11, weight: .bold))
                                .padding(.horizontal, 8)
                                .padding(.vertical, 3)
                                .background(Color.blue.opacity(0.12))
                                .foregroundColor(.blue)
                                .cornerRadius(6)
                        }
                        .padding(.horizontal, 4)
                        .padding(.top, 2)

                        // The Node Textbox Cards

                        sensorCardsList
                    }
                    .padding(.horizontal, 12)
                    .padding(.bottom, 40)
                }
            }
        }

        .background(
            Color(
                red: 243/255,
                green: 244/255,
                blue: 246/255
            )
            .edgesIgnoringSafeArea(.bottom)
        )

        .navigationBarHidden(true)

        .alert(isPresented: $showSaveAlert) {

            Alert(
                title: Text("Node Configuration"),
                message: Text(saveMessage ?? ""),
                dismissButton: .default(Text("OK"))
            )
        }

        .onAppear {

            if self.nodes.isEmpty {

                self.nodes = CarNodeCoordinates.defaultNodes(
                    for: categoryId,
                    carType: carType
                )
            }

            fetchData()
        }
    }

    // MARK: - Header

    private var headerView: some View {

        HStack {

            HStack(spacing: 12) {

                Text("A")
                    .bold()
                    .foregroundColor(.white)
                    .frame(width: 38, height: 38)
                    .background(
                        Color(
                            red: 255/255,
                            green: 59/255,
                            blue: 0
                        )
                    )
                    .cornerRadius(10)

                VStack(alignment: .leading, spacing: 2) {

                    Text("Admin Dashboard")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundColor(.black)

                    Text("Interactive Sensor Mapping")
                        .foregroundColor(.gray)
                        .font(.system(size: 11))
                }
            }

            Spacer()

            Button(action: onLogout) {

                Image(systemName: "rectangle.portrait.and.arrow.right")
                    .font(.system(size: 19, weight: .semibold))
                    .foregroundColor(.red)
            }
        }

        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(Color.white)
        .shadow(
            color: Color.black.opacity(0.04),
            radius: 2,
            y: 1
        )
    }

    // MARK: - Sub Header

    private var carSubHeader: some View {

        HStack {

            Button(
                action: {
                    presentationMode.wrappedValue.dismiss()
                }
            ) {

                HStack(spacing: 5) {

                    Image(systemName: "chevron.left")
                        .font(.system(size: 15, weight: .bold))

                    Text("Back")
                        .font(.system(size: 14, weight: .medium))
                }

                .foregroundColor(.black)
            }

            Spacer()

            VStack(alignment: .center, spacing: 1) {

                Text(carName)
                    .font(.system(size: 15, weight: .bold))
                    .foregroundColor(.black)

                Text(carType.uppercased())
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(
                        Color(
                            red: 255/255,
                            green: 59/255,
                            blue: 0
                        )
                    )
            }

            Spacer()

            Button(action: saveConfiguration) {

                HStack(spacing: 4) {

                    if isSaving {

                        ProgressView()
                            .progressViewStyle(
                                CircularProgressViewStyle(tint: .white)
                            )
                            .scaleEffect(0.75)

                    } else {

                        Image(systemName: "checkmark")
                            .font(.system(size: 12, weight: .bold))
                    }

                    Text("Save")
                        .font(.system(size: 13, weight: .bold))
                }

                .foregroundColor(.white)
                .padding(.horizontal, 14)
                .padding(.vertical, 7)
                .background(
                    Color(
                        red: 255/255,
                        green: 59/255,
                        blue: 0
                    )
                )
                .cornerRadius(8)
            }

            .disabled(isSaving)
        }

        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(Color.white)
    }

    // MARK: - FIXED CAR DISPLAY SECTION

    private func fixedCarSection(
        scrollProxy: ScrollViewProxy
    ) -> some View {

        let imageHeight: CGFloat = 410
        let imageWidth = imageHeight * carAspectRatio

        return VStack(spacing: 2) {

            // Selected Node & Status Indicator Banner

            HStack {

                Circle()
                    .fill(
                        syncStatus.contains("Synced")
                        ? Color.green
                        : Color.orange
                    )
                    .frame(width: 7, height: 7)

                Text(syncStatus)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.gray)

                Spacer()

                if let selected = selectedNodeId {

                    Text("Selected: Node \(selected)")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(
                            Color(
                                red: 255/255,
                                green: 59/255,
                                blue: 0
                            )
                        )
                        .padding(.horizontal, 8)
                        .padding(.vertical, 2)
                        .background(
                            Color(
                                red: 255/255,
                                green: 59/255,
                                blue: 0
                            )
                            .opacity(0.12)
                        )
                        .cornerRadius(6)

                } else {

                    Text("Tap any node to jump to textbox")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.gray)
                }
            }

            .padding(.horizontal, 14)
            .padding(.top, 4)

            // MARK: - Centered Car Visualizer

            
            ZStack {
                Image(carImageName)
                    .resizable()
                    .scaledToFit()
                    .frame(width: imageWidth, height: imageHeight)

                ForEach(nodes) { node in
                    let posX = (node.x / 100.0) * imageWidth
                    let posY = (node.y / 100.0) * imageHeight
                    let isSelected = selectedNodeId == node.id

                    Button(action: {
                        selectNode(node.id, scrollProxy: scrollProxy)
                    }) {
                        ZStack {
                            if isSelected {
                                Circle()
                                    .stroke(
                                        Color(red: 255/255, green: 59/255, blue: 0),
                                        lineWidth: 2.5
                                    )
                                    .frame(width: 32, height: 32)
                                    .background(
                                        Circle()
                                            .fill(
                                                Color(red: 255/255, green: 59/255, blue: 0)
                                                    .opacity(0.35)
                                            )
                                    )
                            }

                            Circle()
                                .fill(
                                    isSelected
                                    ? Color(red: 255/255, green: 59/255, blue: 0)
                                    : Color.blue.opacity(0.9)
                                )
                                .frame(
                                    width: isSelected ? 26 : 22,
                                    height: isSelected ? 26 : 22
                                )
                                .overlay(
                                    Circle()
                                        .stroke(Color.white, lineWidth: 1.5)
                                )

                            Text("\(node.id)")
                                .font(
                                    .system(
                                        size: isSelected ? 12 : 10,
                                        weight: .bold
                                    )
                                )
                                .foregroundColor(.white)
                        }
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(PlainButtonStyle())
                    .position(x: posX, y: posY)
                }
            }
            .frame(width: imageWidth, height: imageHeight)
            .scaleEffect(scale)
            .offset(offset)
            .simultaneousGesture(
                MagnificationGesture()
                    .onChanged { value in
                        let newScale = lastScale * value

                        scale = min(max(newScale, 1.0), 4.0)

                        // Return to original position when completely unzoomed
                        if scale <= 1.0 {
                            offset = .zero
                            lastOffset = .zero
                        }
                    }
                    .onEnded { _ in
                        lastScale = scale
                    }
            )
            .simultaneousGesture(
                DragGesture()
                    .onChanged { value in
                        // Allow moving the zoomed car
                        offset = CGSize(
                            width: lastOffset.width + value.translation.width,
                            height: lastOffset.height + value.translation.height
                        )
                    }
                    .onEnded { _ in
                        lastOffset = offset
                    }
            )
            .animation(.easeOut(duration: 0.15), value: scale)
            
            .frame(width: imageWidth, height: imageHeight)
            .scaleEffect(scale)
            .gesture(
                MagnificationGesture()
                    .onChanged { value in
                        let newScale = lastScale * value

                        // Minimum = original size (1x)
                        // Maximum = 4x zoom
                        scale = min(max(newScale, 1.0), 4.0)
                    }
                    .onEnded { _ in
                        lastScale = scale
                    }
            )

            // IMPORTANT:
            // Scale the entire ZStack instead of only the Image.
            // This makes both the car image AND all nodes zoom together.

            .frame(
                width: imageWidth,
                height: imageHeight
            )

            .scaleEffect(scale)

            .gesture(
                MagnificationGesture()
                    .onChanged { value in

                        scale = max(
                            1,
                            min(value, 4)
                        )
                    }
            )

            .padding(.bottom, 6)
        }

        .frame(maxWidth: .infinity)

        .background(Color.white)

        .cornerRadius(16)

        .shadow(
            color: Color.black.opacity(0.06),
            radius: 4,
            y: 2
        )

        .padding(.horizontal, 10)
        .padding(.top, 2)
        .padding(.bottom, 2)
    }

    // MARK: - Vehicle Weight Card

    private var weightCard: some View {

        VStack(alignment: .leading, spacing: 6) {

            Text("Vehicle Weight")
                .font(.system(size: 13, weight: .bold))
                .foregroundColor(.black)

            HStack {

                TextField(
                    "0.0",
                    text: $carWeight
                )
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.center)
                .font(
                    .system(
                        size: 15,
                        weight: .semibold
                    )
                )
                .frame(width: 110)
                .padding(.vertical, 8)
                .padding(.horizontal, 10)
                .background(Color(white: 0.95))
                .cornerRadius(8)

                Text("Ton")
                    .font(
                        .system(
                            size: 14,
                            weight: .medium
                        )
                    )
                    .foregroundColor(.gray)
                    .padding(.leading, 6)

                Spacer()
            }
        }

        .padding(12)

        .background(Color.white)

        .cornerRadius(12)

        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(
                    Color(white: 0.9),
                    lineWidth: 1
                )
        )
    }

    // MARK: - Sensor Node Textboxes List

    private var sensorCardsList: some View {

        LazyVStack(spacing: 8) {

            ForEach($nodes) { $node in

                let isSelected = selectedNodeId == node.id

                HStack(spacing: 12) {

                    // Node ID Badge

                    Text("\(node.id)")
                        .font(
                            .system(
                                size: 13,
                                weight: .bold
                            )
                        )
                        .foregroundColor(.white)
                        .frame(
                            width: 32,
                            height: 32
                        )
                        .background(
                            isSelected
                            ? Color(
                                red: 255/255,
                                green: 59/255,
                                blue: 0
                            )
                            : Color.blue
                        )
                        .clipShape(Circle())

                    // Model-Specific Node Position Name

                    VStack(alignment: .leading, spacing: 2) {

                        Text(node.name)
                            .font(
                                .system(
                                    size: 14,
                                    weight: .bold
                                )
                            )
                            .foregroundColor(.black)

                        Text("Node ID: \(node.id)")
                            .font(.system(size: 11))
                            .foregroundColor(.gray)
                    }

                    Spacer()

                    // Editable Force Value Field

                    HStack(spacing: 4) {

                        TextField(
                            "0",
                            text: $node.force
                        )
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.center)
                        .font(
                            .system(
                                size: 15,
                                weight: .bold
                            )
                        )
                        .frame(width: 80)
                        .padding(.vertical, 7)
                        .padding(.horizontal, 8)
                        .background(
                            isSelected
                            ? Color(
                                red: 255/255,
                                green: 59/255,
                                blue: 0
                            ).opacity(0.1)
                            : Color(white: 0.94)
                        )
                        .cornerRadius(8)
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(
                                    isSelected
                                    ? Color(
                                        red: 255/255,
                                        green: 59/255,
                                        blue: 0
                                    )
                                    : Color.clear,
                                    lineWidth: 2
                                )
                        )
                        .onTapGesture {

                            selectedNodeId = node.id
                        }

                        Text("N")
                            .font(
                                .system(
                                    size: 12,
                                    weight: .semibold
                                )
                            )
                            .foregroundColor(.gray)
                    }
                }

                .padding(.horizontal, 12)
                .padding(.vertical, 10)

                .background(
                    isSelected
                    ? Color(
                        red: 255/255,
                        green: 59/255,
                        blue: 0
                    ).opacity(0.06)
                    : Color.white
                )

                .cornerRadius(10)

                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(
                            isSelected
                            ? Color(
                                red: 255/255,
                                green: 59/255,
                                blue: 0
                            )
                            : Color(white: 0.88),
                            lineWidth: isSelected ? 2 : 1
                        )
                )

                .id("node_card_\(node.id)")

                .onTapGesture {

                    selectedNodeId = node.id
                }
            }
        }
    }

    // MARK: - Node Selection & Scroll Handler

    private func selectNode(
        _ id: Int,
        scrollProxy: ScrollViewProxy
    ) {

        // 1. Physical Haptic Tap

        let generator = UIImpactFeedbackGenerator(
            style: .medium
        )

        generator.impactOccurred()

        // 2. Highlight Node

        selectedNodeId = id

        // 3. Automatically scroll the bottom textbox list

        DispatchQueue.main.asyncAfter(
            deadline: .now() + 0.05
        ) {

            withAnimation(
                .spring(
                    response: 0.4,
                    dampingFraction: 0.8
                )
            ) {

                scrollProxy.scrollTo(
                    "node_card_\(id)",
                    anchor: .top
                )
            }
        }
    }
}
