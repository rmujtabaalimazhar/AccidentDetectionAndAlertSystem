
import SwiftUI
import CoreMotion
import CoreLocation
import Combine

class MonitoringViewModel: NSObject, ObservableObject, CLLocationManagerDelegate {
    @Published var sensorData: SensorData? = nil
    
    struct SensorData {
        var accidentType: String  // "Rollover", "Frontal Collision", "Side Impact", "Rear Collision"
        var rawSide: String?
        var impactSide: String
        var force: String
        var cabinDamage: Double
        var severity: String? = nil
        var aisLevel: String? = nil
        var passengerSeverity: String? = nil
        var passengerInjury: String? = nil
        var driverSeverity: String? = nil
        var driverInjury: String? = nil
        var occupantSummary: String? = nil
        var steeringSide: String? = nil
        var lastEvent: String
        var status: String   // "ACCIDENT" or "SAFE"
    }
    
    let API = AppConfig.apiBaseURL
    var carId: Int = 0
    var steeringSide: String = "Right-Hand"
    
    // 1. Calibrated Linear Acceleration Threshold (Gravity isolated: 0 m/s² rest baseline)
    // 2.0 G (19.6 m/s²) catches lightweight toy car / RC collisions, but ignores finger taps
    let IMPACT_THRESHOLD_ACC: Double = 19.6    // ~2.0 G (19.6 m/s² pure linear acceleration)
    let DEBOUNCE_MS: TimeInterval = 800       // 0.8s debounce prevents double-triggering
    let MIN_SUSTAINED_FRAMES: Int = 3         // Requires force to stay high for >= 3 consecutive frames (~40-60ms)
    let MIN_DURATION_MS: Double = 35.0        // Minimum sustained impact duration in ms (filters taps <35ms)
    let WARMUP_READS = 10                     // Warmup buffer before sensor activation
    
    // Time check tracking for sustained impact window
    private var highForceStartTime: Date? = nil
    private var highForceFrameCount: Int = 0
    
    let motionManager = CMMotionManager()
    let locationManager = CLLocationManager()
    
    var lastAccel: Double = 1.0
    var prevAcc: Double = 0
    var shake: Double = 0
    var lastSent: Date = Date.distantPast
    var readCount = 0
    
    // Gravity isolation baseline
    var gravityX: Double = 0.0
    var gravityY: Double = -0.7
    var gravityZ: Double = -0.7
    
    @Published var accelX: Double = 0
    @Published var accelY: Double = 0
    @Published var accelZ: Double = 0
    
    @Published var gyroX: Double = 0
    @Published var gyroY: Double = 0
    @Published var gyroZ: Double = 0
    
    @Published var latitude: Double = 0
    @Published var longitude: Double = 0
    
    // Live Location Broadcast for active accident
    @Published var activeAccidentId: Int? = nil
    @Published var isLiveTrackingActive: Bool = false
    private var liveLocationTimer: Timer? = nil
    private var lastBroadcastedLocation: CLLocationCoordinate2D? = nil
    private var lastBroadcastTime: Date = Date.distantPast
    
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
        if side.contains("rollover") { return "Rollover" }
        if side.contains("front") && side.contains("left") { return "Front-Left" }
        if side.contains("front") && side.contains("right") { return "Front-Right" }
        if (side.contains("rear") || side.contains("back")) && side.contains("left") { return "Rear-Left" }
        if (side.contains("rear") || side.contains("back")) && side.contains("right") { return "Rear-Right" }
        if side.contains("front") { return "Front" }
        if side.contains("rear") || side.contains("back") { return "Rear" }
        if side.contains("left") { return "Left" }
        if side.contains("right") { return "Right" }
        return "NONE"
    }
    
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        if let loc = locations.last {
            currentLocation = loc.coordinate
            DispatchQueue.main.async {
                self.latitude = loc.coordinate.latitude
                self.longitude = loc.coordinate.longitude
            }
            if isLiveTrackingActive {
                broadcastCurrentLocationIfNeeded(newLocation: loc)
            }
        }
    }
    
    // ================= LIVE LOCATION BROADCAST =================
    func startLiveLocationBroadcast(for accidentId: Int) {
        self.activeAccidentId = accidentId
        self.isLiveTrackingActive = true
        
        // Immediate broadcast if coordinates available
        if let coords = currentLocation {
            sendLiveLocationUpdate(accidentId: accidentId, coords: coords)
        }
        
        // Poll GPS broadcast every 3 seconds
        liveLocationTimer?.invalidate()
        liveLocationTimer = Timer.scheduledTimer(withTimeInterval: 3.0, repeats: true) { [weak self] _ in
            self?.broadcastCurrentLocationIfNeeded()
        }
    }
    
    func broadcastCurrentLocationIfNeeded(newLocation: CLLocation? = nil) {
        guard let accidentId = activeAccidentId, isLiveTrackingActive else { return }
        guard let coord = currentLocation else { return }
        
        let now = Date()
        guard now.timeIntervalSince(lastBroadcastTime) >= 2.0 else { return }
        
        // Avoid sending duplicate identical coordinates unless 15s elapsed (heartbeat)
        if let last = lastBroadcastedLocation {
            let lastLoc = CLLocation(latitude: last.latitude, longitude: last.longitude)
            let currLoc = newLocation ?? CLLocation(latitude: coord.latitude, longitude: coord.longitude)
            let dist = currLoc.distance(from: lastLoc)
            if dist < 1.5 && now.timeIntervalSince(lastBroadcastTime) < 15.0 {
                return
            }
        }
        
        sendLiveLocationUpdate(accidentId: accidentId, coords: coord)
    }
    
    func sendLiveLocationUpdate(accidentId: Int, coords: CLLocationCoordinate2D) {
        guard let url = URL(string: "\(API)/DetectAccident/UpdateLiveLocation") else { return }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let body: [String: Any] = [
            "accidentId": accidentId,
            "latitude": coords.latitude,
            "longitude": coords.longitude
        ]
        
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)
        
        URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
            guard let self = self else { return }
            if let error = error {
                print("❌ Live location update failed: \(error.localizedDescription)")
                return
            }
            DispatchQueue.main.async {
                self.lastBroadcastedLocation = coords
                self.lastBroadcastTime = Date()
                print("📍 Live location broadcasted for Accident #\(accidentId): \(coords.latitude), \(coords.longitude)")
            }
        }.resume()
    }
    
    func stopLiveLocationBroadcast() {
        liveLocationTimer?.invalidate()
        liveLocationTimer = nil
        isLiveTrackingActive = false
        activeAccidentId = nil
    }
    
    func determineExactSide(dynX: Double, dynY: Double, dynZ: Double, gravZ: Double, gyroMag: Double) -> String {
        // 1. Rollover Check:
        // A vehicle rollover requires either:
        // a) Violent rotational roll/tumble (gyroMag > 5.5 rad/s)
        // b) Sustained inverted orientation onto vehicle roof (gravZ > 0.70 face-down with gyroMag > 2.0 rad/s)
        // NOTE: In iOS CoreMotion, normal face-up posture has gravZ < 0 (approx -0.7 to -1.0).
        // Only when the device is completely inverted face-down towards Earth does gravZ become positive (+0.7 to +1.0).
        if gyroMag > 5.5 || (gravZ > 0.70 && gyroMag > 2.0) {
            return "Rollover"
        }
        
        let absX = abs(dynX)
        let absY = abs(dynY)
        
        if absX < 0.10 && absY < 0.10 {
            return "Front" // Fallback default
        }
        
        let ratio = absX / max(absY, 0.0001)
        // Diagonal strike (energy balanced between axes)
        if absX >= 0.18 && absY >= 0.18 && ratio >= 0.45 && ratio <= 2.2 {
            let lon = dynY >= 0 ? "Front" : "Rear"
            let lat = dynX >= 0 ? "Right" : "Left"
            return "\(lon)-\(lat)"
        }
        
        // Orthogonal strike
        if absY >= absX {
            return dynY >= 0 ? "Front" : "Rear"
        } else {
            return dynX >= 0 ? "Right" : "Left"
        }
    }
    
    func sendImpact(acceleration: Double, coords: CLLocationCoordinate2D, detectedSide: String = "Front", dynX: Double = 0, dynY: Double = 0, dynZ: Double = 0, durationMs: Double = 40.0) {
        let formatter = DateFormatter()
        formatter.timeStyle = .medium
        let currentTimeString = formatter.string(from: Date())
        
        if carId == 0 {
            DispatchQueue.main.async {
                self.sensorData = SensorData(
                    accidentType: "Test (No Car ID)",
                    rawSide: detectedSide,
                    impactSide: detectedSide,
                    force: "SHAKE DETECTED",
                    cabinDamage: 0,
                    severity: "Minor (AIS 1)",
                    aisLevel: "AIS 1",
                    passengerSeverity: "Minor (AIS 1)",
                    passengerInjury: "Minor: Mild neck strain/whiplash, soft tissue pain.",
                    driverSeverity: "Minor (AIS 1)",
                    driverInjury: "Minor: Mild neck strain/whiplash, superficial bruising.",
                    occupantSummary: "Test simulation without Car ID.",
                    steeringSide: self.steeringSide,
                    lastEvent: currentTimeString,
                    status: "SAFE"
                )
            }
            return
        }
        
        let now = Date()
        if now.timeIntervalSince(lastSent) * 1000 < DEBOUNCE_MS { return }
        lastSent = now
        
        DispatchQueue.main.async {
            self.debugStatus = "📡 Sending to API…"
        }
        
        guard let url = URL(string: "\(API)/DetectAccident/ImpactCalculation") else { return }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let gForce = acceleration / 9.81
        let clientSeverity = gForce > 7.0 ? "High" : (gForce > 4.0 ? "Medium" : "Low")
        let isoFormatter = ISO8601DateFormatter()
        let timeIso = isoFormatter.string(from: now)
        
        let body: [String: Any] = [
            "CarId": carId,
            "Acceleration": acceleration,
            "GForce": gForce,
            "ImpactDurationMs": durationMs,
            "ImpactSide": detectedSide,
            "SteeringSide": steeringSide,
            "AccelX": dynX,
            "AccelY": dynY,
            "AccelZ": dynZ,
            "GyroX": gyroX,
            "GyroY": gyroY,
            "GyroZ": gyroZ,
            "Latitude": coords.latitude,
            "Longitude": coords.longitude,
            "Severity": clientSeverity,
            "Time": timeIso
        ]
        
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)
        
        URLSession.shared.dataTask(with: request) { data, response, error in
            let formatter = DateFormatter()
            formatter.timeStyle = .medium
            let timeStr = formatter.string(from: Date())
            
            // Handle network errors
            if let error = error {
                print("API ERROR: \(error)")
                DispatchQueue.main.async {
                    self.debugStatus = "❌ API Error: \(error.localizedDescription)"
                }
                return
            }
            
            guard let data = data else {
                DispatchQueue.main.async {
                    self.debugStatus = "❌ No data returned from server"
                }
                return
            }
            
            do {
                if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] {
                    DispatchQueue.main.async {
                        let accidentType = json["accidentType"] as? String ?? "Impact"
                        let rawSide     = json["impactSide"] as? String ?? detectedSide
                        let impactForce = json["impactForce"] as? Double ?? 0
                        var cabinDamage = json["cabinDamage"] as? Double ?? 0
                        let cabinForce  = json["cabinForce"] as? Double ?? 0
                        let apiStatus   = json["status"] as? String ?? "SAFE"
                        let serverTime  = json["time"] as? String ?? timeStr

                        let aisLevel = json["aisLevel"] as? String ?? "AIS 0"
                        let passengerSeverity = json["passengerSeverity"] as? String ?? (json["severity"] as? String ?? clientSeverity)
                        let passengerInjury = json["passengerInjury"] as? String ?? "No significant injuries detected."
                        let driverSeverity = json["driverSeverity"] as? String ?? passengerSeverity
                        let driverInjury = json["driverInjury"] as? String ?? "Normal driving safe baseline."
                        let occupantSummary = json["occupantSummary"] as? String ?? ""
                        let steeringSideRet = json["steeringSide"] as? String ?? self.steeringSide

                        if cabinDamage == 0 && cabinForce > 0 && impactForce > 0 {
                            cabinDamage = (cabinForce / (impactForce * 0.5)) * 100
                        }
                        if cabinDamage.isNaN { cabinDamage = 0 }
                        cabinDamage = max(0, min(100, cabinDamage))

                        self.debugStatus = apiStatus == "ACCIDENT"
                            ? String(format: "🚨 %@ [%@]! Force=%.0fN Damage=%.0f%%", accidentType.uppercased(), passengerSeverity.uppercased(), impactForce, cabinDamage)
                            : String(format: "✅ API OK: \(rawSide) (force=%.0fN)", impactForce)

                        self.sensorData = SensorData(
                            accidentType: accidentType,
                            rawSide: rawSide,
                            impactSide: self.normalizeImpact(rawSide),
                            force: impactForce > 0 ? String(format: "%.0f N", impactForce) : "LOW",
                            cabinDamage: cabinDamage,
                            severity: passengerSeverity,
                            aisLevel: aisLevel,
                            passengerSeverity: passengerSeverity,
                            passengerInjury: passengerInjury,
                            driverSeverity: driverSeverity,
                            driverInjury: driverInjury,
                            occupantSummary: occupantSummary,
                            steeringSide: steeringSideRet,
                            lastEvent: serverTime,
                            status: apiStatus
                        )
                        
                        // Start continuous live location broadcasting if accident detected
                        if apiStatus == "ACCIDENT", let accId = json["accidentId"] as? Int {
                            self.startLiveLocationBroadcast(for: accId)
                        }
                    }
                }
            } catch {
                print("JSON parse error: \(error)")
                DispatchQueue.main.async {
                    self.debugStatus = "❌ JSON parse error"
                }
            }
        }.resume()
    }
    
    func confirmAccident(dynX: Double, dynY: Double, dynZ: Double, gravZ: Double, gyroX: Double, gyroY: Double, gyroZ: Double, acc: Double, durationMs: Double = 40.0) {
        let now = Date()
        if now.timeIntervalSince(lastSent) * 1000 < DEBOUNCE_MS { return }
        
        // Filter out extreme sensor resets (> 150 m/s²)
        if acc > 150 { return }
        
        let gyroMagnitude = sqrt(gyroX*gyroX + gyroY*gyroY + gyroZ*gyroZ)
        let detectedSide = determineExactSide(dynX: dynX, dynY: dynY, dynZ: dynZ, gravZ: gravZ, gyroMag: gyroMagnitude)
        
        debugStatus = String(format: "🚨 Verified %@! Acc=%.1f m/s² (%.0fms)", detectedSide, acc, durationMs)
        
        let coords = currentLocation ?? CLLocationCoordinate2D(latitude: 0, longitude: 0)
        sendImpact(acceleration: acc, coords: coords, detectedSide: detectedSide, dynX: dynX, dynY: dynY, dynZ: dynZ, durationMs: durationMs)
    }
    
    func startSensors() {
        self.lastAccel = 1.0
        self.prevAcc = 0
        self.shake = 0
        self.readCount = 0
        self.highForceStartTime = nil
        self.highForceFrameCount = 0
        self.debugStatus = "Calibrating sensors…"
        
        if motionManager.isDeviceMotionAvailable {
            motionManager.deviceMotionUpdateInterval = 0.02 // 50Hz update (20ms per frame)
            motionManager.startDeviceMotionUpdates(to: .main) { [weak self] motion, error in
                guard let self = self, let motion = motion else { return }
                
                // 1. Pure dynamic linear acceleration (gravity isolated to zero baseline by Apple sensor fusion)
                let uX = motion.userAcceleration.x
                let uY = motion.userAcceleration.y
                let uZ = motion.userAcceleration.z
                
                // Earth gravity unit vector
                let gZ = motion.gravity.z
                
                // Angular rotation rate (rad/s)
                let rX = motion.rotationRate.x
                let rY = motion.rotationRate.y
                let rZ = motion.rotationRate.z
                
                self.accelX = uX
                self.accelY = uY
                self.accelZ = uZ
                
                self.gyroX = rX
                self.gyroY = rY
                self.gyroZ = rZ
                
                // Dynamic linear shock magnitude (in G and m/s²)
                let dynMagnitude = sqrt(uX*uX + uY*uY + uZ*uZ)
                let linearAcc = dynMagnitude * 9.81
                
                self.shakeLevel = dynMagnitude
                
                self.readCount += 1
                if self.readCount < self.WARMUP_READS {
                    self.debugStatus = "Calibrating linear sensors (\(self.readCount)/\(self.WARMUP_READS))…"
                    return
                }
                
                // 2. Time check / sustained impact window filter
                if linearAcc >= self.IMPACT_THRESHOLD_ACC {
                    if self.highForceStartTime == nil {
                        self.highForceStartTime = Date()
                        self.highForceFrameCount = 1
                        self.debugStatus = String(format: "Spike detected (%.1f m/s²)... checking duration", linearAcc)
                    } else {
                        self.highForceFrameCount += 1
                        let elapsedMs = Date().timeIntervalSince(self.highForceStartTime!) * 1000.0
                        
                        // Sustained impact window reached (>= 3 frames or >= 35ms)
                        if self.highForceFrameCount >= self.MIN_SUSTAINED_FRAMES || elapsedMs >= self.MIN_DURATION_MS {
                            self.confirmAccident(
                                dynX: uX,
                                dynY: uY,
                                dynZ: uZ,
                                gravZ: gZ,
                                gyroX: rX,
                                gyroY: rY,
                                gyroZ: rZ,
                                acc: linearAcc,
                                durationMs: max(elapsedMs, self.MIN_DURATION_MS)
                            )
                            // Reset tracking after triggering
                            self.highForceStartTime = nil
                            self.highForceFrameCount = 0
                        }
                    }
                } else {
                    // Force dropped below threshold before duration check -> Discard finger tap!
                    if self.highForceStartTime != nil {
                        self.highForceStartTime = nil
                        self.highForceFrameCount = 0
                    }
                    
                    let now = Date()
                    if now.timeIntervalSince(self.lastSent) * 1000 > self.DEBOUNCE_MS {
                        self.debugStatus = String(format: "Monitoring: Linear Acc=%.2f m/s² (%.2f G)", linearAcc, dynMagnitude)
                    }
                }
            }
        } else if motionManager.isAccelerometerAvailable {
            // Fallback for hardware without device motion: isolate gravity with high-pass filter
            motionManager.accelerometerUpdateInterval = 0.02
            motionManager.startAccelerometerUpdates(to: .main) { [weak self] data, error in
                guard let self = self, let data = data else { return }
                let x = data.acceleration.x
                let y = data.acceleration.y
                let z = data.acceleration.z
                
                let alpha = 0.90
                self.gravityX = alpha * self.gravityX + (1.0 - alpha) * x
                self.gravityY = alpha * self.gravityY + (1.0 - alpha) * y
                self.gravityZ = alpha * self.gravityZ + (1.0 - alpha) * z
                
                // Pure linear acceleration
                let dynX = x - self.gravityX
                let dynY = y - self.gravityY
                let dynZ = z - self.gravityZ
                
                self.accelX = dynX
                self.accelY = dynY
                self.accelZ = dynZ
                
                let dynMagnitude = sqrt(dynX*dynX + dynY*dynY + dynZ*dynZ)
                let linearAcc = dynMagnitude * 9.81
                self.shakeLevel = dynMagnitude
                
                self.readCount += 1
                if self.readCount < self.WARMUP_READS { return }
                
                if linearAcc >= self.IMPACT_THRESHOLD_ACC {
                    if self.highForceStartTime == nil {
                        self.highForceStartTime = Date()
                        self.highForceFrameCount = 1
                    } else {
                        self.highForceFrameCount += 1
                        let elapsedMs = Date().timeIntervalSince(self.highForceStartTime!) * 1000.0
                        if self.highForceFrameCount >= self.MIN_SUSTAINED_FRAMES || elapsedMs >= self.MIN_DURATION_MS {
                            self.confirmAccident(
                                dynX: dynX,
                                dynY: dynY,
                                dynZ: dynZ,
                                gravZ: self.gravityZ,
                                gyroX: self.gyroX,
                                gyroY: self.gyroY,
                                gyroZ: self.gyroZ,
                                acc: linearAcc,
                                durationMs: max(elapsedMs, self.MIN_DURATION_MS)
                            )
                            self.highForceStartTime = nil
                            self.highForceFrameCount = 0
                        }
                    }
                } else {
                    if self.highForceStartTime != nil {
                        self.highForceStartTime = nil
                        self.highForceFrameCount = 0
                    }
                }
            }
            
            if motionManager.isGyroAvailable {
                motionManager.gyroUpdateInterval = 0.02
                motionManager.startGyroUpdates(to: .main) { [weak self] data, error in
                    guard let self = self, let data = data else { return }
                    self.gyroX = data.rotationRate.x
                    self.gyroY = data.rotationRate.y
                    self.gyroZ = data.rotationRate.z
                }
            }
        }
    }
    
    func stopSensors() {
        stopLiveLocationBroadcast()
        if motionManager.isDeviceMotionActive {
            motionManager.stopDeviceMotionUpdates()
        }
        if motionManager.isAccelerometerActive {
            motionManager.stopAccelerometerUpdates()
        }
        if motionManager.isGyroActive {
            motionManager.stopGyroUpdates()
        }
    }
}

struct MonitoringScreen: View {
    var email: String = ""
    var carId: Int = 0
    var uid: String = ""
    var make: String = "Car"
    var plate: String = "-"
    var categoryId: Int = 1
    var steeringSide: String = "Right-Hand"
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
                }.padding(.bottom, 6)
                
                // Selected Car Picture & Affected Impact Area Highlight (Frontend Function)
                makeCarImpactVisualizer(
                    make: make,
                    plate: plate,
                    categoryId: categoryId,
                    isAccident: viewModel.sensorData?.status == "ACCIDENT",
                    impactSide: viewModel.sensorData?.impactSide ?? (viewModel.sensorData?.rawSide ?? "-"),
                    cabinDamage: viewModel.sensorData?.cabinDamage ?? 0
                )
                .padding(.top, 4)
                
                // Accident status banner — shows after first detection
                if let sd = viewModel.sensorData {
                    HStack(spacing: 12) {
                        Image(systemName: sd.status == "ACCIDENT" ? "exclamationmark.triangle.fill" : "checkmark.shield.fill")
                            .font(.system(size: 24))
                            .foregroundColor(.white)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(sd.status == "ACCIDENT" ? "🚨 \(sd.accidentType.uppercased()) DETECTED" : "✅ Safe — No Accident")
                                .bold()
                                .foregroundColor(.white)
                            if sd.status == "ACCIDENT" {
                                HStack(spacing: 8) {
                                    if let sev = sd.passengerSeverity ?? sd.severity {
                                        Text("Severity: \(sev)")
                                            .font(.system(size: 12, weight: .bold))
                                            .padding(.horizontal, 6)
                                            .padding(.vertical, 2)
                                            .background(Color.white.opacity(0.25))
                                            .cornerRadius(6)
                                    }
                                    Text("Time: \(sd.lastEvent)")
                                        .font(.system(size: 12))
                                }
                                .foregroundColor(.white.opacity(0.95))
                            }
                            
                            if viewModel.isLiveTrackingActive {
                                HStack(spacing: 5) {
                                    Circle()
                                        .fill(Color.white)
                                        .frame(width: 7, height: 7)
                                    Text("Broadcasting Live Location")
                                        .font(.system(size: 11, weight: .semibold))
                                        .foregroundColor(.white)
                                }
                                .padding(.top, 2)
                            }
                        }
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
                        title: "Accident Type",
                        value: viewModel.sensorData?.accidentType ?? "-",
                        sub: "Classification",
                        highlight: viewModel.sensorData?.status == "ACCIDENT"
                    )
                    InfoCard(
                        title: "Passenger Severity",
                        value: viewModel.sensorData?.passengerSeverity ?? (viewModel.sensorData?.severity ?? "-"),
                        sub: viewModel.sensorData?.aisLevel ?? "Impact Matrix",
                        highlight: viewModel.sensorData?.status == "ACCIDENT"
                    )
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
                }.padding(.top, 10)
                
                // Occupant Biomechanical Injury Assessment (Crash Severity Data Matrix)
                OccupantInjuryCard(
                    steeringSide: viewModel.sensorData?.steeringSide ?? steeringSide,
                    passengerSeverity: viewModel.sensorData?.passengerSeverity ?? "None (AIS 0)",
                    passengerInjury: viewModel.sensorData?.passengerInjury ?? "Normal driving safe baseline / no trauma.",
                    driverSeverity: viewModel.sensorData?.driverSeverity ?? "None (AIS 0)",
                    driverInjury: viewModel.sensorData?.driverInjury ?? "Normal driving safe baseline / no trauma.",
                    occupantSummary: viewModel.sensorData?.occupantSummary ?? "",
                    isAccident: viewModel.sensorData?.status == "ACCIDENT"
                )
                .padding(.top, 8)
                
                
                // Real-time Sensors Section
                VStack(alignment: .leading, spacing: 10) {
                    Text("Real-time Sensors").bold().padding(.bottom, 5)
                    
                    VStack(spacing: 8) {
                        SensorRow(label: "Accelerometer Dynamic (G)", x: viewModel.accelX, y: viewModel.accelY, z: viewModel.accelZ)
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
                                    .foregroundColor(viewModel.debugStatus.contains("✅") || viewModel.debugStatus.contains("🚨") ? .green : .orange)
                                
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
            viewModel.steeringSide = steeringSide
            viewModel.startSensors()
        }
        .onDisappear {
            viewModel.stopSensors()
        }
    }
}

// MARK: - Occupant Injury Card Component (Crash Severity Data Matrix)
struct OccupantInjuryCard: View {
    var steeringSide: String
    var passengerSeverity: String
    var passengerInjury: String
    var driverSeverity: String
    var driverInjury: String
    var occupantSummary: String
    var isAccident: Bool
    
    private func badgeColor(for severityText: String) -> Color {
        let lower = severityText.lowercased()
        if lower.contains("fatal") || lower.contains("critical") || lower.contains("5") || lower.contains("6") {
            return Color.purple
        } else if lower.contains("severe") || lower.contains("serious") || lower.contains("3") || lower.contains("4") {
            return Color.red
        } else if lower.contains("moderate") || lower.contains("2") {
            return Color.orange
        } else if lower.contains("minor") || lower.contains("1") {
            return Color.yellow
        } else {
            return Color.green
        }
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Header
            HStack {
                Image(systemName: "person.2.fill")
                    .foregroundColor(isAccident ? .red : .blue)
                    .font(.system(size: 16))
                Text("Passenger & Occupant Injury Analysis")
                    .font(.system(size: 14, weight: .bold))
                Spacer()
                // Steering Side badge
                Text(steeringSide)
                    .font(.system(size: 11, weight: .bold))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Color.blue.opacity(0.12))
                    .foregroundColor(.blue)
                    .cornerRadius(8)
            }
            
            Divider()
            
            // Passenger Section
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    HStack(spacing: 5) {
                        Image(systemName: "person.fill")
                            .foregroundColor(.orange)
                        Text(steeringSide.lowercased().contains("left") ? "Passenger (Right Seat)" : "Passenger (Left Seat)")
                            .font(.system(size: 13, weight: .bold))
                    }
                    Spacer()
                    Text(passengerSeverity)
                        .font(.system(size: 11, weight: .bold))
                        .padding(.horizontal, 7)
                        .padding(.vertical, 2)
                        .background(badgeColor(for: passengerSeverity).opacity(0.2))
                        .foregroundColor(badgeColor(for: passengerSeverity))
                        .cornerRadius(6)
                }
                
                Text(passengerInjury)
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(10)
            .background(Color(white: 0.97))
            .cornerRadius(10)
            
            // Driver Section
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    HStack(spacing: 5) {
                        Image(systemName: "steeringwheel")
                            .foregroundColor(.blue)
                        Text(steeringSide.lowercased().contains("left") ? "Driver (Left Seat)" : "Driver (Right Seat)")
                            .font(.system(size: 13, weight: .bold))
                    }
                    Spacer()
                    Text(driverSeverity)
                        .font(.system(size: 11, weight: .bold))
                        .padding(.horizontal, 7)
                        .padding(.vertical, 2)
                        .background(badgeColor(for: driverSeverity).opacity(0.2))
                        .foregroundColor(badgeColor(for: driverSeverity))
                        .cornerRadius(6)
                }
                
                Text(driverInjury)
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(10)
            .background(Color(white: 0.97))
            .cornerRadius(10)
            
            // Occupant Summary / Cabin Dead-End Impact
            if isAccident && !occupantSummary.isEmpty {
                HStack(alignment: .top, spacing: 6) {
                    Image(systemName: "shield.lefthalf.filled")
                        .foregroundColor(.red)
                        .font(.system(size: 12))
                    Text(occupantSummary)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.primary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.top, 2)
            }
        }
        .padding(14)
        .background(Color.white)
        .cornerRadius(15)
        .shadow(color: Color.black.opacity(0.04), radius: 3)
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
                .font(.system(size: 16, weight: .bold))
                .foregroundColor(highlight ? .white : .primary)
                .multilineTextAlignment(.center)
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
