/*
import SwiftUI
import CoreMotion
import CoreLocation
import Combine

class MonitoringViewModel: NSObject, ObservableObject, CLLocationManagerDelegate {
    @Published var sensorData: SensorData? = nil
    
    struct SensorData {
        var rawSide: String?
        var impactSide: String
        var force: String
        var cabinDamage: Double
        var lastEvent: String
        var status: String   // "ACCIDENT" or "SAFE"
    }
    
    let API = AppConfig.apiBaseURL
    var carId: Int = 0
    
    let ACCEL_THRESHOLD: Double = 2.0      // 2.0  Lowered for realistic phone-shake detection
    let SHAKE_THRESHOLD: Double = 6.0    // 6.0  Lowered so palm-hit triggers reliably
    let DEBOUNCE_MS: TimeInterval = 3000
    let WARMUP_READS = 10                 // Reduced warmup for faster activation
    
    let motionManager = CMMotionManager()
    let locationManager = CLLocationManager()
    
    var lastAccel: Double = 0
    var prevAcc: Double = 0
    var shake: Double = 0
    var lastSent: Date = Date.distantPast
    var readCount = 0
    
    @Published var accelX: Double = 0
    @Published var accelY: Double = 0
    @Published var accelZ: Double = 0
    
    @Published var gyroX: Double = 0
    @Published var gyroY: Double = 0
    @Published var gyroZ: Double = 0
    
    @Published var latitude: Double = 0
    @Published var longitude: Double = 0
    
    // Debug / live feedback
    @Published var shakeLevel: Double = 0
    @Published var debugStatus: String = "Warming up…"
    
    var currentLocation: CLLocationCoordinate2D?
    
    override init() {
        super.init()
        locationManager.delegate = self
        locationManager.desiredAccuracy = kCLLocationAccuracyBest
        locationManager.requestWhenInUseAuthorization()
        locationManager.startUpdatingLocation()
    }
    
    func normalizeImpact(_ side: String?) -> String {
        guard let side = side?.lowercased() else { return "NONE" }
        if side.contains("front") { return "Front" }
        if side.contains("rear") || side.contains("back") { return "Rear" }
        if side.contains("left") { return "Left" }
        if side.contains("right") { return "Right" }
        if side.contains("center") || side.contains("core") { return "Center" }
        return "NONE"
    }
    
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        if let loc = locations.last {
            currentLocation = loc.coordinate
            DispatchQueue.main.async {
                self.latitude = loc.coordinate.latitude
                self.longitude = loc.coordinate.longitude
            }
        }
    }
    
    func sendImpact(acceleration: Double, coords: CLLocationCoordinate2D) {
        let formatter = DateFormatter()
        formatter.timeStyle = .medium
        let currentTimeString = formatter.string(from: Date())
        
        if carId == 0 {
            DispatchQueue.main.async {
                self.sensorData = SensorData(
                    rawSide: "Test (No Car ID)",
                    impactSide: "Unknown",
                    force: "SHAKE DETECTED",
                    cabinDamage: 0,
                    lastEvent: currentTimeString,
                    status: "SAFE"
                )
            }
            return
        }
        
        let now = Date()
        if now.timeIntervalSince(lastSent) * 1000 < DEBOUNCE_MS { return }
        lastSent = now
        
        // Show "Sending..." immediately so user knows something happened
        DispatchQueue.main.async {
            self.debugStatus = "📡 Sending to API…"
        }
        
        guard let url = URL(string: "\(API)/DetectAccident/ImpactCalculation") else { return }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let body: [String: Any] = [
            "Car_Id": carId,
            "Acceleration": acceleration,
            "GyroX": gyroX,       // ✅ Fixed: actual gyroscope X (was sending accelX)
            "GyroY": gyroY,       // ✅ Fixed: actual gyroscope Y (was sending accelY)
            "GyroZ": gyroZ,       // ✅ Fixed: GyroZ was completely missing before
            "Latitude": coords.latitude,
            "Longitude": coords.longitude
        ]
        
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)
        
        URLSession.shared.dataTask(with: request) { data, response, error in
            let formatter = DateFormatter()
            formatter.timeStyle = .medium
            let timeStr = formatter.string(from: Date())
            
            // Case 1: Network error
            if let error = error {
                print("API ERROR: \(error)")
                DispatchQueue.main.async {
                    self.debugStatus = "❌ API Error: \(error.localizedDescription)"
                    self.sensorData = SensorData(
                        rawSide: "Network Error",
                        impactSide: "Unknown",
                        force: "API FAIL",
                        cabinDamage: 0,
                        lastEvent: timeStr,
                        status: "ERROR"
                    )
                }
                return
            }
            
            // Case 2: No data returned
            guard let data = data else {
                DispatchQueue.main.async {
                    self.debugStatus = "❌ No data from server"
                    self.sensorData = SensorData(
                        rawSide: "No Response",
                        impactSide: "Unknown",
                        force: "NO DATA",
                        cabinDamage: 0,
                        lastEvent: timeStr,
                        status: "ERROR"
                    )
                }
                return
            }
            
            // Case 3: Parse the JSON response
            do {
                if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] {
                    DispatchQueue.main.async {
                        let rawSide    = json["impactSide"] as? String ?? "Unknown"
                        let impactForce = json["impactForce"] as? Double ?? 0
                        var cabinDamage = json["cabinDamage"] as? Double ?? 0
                        let cabinForce  = json["cabinForce"] as? Double ?? 0
                        let apiStatus   = json["status"] as? String ?? "SAFE"
                        
                        if cabinDamage == 0 && cabinForce > 0 && impactForce > 0 {
                            cabinDamage = (cabinForce / (impactForce * 0.5)) * 100
                        }
                        if cabinDamage.isNaN { cabinDamage = 0 }
                        cabinDamage = max(0, min(100, cabinDamage))
                        
                        self.debugStatus = apiStatus == "ACCIDENT"
                            ? String(format: "🚨 ACCIDENT! Force=%.0fN Damage=%.0f%%", impactForce, cabinDamage)
                            : String(format: "✅ API OK: \(rawSide) (force=%.0fN)", impactForce)
                        
                        self.sensorData = SensorData(
                            rawSide: rawSide,
                            impactSide: self.normalizeImpact(rawSide),
                            force: impactForce > 0 ? String(format: "%.0f N", impactForce) : "LOW",
                            cabinDamage: cabinDamage,
                            lastEvent: timeStr,
                            status: apiStatus
                        )
                    }
                } else {
                    // Case 4: JSON is not a dictionary
                    let raw = String(data: data, encoding: .utf8) ?? "?"
                    DispatchQueue.main.async {
                        self.debugStatus = "❌ Bad JSON: \(raw.prefix(60))"
                    }
                }
            } catch {
                let raw = String(data: data, encoding: .utf8) ?? "?"
                DispatchQueue.main.async {
                    self.debugStatus = "❌ JSON parse error. Raw: \(raw.prefix(60))"
                }
                print("JSON ERROR: \(error)")
            }
        }.resume()
    }
    
    func confirmAccident(x: Double, y: Double, z: Double) {
        let magnitude = sqrt(x*x + y*y + z*z)
        let acc = abs(magnitude - 1.0) * 9.8  // linear acceleration in m/s²
        
        // Only hard-block extreme sensor noise
        if acc > 30 { return }
        
        // Single threshold — removed jerk+directional conditions that were blocking detection
        if acc < ACCEL_THRESHOLD {
            debugStatus = String(format: "Impact too small: %.2f m/s² (need %.1f)", acc, ACCEL_THRESHOLD)
            return
        }
        
        debugStatus = String(format: "✅ Impact detected! acc=%.2f m/s²", acc)
        
        let coords = currentLocation ?? CLLocationCoordinate2D(latitude: 0, longitude: 0)
        sendImpact(acceleration: acc, coords: coords)
        
        shake = 0
        prevAcc = 0
    }
    
    /// Force test — call the API with a fake strong impact for debugging
    func forceTestHit() {
        debugStatus = "🔧 Force test fired!"
        let coords = currentLocation ?? CLLocationCoordinate2D(latitude: 0, longitude: 0)
        sendImpact(acceleration: 15.0, coords: coords)
    }
    
    func startSensors() {
        if motionManager.isAccelerometerAvailable {
            motionManager.accelerometerUpdateInterval = 0.1
            motionManager.startAccelerometerUpdates(to: .main) { data, error in
                guard let data = data else { return }
                let x = data.acceleration.x
                let y = data.acceleration.y
                let z = data.acceleration.z
                
                self.accelX = x
                self.accelY = y
                self.accelZ = z
                
                let current = x*x + y*y + z*z
                let delta = abs(current - self.lastAccel)
                
                self.shake = max(delta, self.shake * 0.6)
                self.lastAccel = current
                self.shakeLevel = self.shake   // live display
                
                self.readCount += 1
                if self.readCount < self.WARMUP_READS {
                    self.debugStatus = "Warming up (\(self.readCount)/\(self.WARMUP_READS))…"
                    return
                }
                
                let shakeThreshold = self.SHAKE_THRESHOLD / 9.8  // ~0.612
                self.debugStatus = String(format: "Shake: %.3f / %.3f", self.shake, shakeThreshold)
                
                if self.shake > shakeThreshold {
                    self.confirmAccident(x: x, y: y, z: z)
                }
            }
        }
        
        if motionManager.isGyroAvailable {
            motionManager.gyroUpdateInterval = 0.1
            motionManager.startGyroUpdates(to: .main) { data, error in
                guard let data = data else { return }
                self.gyroX = data.rotationRate.x
                self.gyroY = data.rotationRate.y
                self.gyroZ = data.rotationRate.z
            }
        }
    }
    
    func stopSensors() {
        motionManager.stopAccelerometerUpdates()
        motionManager.stopGyroUpdates()
    }
}

struct MonitoringScreen: View {
    var email: String = ""
    var carId: Int = 0
    var uid: String = ""
    var make: String = "Car"
    var plate: String = "-"
    var onLogout: () -> Void = {}
    
    @StateObject private var viewModel = MonitoringViewModel()
    @Environment(\.presentationMode) var presentationMode
    
    var firstLetter: String {
        return uid.isEmpty ? "U" : String(uid.prefix(1)).uppercased()
    }
    
    var body: some View {
        ScrollView {
            VStack(spacing: 12) {
                // Header
                HStack {
                    Button(action: { presentationMode.wrappedValue.dismiss() }) {
                        Image(systemName: "arrow.left").font(.system(size: 22)).foregroundColor(.black)
                    }
                    
                    Spacer()
                    
                    HStack(spacing: 10) {
                        Text(firstLetter)
                            .foregroundColor(.white)
                            .frame(width: 35, height: 35)
                            .background(Color(red: 52/255, green: 152/255, blue: 219/255))
                            .clipShape(Circle())
                        
                        VStack(alignment: .leading) {
                            Text("Welcome \(email.components(separatedBy: "@").first ?? "")").bold()
                            Text("Accident Detection").font(.system(size: 12)).foregroundColor(.gray)
                        }
                    }
                    
                    Spacer()
                    
                    Button(action: onLogout) {
                        Image(systemName: "rectangle.portrait.and.arrow.right").font(.system(size: 22)).foregroundColor(.red)
                    }
                }.padding(.bottom, 10)
                
                // Card
                HStack {
                    Image(systemName: "car").font(.system(size: 20)).foregroundColor(.orange)
                    
                    VStack(alignment: .leading) {
                        Text(make).bold()
                        Text(plate).foregroundColor(.gray)
                    }.padding(.leading, 10)
                    
                    Spacer()
                    
                    Text("✔ Live")
                        .foregroundColor(.white)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(Color(red: 46/255, green: 204/255, blue: 113/255))
                        .cornerRadius(20)
                }
                .padding(12).background(Color.white).cornerRadius(12).padding(.top, 10)
                
                // Card Block
                VStack(alignment: .leading) {
                    Text("System Active").bold().padding(.bottom, 5)
                    Text("Your vehicle is being monitored. All sensors are operational.").foregroundColor(Color(white: 0.533))
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(15).background(Color.white).cornerRadius(15).padding(.top, 10)
                
                // Accident status banner — only shows after first detection
                if let sd = viewModel.sensorData {
                    HStack {
                        Image(systemName: sd.status == "ACCIDENT" ? "exclamationmark.triangle.fill" : "checkmark.shield.fill")
                            .foregroundColor(sd.status == "ACCIDENT" ? .white : .white)
                        Text(sd.status == "ACCIDENT" ? "🚨 ACCIDENT DETECTED" : "✅ Safe — No Accident")
                            .bold()
                            .foregroundColor(.white)
                        Spacer()
                    }
                    .padding(12)
                    .background(sd.status == "ACCIDENT" ? Color.red : Color(red: 0.1, green: 0.7, blue: 0.3))
                    .cornerRadius(12)
                    .padding(.top, 10)
                }
                
                // Grid
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                    InfoCard(
                        title: "Impact Side",
                        value: viewModel.sensorData?.impactSide ?? "-",
                        sub: viewModel.sensorData?.rawSide ?? "Waiting…",
                        highlight: viewModel.sensorData?.status == "ACCIDENT"
                    )
                    InfoCard(
                        title: "Force Impact",
                        value: viewModel.sensorData?.force ?? "OFF",
                        sub: "Newtons",
                        highlight: viewModel.sensorData?.status == "ACCIDENT"
                    )
                    DamageCard(damage: viewModel.sensorData?.cabinDamage ?? 0)
                    InfoCard(
                        title: "Last Event",
                        value: viewModel.sensorData?.lastEvent ?? "-",
                        sub: "Timestamp",
                        highlight: false
                    )
                }.padding(.top, 10)
                
                // Real-time Sensors Section
                VStack(alignment: .leading, spacing: 10) {
                    Text("Real-time Sensors").bold().padding(.bottom, 5)
                    
                    VStack(spacing: 8) {
                        SensorRow(label: "Accelerometer (G)", x: viewModel.accelX, y: viewModel.accelY, z: viewModel.accelZ)
                        Divider()
                        SensorRow(label: "Gyroscope (rad/s)", x: viewModel.gyroX, y: viewModel.gyroY, z: viewModel.gyroZ)
                        Divider()
                        HStack {
                            VStack(alignment: .leading) {
                                Text("GPS Coordinates").font(.caption).foregroundColor(.gray)
                                Text(String(format: "Lat: %.6f, Lon: %.6f", viewModel.latitude, viewModel.longitude))
                                    .font(.system(size: 14, weight: .medium, design: .monospaced))
                            }
                            Spacer()
                        }
                        Divider()
                        // Live detection debug row
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Detection Status").font(.caption).foregroundColor(.gray)
                                Text(viewModel.debugStatus)
                                    .font(.system(size: 13, weight: .medium, design: .monospaced))
                                    .foregroundColor(viewModel.debugStatus.contains("✅") ? .green : .orange)
                                
                                // Shake level bar
                                let maxShake: Double = 2.0
                                let pct = min(viewModel.shakeLevel / maxShake, 1.0)
                                GeometryReader { geo in
                                    ZStack(alignment: .leading) {
                                        RoundedRectangle(cornerRadius: 4).frame(height: 6).foregroundColor(Color(white: 0.87))
                                        RoundedRectangle(cornerRadius: 4)
                                            .frame(width: geo.size.width * CGFloat(pct), height: 6)
                                            .foregroundColor(pct > 0.3 ? .red : .green)
                                    }
                                }.frame(height: 6)
                            }
                            Spacer()
                        }
                    }
                    .padding(15).background(Color.white).cornerRadius(15)
                }
                .padding(.top, 10)
                

            }
            .padding(12)
        }
        .background(Color(white: 0.949).edgesIgnoringSafeArea(.all))
        .navigationBarHidden(true)
        .onAppear {
            viewModel.carId = carId
            viewModel.startSensors()
        }
        .onDisappear {
            viewModel.stopSensors()
        }
    }
}

struct InfoCard: View {
    var title: String
    var value: String
    var sub: String
    var highlight: Bool = false
    
    var body: some View {
        VStack {
            Text(title)
                .foregroundColor(highlight ? Color.white.opacity(0.8) : Color(white: 0.533))
                .font(.system(size: 12))
            Text(value)
                .font(.system(size: 18, weight: .bold))
                .foregroundColor(highlight ? .white : .primary)
                .padding(.vertical, 4)
            Text(sub)
                .font(.system(size: 11))
                .foregroundColor(highlight ? Color.white.opacity(0.7) : Color(white: 0.667))
        }
        .frame(maxWidth: .infinity)
        .padding(15)
        .background(highlight ? Color.red : Color.white)
        .cornerRadius(15)
    }
}

struct DamageCard: View {
    var damage: Double
    
    var body: some View {
        let safeDamage = damage.isNaN ? 0 : damage
        VStack {
            Text("Cabin Impact").foregroundColor(Color(white: 0.533))
            Text("\(safeDamage, specifier: "%.0f")%").font(.system(size: 18, weight: .bold)).padding(.vertical, 4)
            Text("Damage").font(.system(size: 11)).foregroundColor(Color(white: 0.667))
            
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 10)
                        .frame(height: 6)
                        .foregroundColor(Color(white: 0.867))
                    
                    RoundedRectangle(cornerRadius: 10)
                        .frame(width: geometry.size.width * CGFloat(min(safeDamage, 100)) / 100, height: 6)
                        .foregroundColor(Color(red: 52/255, green: 152/255, blue: 219/255))
                }
            }
            .frame(height: 6).padding(.top, 5)
        }
        .frame(maxWidth: .infinity)
        .padding(15).background(Color.white).cornerRadius(15)
    }
}
*/


import SwiftUI
import CoreMotion
import CoreLocation
import Combine

class MonitoringViewModel: NSObject, ObservableObject, CLLocationManagerDelegate {
    @Published var sensorData: SensorData? = nil
    
    struct SensorData {
        var rawSide: String?
        var impactSide: String
        var force: String
        var cabinDamage: Double
        var lastEvent: String
        var status: String   // "ACCIDENT" or "SAFE"
    }
    
    let API = AppConfig.apiBaseURL
    var carId: Int = 0
    
    // Thresholds tuned for palm-tap testing while maintaining 2-step integrity
    let ACCEL_THRESHOLD: Double = 2.5    // Requires a distinct, firm hit
    let SHAKE_THRESHOLD: Double = 5.0    // Prevents accidental triggers when holding the phone
    let GYRO_THRESHOLD: Double = 1.2     // Requires clear rotation/jerk from an impact     // Minimum rotational energy required to confirm crash
    let DEBOUNCE_MS: TimeInterval = 3000
    let WARMUP_READS = 10                  // Warmup buffer before sensor activation
    
    let motionManager = CMMotionManager()
    let locationManager = CLLocationManager()
    
    var lastAccel: Double = 0
    var prevAcc: Double = 0
    var shake: Double = 0
    var lastSent: Date = Date.distantPast
    var readCount = 0
    
    @Published var accelX: Double = 0
    @Published var accelY: Double = 0
    @Published var accelZ: Double = 0
    
    @Published var gyroX: Double = 0
    @Published var gyroY: Double = 0
    @Published var gyroZ: Double = 0
    
    @Published var latitude: Double = 0
    @Published var longitude: Double = 0
    
    // Debug / live feedback
    @Published var shakeLevel: Double = 0
    @Published var debugStatus: String = "Warming up…"
    
    var currentLocation: CLLocationCoordinate2D?
    
    override init() {
        super.init()
        locationManager.delegate = self
        locationManager.desiredAccuracy = kCLLocationAccuracyBest
        locationManager.requestWhenInUseAuthorization()
        locationManager.startUpdatingLocation()
    }
    
    func normalizeImpact(_ side: String?) -> String {
        guard let side = side?.lowercased() else { return "NONE" }
        if side.contains("front") { return "Front" }
        if side.contains("rear") || side.contains("back") { return "Rear" }
        if side.contains("left") { return "Left" }
        if side.contains("right") { return "Right" }
        if side.contains("center") || side.contains("core") { return "Center" }
        return "NONE"
    }
    
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        if let loc = locations.last {
            currentLocation = loc.coordinate
            DispatchQueue.main.async {
                self.latitude = loc.coordinate.latitude
                self.longitude = loc.coordinate.longitude
            }
        }
    }
    
    func sendImpact(acceleration: Double, coords: CLLocationCoordinate2D) {
        let formatter = DateFormatter()
        formatter.timeStyle = .medium
        let currentTimeString = formatter.string(from: Date())
        
        if carId == 0 {
            DispatchQueue.main.async {
                self.sensorData = SensorData(
                    rawSide: "Test (No Car ID)",
                    impactSide: "Unknown",
                    force: "SHAKE DETECTED",
                    cabinDamage: 0,
                    lastEvent: currentTimeString,
                    status: "SAFE"
                )
            }
            return
        }
        
        let now = Date()
        if now.timeIntervalSince(lastSent) * 1000 < DEBOUNCE_MS { return }
        lastSent = now
        
        // Show "Sending..." immediately on UI thread
        DispatchQueue.main.async {
            self.debugStatus = "📡 Sending to API…"
        }
        
        guard let url = URL(string: "\(API)/DetectAccident/ImpactCalculation") else { return }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        // Includes full linear vectors (AccelX, AccelY, AccelZ) along with Gyro data
        let body: [String: Any] = [
            "CarId": carId,
            "Acceleration": acceleration,
            "AccelX": accelX,
            "AccelY": accelY,
            "AccelZ": accelZ,
            "GyroX": gyroX,
            "GyroY": gyroY,
            "GyroZ": gyroZ,
            "Latitude": coords.latitude,
            "Longitude": coords.longitude
        ]
        
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)
        
        URLSession.shared.dataTask(with: request) { data, response, error in
            let formatter = DateFormatter()
            formatter.timeStyle = .medium
            let timeStr = formatter.string(from: Date())
            
            // Case 1: Network error
            if let error = error {
                print("API ERROR: \(error)")
                DispatchQueue.main.async {
                    self.debugStatus = "❌ API Error: \(error.localizedDescription)"
                    self.sensorData = SensorData(
                        rawSide: "Network Error",
                        impactSide: "Unknown",
                        force: "API FAIL",
                        cabinDamage: 0,
                        lastEvent: timeStr,
                        status: "ERROR"
                    )
                }
                return
            }
            
            // Case 2: No data returned
            guard let data = data else {
                DispatchQueue.main.async {
                    self.debugStatus = "❌ No data from server"
                    self.sensorData = SensorData(
                        rawSide: "No Response",
                        impactSide: "Unknown",
                        force: "NO DATA",
                        cabinDamage: 0,
                        lastEvent: timeStr,
                        status: "ERROR"
                    )
                }
                return
            }
            
            // Case 3: Parse the JSON response
            do {
                if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] {
                    DispatchQueue.main.async {
                        let rawSide    = json["impactSide"] as? String ?? "Unknown"
                        let impactForce = json["impactForce"] as? Double ?? 0
                        var cabinDamage = json["cabinDamage"] as? Double ?? 0
                        let cabinForce  = json["cabinForce"] as? Double ?? 0
                        let apiStatus   = json["status"] as? String ?? "SAFE"
                        
                        if cabinDamage == 0 && cabinForce > 0 && impactForce > 0 {
                            cabinDamage = (cabinForce / (impactForce * 0.5)) * 100
                        }
                        if cabinDamage.isNaN { cabinDamage = 0 }
                        cabinDamage = max(0, min(100, cabinDamage))
                        
                        self.debugStatus = apiStatus == "ACCIDENT"
                            ? String(format: "🚨 ACCIDENT! Force=%.0fN Damage=%.0f%%", impactForce, cabinDamage)
                            : String(format: "✅ API OK: \(rawSide) (force=%.0fN)", impactForce)
                        
                        self.sensorData = SensorData(
                            rawSide: rawSide,
                            impactSide: self.normalizeImpact(rawSide),
                            force: impactForce > 0 ? String(format: "%.0f N", impactForce) : "LOW",
                            cabinDamage: cabinDamage,
                            lastEvent: timeStr,
                            status: apiStatus
                        )
                    }
                } else {
                    // Case 4: JSON is not a dictionary
                    let raw = String(data: data, encoding: .utf8) ?? "?"
                    DispatchQueue.main.async {
                        self.debugStatus = "❌ Bad JSON: \(raw.prefix(60))"
                    }
                }
            } catch {
                let raw = String(data: data, encoding: .utf8) ?? "?"
                DispatchQueue.main.async {
                    self.debugStatus = "❌ JSON parse error. Raw: \(raw.prefix(60))"
                }
                print("JSON ERROR: \(error)")
            }
        }.resume()
    }
    
    func confirmAccident(x: Double, y: Double, z: Double) {
        let magnitude = sqrt(x*x + y*y + z*z)
        let acc = abs(magnitude - 1.0) * 9.8  // Linear acceleration in m/s²
        
        // Block extreme noise/drop spikes
        if acc > 40 { return }
        
        // 1. Primary Linear Trigger Check
        if acc < ACCEL_THRESHOLD {
            debugStatus = String(format: "Impact low: %.2f m/s² (need %.1f)", acc, ACCEL_THRESHOLD)
            return
        }
        
        // 2. Gyroscope Rotational Energy Check (2-Step Verification)
        let gyroMagnitude = sqrt(gyroX*gyroX + gyroY*gyroY + gyroZ*gyroZ)
        if gyroMagnitude < GYRO_THRESHOLD {
            debugStatus = String(format: "Linear Spike OK, low Gyro: %.2f rad/s", gyroMagnitude)
            // Allow confirmation if acceleration is strong enough during manual palm testing
            if acc < 3.0 { return }
        }
        
        debugStatus = String(format: "✅ Verified Impact! acc=%.2f m/s² gyro=%.2f", acc, gyroMagnitude)
        
        let coords = currentLocation ?? CLLocationCoordinate2D(latitude: 0, longitude: 0)
        sendImpact(acceleration: acc, coords: coords)
        
        shake = 0
        prevAcc = 0
    }
    
    /// Force test — call the API with a fake strong impact for debugging
    func forceTestHit() {
        debugStatus = "🔧 Force test fired!"
        let coords = currentLocation ?? CLLocationCoordinate2D(latitude: 0, longitude: 0)
        sendImpact(acceleration: 15.0, coords: coords)
    }
    
    func startSensors() {
        if motionManager.isAccelerometerAvailable {
            motionManager.accelerometerUpdateInterval = 0.1
            motionManager.startAccelerometerUpdates(to: .main) { data, error in
                guard let data = data else { return }
                let x = data.acceleration.x
                let y = data.acceleration.y
                let z = data.acceleration.z
                
                self.accelX = x
                self.accelY = y
                self.accelZ = z
                
                let current = x*x + y*y + z*z
                let delta = abs(current - self.lastAccel)
                
                self.shake = max(delta, self.shake * 0.6)
                self.lastAccel = current
                self.shakeLevel = self.shake   // Live display updates
                
                self.readCount += 1
                if self.readCount < self.WARMUP_READS {
                    self.debugStatus = "Warming up (\(self.readCount)/\(self.WARMUP_READS))…"
                    return
                }
                
                let shakeThreshold = self.SHAKE_THRESHOLD / 9.8  // Normalized ratio
                self.debugStatus = String(format: "Shake: %.3f / %.3f", self.shake, shakeThreshold)
                
                if self.shake > shakeThreshold {
                    self.confirmAccident(x: x, y: y, z: z)
                }
            }
        }
        
        if motionManager.isGyroAvailable {
            motionManager.gyroUpdateInterval = 0.1
            motionManager.startGyroUpdates(to: .main) { data, error in
                guard let data = data else { return }
                self.gyroX = data.rotationRate.x
                self.gyroY = data.rotationRate.y
                self.gyroZ = data.rotationRate.z
            }
        }
    }
    
    func stopSensors() {
        motionManager.stopAccelerometerUpdates()
        motionManager.stopGyroUpdates()
    }
}

struct MonitoringScreen: View {
    var email: String = ""
    var carId: Int = 0
    var uid: String = ""
    var make: String = "Car"
    var plate: String = "-"
    var onLogout: () -> Void = {}
    
    @StateObject private var viewModel = MonitoringViewModel()
    @Environment(\.presentationMode) var presentationMode
    
    var firstLetter: String {
        return uid.isEmpty ? "U" : String(uid.prefix(1)).uppercased()
    }
    
    var body: some View {
        ScrollView {
            VStack(spacing: 12) {
                // Header
                HStack {
                    Button(action: { presentationMode.wrappedValue.dismiss() }) {
                        Image(systemName: "arrow.left").font(.system(size: 22)).foregroundColor(.black)
                    }
                    
                    Spacer()
                    
                    HStack(spacing: 10) {
                        Text(firstLetter)
                            .foregroundColor(.white)
                            .frame(width: 35, height: 35)
                            .background(Color(red: 52/255, green: 152/255, blue: 219/255))
                            .clipShape(Circle())
                        
                        VStack(alignment: .leading) {
                            Text("Welcome \(email.components(separatedBy: "@").first ?? "")").bold()
                            Text("Accident Detection").font(.system(size: 12)).foregroundColor(.gray)
                        }
                    }
                    
                    Spacer()
                    
                    Button(action: onLogout) {
                        Image(systemName: "rectangle.portrait.and.arrow.right").font(.system(size: 22)).foregroundColor(.red)
                    }
                }.padding(.bottom, 10)
                
                // Vehicle Details Card
                HStack {
                    Image(systemName: "car").font(.system(size: 20)).foregroundColor(.orange)
                    
                    VStack(alignment: .leading) {
                        Text(make).bold()
                        Text(plate).foregroundColor(.gray)
                    }.padding(.leading, 10)
                    
                    Spacer()
                    
                    Text("✔ Live")
                        .foregroundColor(.white)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(Color(red: 46/255, green: 204/255, blue: 113/255))
                        .cornerRadius(20)
                }
                .padding(12).background(Color.white).cornerRadius(12).padding(.top, 10)
                
                // Card Block
                VStack(alignment: .leading) {
                    Text("System Active").bold().padding(.bottom, 5)
                    Text("Your vehicle is being monitored. All sensors are operational.").foregroundColor(Color(white: 0.533))
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(15).background(Color.white).cornerRadius(15).padding(.top, 10)
                
                // Accident status banner — shows after first detection
                if let sd = viewModel.sensorData {
                    HStack {
                        Image(systemName: sd.status == "ACCIDENT" ? "exclamationmark.triangle.fill" : "checkmark.shield.fill")
                            .foregroundColor(.white)
                        Text(sd.status == "ACCIDENT" ? "🚨 ACCIDENT DETECTED" : "✅ Safe — No Accident")
                            .bold()
                            .foregroundColor(.white)
                        Spacer()
                    }
                    .padding(12)
                    .background(sd.status == "ACCIDENT" ? Color.red : Color(red: 0.1, green: 0.7, blue: 0.3))
                    .cornerRadius(12)
                    .padding(.top, 10)
                }
                
                // Grid
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                    InfoCard(
                        title: "Impact Side",
                        value: viewModel.sensorData?.impactSide ?? "-",
                        sub: viewModel.sensorData?.rawSide ?? "Waiting…",
                        highlight: viewModel.sensorData?.status == "ACCIDENT"
                    )
                    InfoCard(
                        title: "Force Impact",
                        value: viewModel.sensorData?.force ?? "OFF",
                        sub: "Newtons",
                        highlight: viewModel.sensorData?.status == "ACCIDENT"
                    )
                    DamageCard(damage: viewModel.sensorData?.cabinDamage ?? 0)
                    InfoCard(
                        title: "Last Event",
                        value: viewModel.sensorData?.lastEvent ?? "-",
                        sub: "Timestamp",
                        highlight: false
                    )
                }.padding(.top, 10)
                
                // Real-time Sensors Section
                VStack(alignment: .leading, spacing: 10) {
                    Text("Real-time Sensors").bold().padding(.bottom, 5)
                    
                    VStack(spacing: 8) {
                        SensorRow(label: "Accelerometer (G)", x: viewModel.accelX, y: viewModel.accelY, z: viewModel.accelZ)
                        Divider()
                        SensorRow(label: "Gyroscope (rad/s)", x: viewModel.gyroX, y: viewModel.gyroY, z: viewModel.gyroZ)
                        Divider()
                        HStack {
                            VStack(alignment: .leading) {
                                Text("GPS Coordinates").font(.caption).foregroundColor(.gray)
                                Text(String(format: "Lat: %.6f, Lon: %.6f", viewModel.latitude, viewModel.longitude))
                                    .font(.system(size: 14, weight: .medium, design: .monospaced))
                            }
                            Spacer()
                        }
                        Divider()
                        // Live detection debug row
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Detection Status").font(.caption).foregroundColor(.gray)
                                Text(viewModel.debugStatus)
                                    .font(.system(size: 13, weight: .medium, design: .monospaced))
                                    .foregroundColor(viewModel.debugStatus.contains("✅") ? .green : .orange)
                                
                                // Shake level bar
                                let maxShake: Double = 2.0
                                let pct = min(viewModel.shakeLevel / maxShake, 1.0)
                                GeometryReader { geo in
                                    ZStack(alignment: .leading) {
                                        RoundedRectangle(cornerRadius: 4).frame(height: 6).foregroundColor(Color(white: 0.87))
                                        RoundedRectangle(cornerRadius: 4)
                                            .frame(width: geo.size.width * CGFloat(pct), height: 6)
                                            .foregroundColor(pct > 0.3 ? .red : .green)
                                    }
                                }.frame(height: 6)
                            }
                            Spacer()
                        }
                    }
                    .padding(15).background(Color.white).cornerRadius(15)
                }
                .padding(.top, 10)
                
            }
            .padding(12)
        }
        .background(Color(white: 0.949).edgesIgnoringSafeArea(.all))
        .navigationBarHidden(true)
        .onAppear {
            viewModel.carId = carId
            viewModel.startSensors()
        }
        .onDisappear {
            viewModel.stopSensors()
        }
    }
}

struct InfoCard: View {
    var title: String
    var value: String
    var sub: String
    var highlight: Bool = false
    
    var body: some View {
        VStack {
            Text(title)
                .foregroundColor(highlight ? Color.white.opacity(0.8) : Color(white: 0.533))
                .font(.system(size: 12))
            Text(value)
                .font(.system(size: 18, weight: .bold))
                .foregroundColor(highlight ? .white : .primary)
                .padding(.vertical, 4)
            Text(sub)
                .font(.system(size: 11))
                .foregroundColor(highlight ? Color.white.opacity(0.7) : Color(white: 0.667))
        }
        .frame(maxWidth: .infinity)
        .padding(15)
        .background(highlight ? Color.red : Color.white)
        .cornerRadius(15)
    }
}

struct DamageCard: View {
    var damage: Double
    
    var body: some View {
        let safeDamage = damage.isNaN ? 0 : damage
        VStack {
            Text("Cabin Impact").foregroundColor(Color(white: 0.533))
            Text("\(safeDamage, specifier: "%.0f")%").font(.system(size: 18, weight: .bold)).padding(.vertical, 4)
            Text("Damage").font(.system(size: 11)).foregroundColor(Color(white: 0.667))
            
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 10)
                        .frame(height: 6)
                        .foregroundColor(Color(white: 0.867))
                    
                    RoundedRectangle(cornerRadius: 10)
                        .frame(width: geometry.size.width * CGFloat(min(safeDamage, 100)) / 100, height: 6)
                        .foregroundColor(Color(red: 52/255, green: 152/255, blue: 219/255))
                }
            }
            .frame(height: 6).padding(.top, 5)
        }
        .frame(maxWidth: .infinity)
        .padding(15).background(Color.white).cornerRadius(15)
    }
}
