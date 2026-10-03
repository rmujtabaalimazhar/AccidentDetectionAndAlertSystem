
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
    let IMPACT_THRESHOLD_ACC: Double = 10    //19.6    // ~2.0 G (19.6 m/s² pure linear acceleration)
    let DEBOUNCE_MS: TimeInterval = 800       // 0.8s debounce prevents double-triggering
    let MIN_SUSTAINED_FRAMES: Int =   3         // Requires force to stay high for >= 3 consecutive frames (~40-60ms)
    let MIN_DURATION_MS: Double = 35        // Minimum sustained impact duration in ms (filters taps <35ms)
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
    
    // =========================================================================
    // REQUIRED PRIORITIZED STATE MACHINE STATE VARIABLES & CONSTANTS
    // =========================================================================
    
    // 1. Architectural Required State Variables
    @Published var is_freefall_locked: Bool = false            // Lockout flag disabling vehicle & rollover checks
    var freefall_lockout_until: Date = Date.distantPast        // Absolute lockout expiry timestamp (2000ms)
    var impact_timestamp: Date? = nil                          // Exact timestamp of T=0ms impact spike
    @Published var primary_event: String? = nil                // T=0ms classified primary event (e.g. SIDE COLLISION (RIGHT))
    @Published var in_phase_2: Bool = false                    // Active Phase 2 dynamic settlement & rollover verification flag
    
    // 2. Calibrated Architectural Thresholds & Constants
    let FREEFALL_ACC_THRESHOLD_G: Double = 0.25            // Top Priority: |a_total| < 0.25g indicates weightless free-fall
    let FREEFALL_MIN_DURATION_MS: Double = 120.0           // Minimum continuous zero-G duration before impact spike
    let FREEFALL_LOCKOUT_MS: Double = 2000.0               // Disables all vehicle accident & rollover checks for 2000ms
    let ROTATIONAL_NOISE_THRESHOLD_DEG_S: Double = 600.0   // 2nd Priority: ||w|| > 600 deg/s at peak impact rejects hand slap
    let IMPACT_COLLISION_THRESHOLD_G: Double = 4.0         // Collision impact threshold (|a_total| >= 4.0g)
    let PHASE2_SETTLED_GYRO_DEG_S: Double = 30.0           // Phase 2: Motion considered settled when ||w|| < 30 deg/s
    let PHASE2_MIN_SETTLED_MS: Double = 150.0              // Physical motion must remain settled for at least 150ms
    let PHASE2_MAX_TIMEOUT_MS: Double = 500.0              // Max dynamic settlement timeout (500ms)
    let ROLLOVER_POSTURE_ANGLE_DEG: Double = 60.0          // Static posture tilt phi = acos(|az|/|atotal|) > 60° confirms rollover
    
    // 3. Dynamic Motion Settlement & Posture Tracking Variables (Phase 2)
    private var phase2_peak_acc: Double = 0.0
    private var phase2_peak_ax: Double = 0.0
    private var phase2_peak_ay: Double = 0.0
    private var phase2_peak_az: Double = 0.0
    private var phase2_settled_start_time: Date? = nil
    
    // 4. 100 Hz IMU Rolling Buffer (stores last ~300ms of readings prior to impact)
    struct IMUReading {
        let timestamp: Date
        let totalAccelG: Double     // |a_total| = sqrt(totX^2 + totY^2 + totZ^2)
        let ax: Double              // totX (in G)
        let ay: Double              // totY (in G)
        let az: Double              // totZ (in G)
        let userAx: Double          // userAcceleration.x (in G)
        let userAy: Double          // userAcceleration.y (in G)
        let userAz: Double          // userAcceleration.z (in G)
        let gyroMagDegS: Double     // ||w|| in deg/s
        let rotX: Double            // rotationRate.x in rad/s
        let rotY: Double            // rotationRate.y in rad/s
        let rotZ: Double            // rotationRate.z in rad/s
    }
    private var imuBuffer: [IMUReading] = []
    
    // 5. Continuous Free-Fall Streak Tracking
    private var freefallStreakStartTime: Date? = nil
    private var lastQualifiedFreefallDurationMs: Double = 0.0
    private var lastQualifiedFreefallEndTime: Date = Date.distantPast
    
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
        if side.contains("fall") || side.contains("drop") { return "Phone Fall" }
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
    
    func determineExactSide(dynX: Double, dynY: Double, dynZ: Double, gravZ: Double, gyroMag: Double, isPhoneFall: Bool = false, rotatedPast90Deg: Bool = false) -> String {
        // 1. Rollover Check: EXACTLY when phone rotates above 90 degrees with active roll/tumble motion
        // (Prevents linear palm hits and table shocks from falsely triggering rollover)
        if rotatedPast90Deg || (gravZ > 0.15 && gyroMag >= 2.0) {
            return "Rollover"
        }
        
        // 2. Phone Fall Edge Case: Gated by at least 1.75 feet drop height (free-fall >= 300ms)
        if isPhoneFall {
            return "Phone Fall"
        }
        
        // 3. Linear Impact Strike (Calibrated for Physical Palm & Obstacle Collision):
        // Striking the Front (top edge) creates rearward deceleration in -Y
        // Striking the Rear (bottom edge) creates forward acceleration in +Y
        // Striking the Right side creates leftward deceleration in -X
        // Striking the Left side creates rightward acceleration in +X
        let absX = abs(dynX)
        let absY = abs(dynY)
        
        if absX < 0.10 && absY < 0.10 {
            return "Front" // Fallback default
        }
        
        let ratio = absX / max(absY, 0.0001)
        
        // Diagonal strike (balanced energy between longitudinal and lateral axes)
        if absX >= 0.18 && absY >= 0.18 && ratio >= 0.45 && ratio <= 2.2 {
            let lon = dynY <= 0 ? "Front" : "Rear"
            let lat = dynX <= 0 ? "Right" : "Left"
            return "\(lon)-\(lat)"
        }
        
        // Orthogonal strike
        if absY >= absX {
            return dynY <= 0 ? "Front" : "Rear"
        } else {
            return dynX <= 0 ? "Right" : "Left"
        }
    }
    
    func sendImpact(acceleration: Double, coords: CLLocationCoordinate2D, detectedSide: String = "Front", dynX: Double = 0, dynY: Double = 0, dynZ: Double = 0, gravZ: Double = 0.0, durationMs: Double = 40.0, isPhoneFall: Bool = false, freeFallMs: Double = 0.0) {
        let effectiveCarId = carId > 0 ? carId : 1
        
        let now = Date()
        if now.timeIntervalSince(lastSent) * 1000 < DEBOUNCE_MS { return }
        lastSent = now
        
        DispatchQueue.main.async {
            self.debugStatus = isPhoneFall ? "📱 Sending Phone Fall Edge Case…" : (detectedSide.contains("Rollover") ? "🔄 Sending Rollover Crash…" : "📡 Sending to API…")
        }
        
        guard let url = URL(string: "\(API)/DetectAccident/ImpactCalculation") else { return }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let gForce = acceleration / 9.81
        let clientSeverity = gForce > 7.0 ? "High" : (gForce > 4.0 ? "Medium" : "Low")
        let isoFormatter = ISO8601DateFormatter()
        let timeIso = isoFormatter.string(from: now)
        
        let isRollover = detectedSide.contains("Rollover")
        let isFall = !isRollover && (isPhoneFall || detectedSide.contains("Fall"))
        
        let body: [String: Any] = [
            "CarId": effectiveCarId,
            "Car_Id": effectiveCarId,
            "AccidentType": isRollover ? "Rollover" : (isFall ? "Phone Fall" : "Impact"),
            "Acceleration": acceleration,
            "GForce": gForce,
            "ImpactDurationMs": durationMs,
            "ImpactSide": detectedSide,
            "SteeringSide": steeringSide,
            "FreeFallDurationMs": isFall ? freeFallMs : 0.0,
            "IsFreeFall": isFall,
            "AccelX": dynX,
            "AccelY": dynY,
            "AccelZ": dynZ,
            "GravityZ": gravZ,
            "GyroX": gyroX,
            "GyroY": gyroY,
            "GyroZ": gyroZ,
            "Latitude": coords.latitude,
            "Longitude": coords.longitude,
            "Severity": isFall ? "Safe (Edge Case)" : (isRollover ? "High" : clientSeverity),
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
                        let accidentType = json["accidentType"] as? String ?? (isFall ? "Phone Fall" : "Impact")
                        let rawSide     = json["impactSide"] as? String ?? detectedSide
                        let impactForce = json["impactForce"] as? Double ?? 0
                        var cabinDamage = json["cabinDamage"] as? Double ?? 0
                        let cabinForce  = json["cabinForce"] as? Double ?? 0
                        let apiStatus   = json["status"] as? String ?? (isFall ? "PHONE_FALL" : "SAFE")
                        let serverTime  = json["time"] as? String ?? timeStr

                        let aisLevel = json["aisLevel"] as? String ?? "AIS 0"
                        let passengerSeverity = json["passengerSeverity"] as? String ?? (json["severity"] as? String ?? (isFall ? "Safe (Edge Case)" : clientSeverity))
                        let passengerInjury = json["passengerInjury"] as? String ?? (isFall ? "Edge Case: Phone drop detected and safely filtered without vehicle cabin damage." : "No significant injuries detected.")
                        let driverSeverity = json["driverSeverity"] as? String ?? passengerSeverity
                        let driverInjury = json["driverInjury"] as? String ?? (isFall ? "Edge Case: Phone drop detected and safely filtered without vehicle cabin damage." : "Normal driving safe baseline.")
                        let occupantSummary = json["occupantSummary"] as? String ?? (isFall ? "Phone drop detected (free-fall weightlessness & transient impact). Vehicle safe." : "")
                        let steeringSideRet = json["steeringSide"] as? String ?? self.steeringSide

                        if cabinDamage == 0 && cabinForce > 0 && impactForce > 0 {
                            cabinDamage = (cabinForce / (impactForce * 0.5)) * 100
                        }
                        if cabinDamage.isNaN { cabinDamage = 0 }
                        cabinDamage = max(0, min(100, cabinDamage))

                        if apiStatus == "PHONE_FALL" || accidentType.contains("Fall") {
                            self.debugStatus = String(format: "📱 Phone Fall Edge Case Detected! (Force=%.0fN | Vehicle Safe)", impactForce)
                        } else if apiStatus == "ACCIDENT" {
                            self.debugStatus = String(format: "🚨 %@ [%@]! Force=%.0fN Damage=%.0f%%", accidentType.uppercased(), passengerSeverity.uppercased(), impactForce, cabinDamage)
                        } else {
                            self.debugStatus = String(format: "✅ API OK: \(rawSide) (force=%.0fN)", impactForce)
                        }

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
                        
                        // Start continuous live location broadcasting only for active vehicle accidents (not phone drops)
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
    
    // =========================================================================
    // STATE MACHINE HELPER FUNCTIONS & LOGGING
    // =========================================================================
    
    /// Clean, timestamped terminal log output for monitoring state transitions in real time during live reviews & testing
    private func logStateTransition(_ message: String) {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss.SSS"
        let timestamp = formatter.string(from: Date())
        print("[\(timestamp)] \(message)")
    }
    
    /// Phase 1: Classify primary impact direction based solely on theta = atan2(a_y, a_x)
    /// Ignores gyro orientation angles and resting tilt (a_z) at this exact millisecond.
    func classifyImpactDirection(ax: Double, ay: Double) -> (event: String, thetaDeg: Double) {
        let thetaRad = atan2(ay, ax)
        let thetaDeg = thetaRad * (180.0 / Double.pi)
        
        let direction: String
        if thetaDeg >= -45.0 && thetaDeg <= 45.0 {
            direction = "FRONTAL COLLISION"
        } else if (thetaDeg >= 135.0 && thetaDeg <= 180.0) || (thetaDeg >= -180.0 && thetaDeg <= -135.0) {
            direction = "REAR COLLISION"
        } else if thetaDeg > 45.0 && thetaDeg < 135.0 {
            direction = "SIDE COLLISION (RIGHT)"
        } else { // thetaDeg > -135.0 && thetaDeg < -45.0
            direction = "SIDE COLLISION (LEFT)"
        }
        return (direction, thetaDeg)
    }
    
    /// Top Priority: Evaluates pre-impact rolling buffer for continuous weightlessness (|a_total| < 0.25g for >= 120ms)
    private func checkContinuousFreefall(priorTo spikeTime: Date) -> (isFreefall: Bool, durationMs: Double) {
        // Filter rolling buffer readings in the 300ms window preceding the impact spike
        let preSpike = imuBuffer.filter { reading in
            let delta = spikeTime.timeIntervalSince(reading.timestamp)
            return delta >= 0 && delta <= 0.30
        }.sorted { $0.timestamp > $1.timestamp }
        
        var consecutiveCount = 0
        var firstTime: Date? = nil
        var lastTime: Date? = nil
        var skippedTransitionFrames = 0
        
        for reading in preSpike {
            if reading.totalAccelG < FREEFALL_ACC_THRESHOLD_G {
                consecutiveCount += 1
                if firstTime == nil { firstTime = reading.timestamp }
                lastTime = reading.timestamp
            } else {
                if consecutiveCount > 0 {
                    break
                } else if skippedTransitionFrames < 2 {
                    // Allow up to 2 transition frames leading into the impact shock front
                    skippedTransitionFrames += 1
                } else {
                    break
                }
            }
        }
        
        var durationMs: Double = 0.0
        if let first = firstTime, let last = lastTime {
            durationMs = abs(first.timeIntervalSince(last)) * 1000.0 + 10.0
        }
        
        let qualifies = consecutiveCount >= 12 || durationMs >= FREEFALL_MIN_DURATION_MS
        return (qualifies, max(durationMs, Double(consecutiveCount) * 10.0))
    }
    
    /// Phase 2: Dynamic Motion Settlement & Rollover Verification
    /// Resolves settlement and evaluates static posture angle relative to gravity: phi = acos(|a_z| / |a_total|)
    private func finalizePhase2(
        currentPrimary: String,
        settledMs: Double,
        totalElapsedMs: Double,
        isTimeout: Bool,
        motion: CMDeviceMotion,
        totalMagG: Double,
        totZ: Double
    ) {
        if isTimeout {
            logStateTransition("⏱️ [PHASE 2 TIMING] Motion settlement reached max timeout limit (\(String(format: "%.0f", totalElapsedMs))ms). Evaluating static posture angle.")
        } else {
            logStateTransition("✅ [PHASE 2 TIMING] Physical motion settled dynamically (||w|| < 30 deg/s for \(String(format: "%.0f", settledMs))ms, total duration: \(String(format: "%.0f", totalElapsedMs))ms).")
        }
        
        // Calculate static posture angle relative to gravity: phi = acos(|a_z| / |a_total|)
        let ratio = min(1.0, max(0.0, abs(totZ) / max(totalMagG, 0.0001)))
        let phiRad = acos(ratio)
        let phiDeg = phiRad * (180.0 / Double.pi)
        
        // Check if vehicle orientation landed upside down on roof (Gz > 0.20 in CoreMotion)
        let isRoofInverted = motion.gravity.z > 0.20
        let finalEvent: String
        
        if phiDeg > ROLLOVER_POSTURE_ANGLE_DEG || isRoofInverted {
            // Reclassify event as primary_event + " WITH ROLLOVER"
            finalEvent = "\(currentPrimary) WITH ROLLOVER"
            logStateTransition("🔄 [PHASE 2 RESOLVED] Reclassified event as: [\(finalEvent)] (Post-impact angle phi = \(String(format: "%.1f", phiDeg))° > 60° [ROLLOVER CONFIRMED]).")
        } else {
            // Retain pure primary_event, confirming transient side-impact tilt has resolved
            finalEvent = currentPrimary
            logStateTransition("🛡️ [PHASE 2 RESOLVED] Retained Pure Primary Event: [\(finalEvent)] (Post-impact angle phi = \(String(format: "%.1f", phiDeg))° <= 60° [TRANSIENT WOBBLE CLEARED]).")
        }
        
        let coords = currentLocation ?? CLLocationCoordinate2D(latitude: 0, longitude: 0)
        confirmAccident(
            dynX: phase2_peak_ax,
            dynY: phase2_peak_ay,
            dynZ: phase2_peak_az,
            gravZ: motion.gravity.z,
            gyroX: motion.rotationRate.x,
            gyroY: motion.rotationRate.y,
            gyroZ: motion.rotationRate.z,
            acc: phase2_peak_acc,
            durationMs: max(totalElapsedMs, 35.0),
            isPhoneFall: false,
            freeFallMs: 0.0,
            classifiedSide: finalEvent
        )
        
        // Reset Phase 2 State
        in_phase_2 = false
        primary_event = nil
        impact_timestamp = nil
        phase2_settled_start_time = nil
    }
    
    func confirmAccident(dynX: Double, dynY: Double, dynZ: Double, gravZ: Double, gyroX: Double, gyroY: Double, gyroZ: Double, acc: Double, durationMs: Double = 40.0, isPhoneFall: Bool = false, freeFallMs: Double = 0.0, rotatedPast90Deg: Bool = false, classifiedSide: String? = nil) {
        let now = Date()
        if now.timeIntervalSince(lastSent) * 1000 < DEBOUNCE_MS { return }
        
        // Filter out extreme sensor resets (> 350 m/s²)
        if acc > 350 { return }
        
        let gyroMagnitude = sqrt(gyroX*gyroX + gyroY*gyroY + gyroZ*gyroZ)
        let detectedSide = classifiedSide ?? determineExactSide(dynX: dynX, dynY: dynY, dynZ: dynZ, gravZ: gravZ, gyroMag: gyroMagnitude, isPhoneFall: isPhoneFall, rotatedPast90Deg: rotatedPast90Deg)
        
        let isActuallyFall = isPhoneFall || detectedSide.contains("Fall") || detectedSide.contains("FALL") || detectedSide.contains("DROP")
        
        if isActuallyFall {
            debugStatus = String(format: "📱 Phone Fall Edge Case: Acc=%.1f m/s² (FF=%.0fms)", acc, freeFallMs)
        } else {
            debugStatus = String(format: "🚨 Verified %@! Acc=%.1f m/s² (%.0fms)", detectedSide, acc, durationMs)
        }
        
        let coords = currentLocation ?? CLLocationCoordinate2D(latitude: 0, longitude: 0)
        sendImpact(acceleration: acc, coords: coords, detectedSide: detectedSide, dynX: dynX, dynY: dynY, dynZ: dynZ, gravZ: gravZ, durationMs: durationMs, isPhoneFall: isActuallyFall, freeFallMs: isActuallyFall ? freeFallMs : 0.0)
    }
    
    func startSensors() {
        self.lastAccel = 1.0
        self.prevAcc = 0
        self.shake = 0
        self.readCount = 0
        self.is_freefall_locked = false
        self.freefall_lockout_until = Date.distantPast
        self.impact_timestamp = nil
        self.primary_event = nil
        self.in_phase_2 = false
        self.phase2_settled_start_time = nil
        self.imuBuffer.removeAll()
        self.freefallStreakStartTime = nil
        self.lastQualifiedFreefallDurationMs = 0.0
        self.lastQualifiedFreefallEndTime = Date.distantPast
        self.debugStatus = "Calibrating sensors (100 Hz)…"
        
        logStateTransition("🚀 [SENSOR INITIALIZATION] Starting IMU at 100 Hz with Prioritized State Machine & Temporal Phase Separation.")
        
        if motionManager.isDeviceMotionAvailable {
            motionManager.deviceMotionUpdateInterval = 0.01 // 100 Hz update (10ms per frame)
            motionManager.startDeviceMotionUpdates(to: .main) { [weak self] motion, error in
                guard let self = self, let motion = motion else { return }
                
                let now = Date()
                
                // 1. Core IMU Kinematics Extraction
                let uX = motion.userAcceleration.x // G
                let uY = motion.userAcceleration.y // G
                let uZ = motion.userAcceleration.z // G
                let gX = motion.gravity.x
                let gY = motion.gravity.y
                let gZ = motion.gravity.z
                let rX = motion.rotationRate.x     // rad/s
                let rY = motion.rotationRate.y     // rad/s
                let rZ = motion.rotationRate.z     // rad/s
                
                // Total acceleration vector (including gravity)
                let totX = uX + gX
                let totY = uY + gY
                let totZ = uZ + gZ
                
                // Total linear acceleration magnitude |a_total| in G
                let totalMagG = sqrt(totX*totX + totY*totY + totZ*totZ)
                
                // Gyroscope angular velocity magnitude ||w|| in deg/s
                let gyroMagDegS = sqrt(rX*rX + rY*rY + rZ*rZ) * (180.0 / Double.pi)
                
                // Dynamic linear acceleration magnitude (without gravity baseline)
                let dynMagnitude = sqrt(uX*uX + uY*uY + uZ*uZ)
                
                // Update Published state for live UI view
                self.accelX = uX
                self.accelY = uY
                self.accelZ = uZ
                self.gyroX = rX
                self.gyroY = rY
                self.gyroZ = rZ
                self.shakeLevel = dynMagnitude
                
                // 2. Rolling Buffer Maintenance (100 Hz, sample duration: last ~300ms)
                let reading = IMUReading(
                    timestamp: now,
                    totalAccelG: totalMagG,
                    ax: totX,
                    ay: totY,
                    az: totZ,
                    userAx: uX,
                    userAy: uY,
                    userAz: uZ,
                    gyroMagDegS: gyroMagDegS,
                    rotX: rX,
                    rotY: rY,
                    rotZ: rZ
                )
                self.imuBuffer.append(reading)
                self.imuBuffer.removeAll { now.timeIntervalSince($0.timestamp) > 0.35 }
                
                // 3. Continuous Free-fall Weightlessness Streak Tracking
                if totalMagG < self.FREEFALL_ACC_THRESHOLD_G {
                    if self.freefallStreakStartTime == nil {
                        self.freefallStreakStartTime = now
                    }
                    let streakMs = now.timeIntervalSince(self.freefallStreakStartTime!) * 1000.0
                    if streakMs >= self.FREEFALL_MIN_DURATION_MS {
                        self.lastQualifiedFreefallDurationMs = streakMs
                        self.lastQualifiedFreefallEndTime = now
                    }
                } else {
                    self.freefallStreakStartTime = nil
                }
                
                // 4. Warmup reads check
                self.readCount += 1
                if self.readCount < self.WARMUP_READS {
                    self.debugStatus = "Calibrating 100 Hz sensors (\(self.readCount)/\(self.WARMUP_READS))…"
                    return
                }
                
                // =========================================================================
                // TOP PRIORITY: FREE-FALL / PHONE DROP LOCKOUT INTERLOCK
                // =========================================================================
                if self.is_freefall_locked {
                    if now < self.freefall_lockout_until {
                        let remainingMs = self.freefall_lockout_until.timeIntervalSince(now) * 1000.0
                        self.debugStatus = String(format: "🔒 Free-fall Lockout: %.0fms remaining", remainingMs)
                        return // Disabling all Vehicle Accident and Rollover checks for 2000ms
                    } else {
                        self.is_freefall_locked = false
                        self.logStateTransition("🔓 [LOCKOUT EXPIRED] 2000ms free-fall lockout completed. Vehicle crash detection re-armed.")
                    }
                }
                
                // =========================================================================
                // PHASE 2: DYNAMIC MOTION SETTLEMENT & ROLLOVER VERIFICATION
                // =========================================================================
                if self.in_phase_2, let impactTime = self.impact_timestamp, let currentPrimary = self.primary_event {
                    let timeSinceImpactMs = now.timeIntervalSince(impactTime) * 1000.0
                    
                    // Track peak acceleration during dynamic impact interval
                    let currentLinearAcc = totalMagG * 9.81
                    if currentLinearAcc > self.phase2_peak_acc {
                        self.phase2_peak_acc = currentLinearAcc
                    }
                    
                    // Monitor gyroscope magnitude ||w|| post-impact: check if physical motion has settled (< 30 deg/s)
                    let isSettled = gyroMagDegS < self.PHASE2_SETTLED_GYRO_DEG_S
                    if isSettled {
                        if self.phase2_settled_start_time == nil {
                            self.phase2_settled_start_time = now
                        }
                        let settledMs = now.timeIntervalSince(self.phase2_settled_start_time!) * 1000.0
                        
                        // Condition: Settled for at least 150ms OR max timeout of 500ms reached
                        if settledMs >= self.PHASE2_MIN_SETTLED_MS || timeSinceImpactMs >= self.PHASE2_MAX_TIMEOUT_MS {
                            self.finalizePhase2(
                                currentPrimary: currentPrimary,
                                settledMs: settledMs,
                                totalElapsedMs: timeSinceImpactMs,
                                isTimeout: false,
                                motion: motion,
                                totalMagG: totalMagG,
                                totZ: totZ
                            )
                            return
                        }
                    } else {
                        // Reset settlement streak on any post-impact wobble disturbance
                        self.phase2_settled_start_time = nil
                        
                        if timeSinceImpactMs >= self.PHASE2_MAX_TIMEOUT_MS {
                            // Max timeout of 500ms reached
                            self.finalizePhase2(
                                currentPrimary: currentPrimary,
                                settledMs: 0.0,
                                totalElapsedMs: timeSinceImpactMs,
                                isTimeout: true,
                                motion: motion,
                                totalMagG: totalMagG,
                                totZ: totZ
                            )
                            return
                        }
                    }
                    
                    self.debugStatus = String(format: "⏳ Phase 2: %@ (||w||=%.0f°/s | %.0fms)", currentPrimary, gyroMagDegS, timeSinceImpactMs)
                    return // Suppress conflicting triggers while resolving Phase 2
                }
                
                // =========================================================================
                // IMPACT SPIKE EVALUATION: PRIORITIES 1 & 2 + PHASE 1 CLASSIFICATION
                // =========================================================================
                if totalMagG >= self.IMPACT_COLLISION_THRESHOLD_G {
                    // Debounce check
                    if now.timeIntervalSince(self.lastSent) * 1000.0 < self.DEBOUNCE_MS { return }
                    
                    // ---------------------------------------------------------------------
                    // TOP PRIORITY: FREE-FALL / PHONE DROP INTERLOCK
                    // ---------------------------------------------------------------------
                    // Check rolling buffer: |a_total| < 0.25g for >= 120ms continuously before impact spike
                    let (bufferFreefall, bufferDuration) = self.checkContinuousFreefall(priorTo: now)
                    let recentStreakFreefall = (now.timeIntervalSince(self.lastQualifiedFreefallEndTime) <= 0.10)
                    
                    if bufferFreefall || recentStreakFreefall {
                        let dropDurationMs = max(bufferDuration, self.lastQualifiedFreefallDurationMs)
                        
                        // 1. Emit Event: "PHONE DROP / FALL DETECTED"
                        self.logStateTransition("⚠️ [TOP PRIORITY: FREE-FALL INTERLOCK] PHONE DROP / FALL DETECTED (Pre-impact zero-g duration: \(String(format: "%.0f", dropDurationMs))ms). Setting Lockout Flag for 2000ms. Disabling vehicle crash & rollover checks.")
                        
                        // 2. Set Lockout Flag disabling all Vehicle Accident and Rollover checks for 2000ms
                        self.is_freefall_locked = true
                        self.freefall_lockout_until = now.addingTimeInterval(self.FREEFALL_LOCKOUT_MS / 1000.0)
                        
                        self.debugStatus = String(format: "📱 PHONE DROP / FALL DETECTED (%.0fms) — Lockout 2s", dropDurationMs)
                        
                        // Transmit safe fall edge case
                        let coords = self.currentLocation ?? CLLocationCoordinate2D(latitude: 0, longitude: 0)
                        self.sendImpact(
                            acceleration: totalMagG * 9.81,
                            coords: coords,
                            detectedSide: "PHONE DROP / FALL DETECTED",
                            dynX: uX,
                            dynY: uY,
                            dynZ: uZ,
                            gravZ: gZ,
                            durationMs: 30.0,
                            isPhoneFall: true,
                            freeFallMs: dropDurationMs
                        )
                        
                        // 3. Exit processing loop for this window
                        return
                    }
                    
                    // ---------------------------------------------------------------------
                    // SECOND PRIORITY: ROTATIONAL NOISE / HAND SLAP FILTER
                    // ---------------------------------------------------------------------
                    // If ||w|| > 600 deg/s AT THE EXACT PEAK of the impact spike: reject as manual noise
                    if gyroMagDegS > self.ROTATIONAL_NOISE_THRESHOLD_DEG_S {
                        self.logStateTransition("✋ [SECOND PRIORITY: ROTATIONAL NOISE FILTER] HAND SLAP / MANUAL HANDLING REJECTED. Total angular velocity ||w|| = \(String(format: "%.1f", gyroMagDegS)) deg/s > 600 deg/s at peak impact (|a_total| = \(String(format: "%.2f", totalMagG))g). Rejecting as vehicle collision.")
                        self.debugStatus = String(format: "✋ Hand Slap / Rotational Noise Rejected (%.0f°/s)", gyroMagDegS)
                        return // Exit processing loop
                    }
                    
                    // ---------------------------------------------------------------------
                    // PHASE 1 (AT T = 0ms IMPACT MOMENT): IMPACT DIRECTION CLASSIFICATION
                    // ---------------------------------------------------------------------
                    // |a_total| >= Threshold AND Free-fall Flag == False AND Rotational Noise == False
                    // Compute horizontal vector angle: theta = atan2(a_y, a_x)
                    // Ignore gyro orientation angles and resting tilt (a_z) at this exact millisecond!
                    let (classifiedDirection, thetaDeg) = self.classifyImpactDirection(ax: uX, ay: uY)
                    
                    self.primary_event = classifiedDirection
                    self.impact_timestamp = now
                    self.in_phase_2 = true
                    self.phase2_peak_acc = totalMagG * 9.81
                    self.phase2_peak_ax = uX
                    self.phase2_peak_ay = uY
                    self.phase2_peak_az = uZ
                    self.phase2_settled_start_time = nil
                    
                    self.logStateTransition("💥 [PHASE 1: IMPACT DIRECTION CLASSIFIED] Primary Event: [\(classifiedDirection)] | theta = \(String(format: "%.1f", thetaDeg))° | |a_total| = \(String(format: "%.2f", totalMagG))g | ||w|| = \(String(format: "%.1f", gyroMagDegS)) deg/s. Transitioning into Phase 2 Dynamic Settlement & Rollover Verification.")
                    
                    self.debugStatus = "💥 Phase 1: \(classifiedDirection) (Settling motion…)"
                    return
                }
                
                // Normal monitoring status update (when no event is actively pending)
                if !self.in_phase_2 && !self.is_freefall_locked && now.timeIntervalSince(self.lastSent) * 1000.0 > self.DEBOUNCE_MS {
                    self.debugStatus = String(format: "Monitoring (100 Hz): |a_total|=%.2fg (dyn=%.2fg)", totalMagG, dynMagnitude)
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
    @State private var showDatasetRecorder: Bool = false
    @State private var datasetRecorderMode: DatasetRecordingMode = .rollover
    
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
                    let isPhoneFall = sd.status == "PHONE_FALL" || sd.accidentType.contains("Fall")
                    let isAccident = sd.status == "ACCIDENT"
                    
                    HStack(spacing: 12) {
                        Image(systemName: isAccident ? "exclamationmark.triangle.fill" : (isPhoneFall ? "arrow.down.to.line.compact" : "checkmark.shield.fill"))
                            .font(.system(size: 24))
                            .foregroundColor(.white)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(isAccident ? "🚨 \(sd.accidentType.uppercased()) DETECTED" : (isPhoneFall ? "📱 PHONE FALL DETECTED (EDGE CASE)" : "✅ Safe — No Accident"))
                                .bold()
                                .foregroundColor(.white)
                            if isAccident || isPhoneFall {
                                HStack(spacing: 8) {
                                    if let sev = sd.passengerSeverity ?? sd.severity {
                                        Text(isPhoneFall ? "Edge Case: 0% Damage" : "Severity: \(sev)")
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
                            
                            if isPhoneFall {
                                Text("Non-collision phone drop filtered with zero vehicle damage.")
                                    .font(.system(size: 11))
                                    .foregroundColor(.white.opacity(0.9))
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
                    .background(isAccident ? Color.red : (isPhoneFall ? Color.orange : Color(red: 0.1, green: 0.7, blue: 0.3)))
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
                
                // Dataset Recorders: Rollover & Phone Fall
                HStack(spacing: 8) {
                    Button(action: {
                        datasetRecorderMode = .rollover
                        showDatasetRecorder = true
                    }) {
                        HStack(spacing: 6) {
                            Image(systemName: "arrow.triangle.2.circlepath.circle.fill")
                                .font(.system(size: 14))
                            Text("Record Rollover Data")
                                .font(.system(size: 12, weight: .bold))
                        }
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(Color(red: 230/255, green: 80/255, blue: 0/255))
                        .cornerRadius(12)
                        .shadow(color: Color.orange.opacity(0.3), radius: 4, x: 0, y: 2)
                    }
                    
                    Button(action: {
                        datasetRecorderMode = .fall
                        showDatasetRecorder = true
                    }) {
                        HStack(spacing: 6) {
                            Image(systemName: "record.circle.fill")
                                .font(.system(size: 14))
                            Text("Record Fall Data")
                                .font(.system(size: 12, weight: .bold))
                        }
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(Color(red: 130/255, green: 40/255, blue: 215/255))
                        .cornerRadius(12)
                        .shadow(color: Color.purple.opacity(0.25), radius: 4, x: 0, y: 2)
                    }
                }
                .padding(.top, 4)
                
            }
            .padding(12)
        }
        .background(Color(white: 0.949).edgesIgnoringSafeArea(.all))
        .navigationBarHidden(true)
        .sheet(isPresented: $showDatasetRecorder) {
            FallDatasetRecorderView(initialMode: datasetRecorderMode)
        }
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
