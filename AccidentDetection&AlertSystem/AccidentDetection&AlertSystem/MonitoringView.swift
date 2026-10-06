
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
    // DUAL-SCENARIO MODE (STATIONARY MODE VS. ACTIVE DRIVING / RUNNING MODE)
    // =========================================================================
    @Published var isDrivingMode: Bool = false                  // Scenario 1: false = Stationary/Parked | Scenario 2: true = Active Driving
    @Published var isTrackRunActive: Bool = false               // Synchronized timer status
    @Published var trackDistanceMeters: Double = 4.0
    @Published var trackDistanceInput: String = "4.0"
    @Published var trackRunStartTime: Date? = nil
    @Published var lastTrackElapsedTime: Double? = nil
    @Published var liveTrackElapsedString: String = "0.000s"
    @Published var liveTrackEstimatedSpeed: Double = 0.0
    @Published var liveTrackEstimatedAccel: Double = 0.0
    @Published var liveRealWorldSpeedKmh: Double = 0.0
    @Published var lastToySpeedMs: Double? = nil
    @Published var lastRealWorldSpeedKmh: Double? = nil
    @Published var lastTrackAccel: Double? = nil
    @Published var lastTrackGForce: Double? = nil
    private var trackRunTimer: Timer? = nil
    
    // Rolling Telemetry Buffer for Active Driving Mode
    struct DrivingTelemetrySample {
        let timestamp: Date
        let ax: Double
        let ay: Double
        let az: Double
        let dynMagnitude: Double
        let totalMagG: Double
        let gyroMagDegS: Double
    }
    private var recentDrivingSamples: [DrivingTelemetrySample] = []
    private var lastHardBrakingTimestamp: Date? = nil
    
    // =========================================================================
    // REQUIRED PRIORITIZED STATE MACHINE STATE VARIABLES & CONSTANTS
    // =========================================================================
    
    // 1. Architectural Required State Variables & Persistent Free-Fall Latch
    @Published var is_freefall_locked: Bool = false            // Lockout flag disabling vehicle & rollover checks
    var freefall_lockout_until: Date = Date.distantPast        // Absolute lockout expiry timestamp
    @Published var is_freefall_latched: Bool = false           // Persistent latch permanently blocking rollover checks after drop
    var freefall_latch_expiration: Date = Date.distantPast     // 3.0s window for persistent free-fall latch
    var impact_timestamp: Date? = nil                          // Exact timestamp of T=0ms impact spike
    @Published var primary_event: String? = nil                // T=0ms classified primary event (e.g. SIDE COLLISION (RIGHT))
    @Published var in_phase_2: Bool = false                    // Active Phase 2 dynamic settlement & rollover verification flag
    
    // 2. Calibrated Architectural Thresholds & Constants (Persistent Free-Fall Latch)
    let FREEFALL_ACC_THRESHOLD_G: Double = 0.40            // Zero-G threshold: |a_total| < 0.40g indicates weightless free-fall
    let FREEFALL_MIN_SAMPLES: Int = 5                      // Windowed sample counter: at least 5 samples at 100 Hz (>= 50ms low-g)
    let FREEFALL_WINDOW_MS: Double = 200.0                 // Evaluates low-g sample count within the last 200ms buffer window
    let FREEFALL_MIN_DURATION_MS: Double = 50.0            // Minimum low-g duration (50ms)
    let FREEFALL_LOCKOUT_MS: Double = 3000.0               // Persistent latch window: 3000ms (3.0s) blocks all rollover checks
    let ROTATIONAL_NOISE_THRESHOLD_DEG_S: Double = 600.0   // 2nd Priority: ||w|| > 600 deg/s at peak impact rejects hand slap
    let IMPACT_COLLISION_THRESHOLD_G: Double = 4.0         // Collision impact threshold (|a_total| >= 4.0g)
    let PHASE2_SETTLED_GYRO_DEG_S: Double = 30.0           // Phase 2: Motion considered settled when ||w|| < 30 deg/s
    let PHASE2_MIN_SETTLED_MS: Double = 150.0              // Physical motion must remain settled for at least 150ms
    let PHASE2_MAX_TIMEOUT_MS: Double = 500.0              // Max dynamic settlement timeout (500ms)
    let ROLLOVER_POSTURE_ANGLE_DEG: Double = 35.0          // Static posture tilt phi = acos(|az|/|atotal|) > 35° confirms rollover
    
    // 3. Dynamic Motion Settlement & Posture Tracking Variables (Phase 2 & Standalone)
    private var phase2_peak_acc: Double = 0.0
    private var phase2_peak_ax: Double = 0.0
    private var phase2_peak_ay: Double = 0.0
    private var phase2_peak_az: Double = 0.0
    private var phase2_settled_start_time: Date? = nil
    
    // Standalone / Handheld Rollover Tracking (Screen Orientation Matrix)
    let STANDALONE_ROLLOVER_REST_GYRO_DEG_S: Double = 45.0    // Rest threshold: ||w|| < 45 deg/s allows jerky motions
    let STANDALONE_ROLLOVER_MIN_REST_MS: Double = 150.0       // Resting at posture for >= 150ms (quick handheld response)
    let STANDALONE_ROLLOVER_MAX_POSTURE_MS: Double = 250.0    // Continuous posture for >= 250ms fallback
    private var standalone_rollover_posture_start_time: Date? = nil // Timestamp when rolled-over posture began
    private var standalone_rollover_rest_start_time: Date? = nil    // Timestamp when quiet rest (< 45 deg/s) began
    
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
    
    // 6. Tier 3 Driving Dynamic Edge Cases Tracking Variables
    private var hardBrakingWindow: [(timestamp: Date, ay: Double)] = []
    private var driftStreakStartTime: Date? = nil
    private var speedBumpFirstPeakTime: Date? = nil
    private var lastEdgeCaseSent: Date = Date.distantPast
    let EDGE_CASE_DEBOUNCE_MS: TimeInterval = 1500.0 // 1.5s debounce for driving edge cases
    
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
        // 1. Phone Fall Edge Case: Gated first so drops do not trigger collision or rollover
        if isPhoneFall {
            return "Phone Fall"
        }
        
        // 2. Rollover Check: Inversion past 90 degrees with sustained tumble
        if rotatedPast90Deg || (gravZ > 0.20 && gyroMag >= 3.0) {
            return "Rollover"
        }
        
        // 3. Directional Vector Analysis (Impact Side)
        let lr = dynX // Left/Right axis
        let fb = dynY // Front/Back axis
        
        let absLR = abs(lr)
        let absFB = abs(fb)
        
        if absLR < 0.3 && absFB < 0.3 {
            return "Front" // Fallback / Minor
        }
        
        if absFB > absLR {
            if fb > 0 {
                return (absLR > 0.3) ? (lr > 0 ? "Front-Right" : "Front-Left") : "Front"
            } else {
                return (absLR > 0.3) ? (lr > 0 ? "Rear-Right" : "Rear-Left") : "Rear"
            }
        } else {
            return lr > 0 ? "Right" : "Left"
        }
    }
    
    // =========================================================================
    // =========================================================================
    // DUAL-SCENARIO MODE CONTROLS (STATIONARY MODE VS. ACTIVE DRIVING MODE)
    // =========================================================================
    func updateTrackDistance(_ newDistanceStr: String) {
        trackDistanceInput = newDistanceStr
        let clean = newDistanceStr.replacingOccurrences(of: ",", with: ".").trimmingCharacters(in: .whitespacesAndNewlines)
        if let val = Double(clean), val > 0 {
            trackDistanceMeters = val
            if let elapsed = lastTrackElapsedTime, elapsed > 0.05 {
                liveTrackEstimatedSpeed = (2.0 * val) / elapsed
                liveTrackEstimatedAccel = (2.0 * val) / (elapsed * elapsed)
            }
        }
    }
    
    // SCENARIO 2 TRIGGER: Start Active Driving Run on Track (d = 4.0m or custom)
    func startDriveRun() {
        startTrackRun()
    }
    
    func startTrackRun() {
        isDrivingMode = true
        isTrackRunActive = true
        let clean = trackDistanceInput.replacingOccurrences(of: ",", with: ".").trimmingCharacters(in: .whitespacesAndNewlines)
        if let val = Double(clean), val > 0 {
            trackDistanceMeters = val
        } else {
            trackDistanceMeters = 4.0
            trackDistanceInput = "4.0"
        }
        
        let start = Date()
        trackRunStartTime = start
        lastTrackElapsedTime = nil
        lastTrackAccel = nil
        lastTrackGForce = nil
        liveTrackElapsedString = "0.000s"
        liveTrackEstimatedSpeed = 0.0
        liveTrackEstimatedAccel = 0.0
        debugStatus = String(format: "🏎️ Active Driving Mode Started (%.1fm Track)! Accelerating towards barrier...", trackDistanceMeters)
        
        trackRunTimer?.invalidate()
        trackRunTimer = Timer.scheduledTimer(withTimeInterval: 0.02, repeats: true) { [weak self] _ in
            guard let self = self, self.isDrivingMode, let startTime = self.trackRunStartTime else { return }
            let elapsed = Date().timeIntervalSince(startTime)
            self.liveTrackElapsedString = String(format: "%.3fs", elapsed)
            if elapsed > 0.05 {
                let v = (2.0 * self.trackDistanceMeters) / elapsed
                let a = (2.0 * self.trackDistanceMeters) / (elapsed * elapsed)
                self.liveTrackEstimatedSpeed = v
                self.liveTrackEstimatedAccel = a
                // Froude Kinematic Scaling: v_base = v_toy / sqrt(0.10)
                let vBase = v / sqrt(0.10)
                self.liveRealWorldSpeedKmh = vBase * 3.6
            }
        }
    }
    
    // Check recent driving telemetry samples from the running form before stopping
    private func checkRecentBrakingAndImpact() -> (hadImpact: Bool, hadHardBrake: Bool, peakDynG: Double, integratedDecel: Double) {
        let now = Date()
        let recent = recentDrivingSamples.filter { now.timeIntervalSince($0.timestamp) <= 1.2 }
        if recent.isEmpty {
            let wasRecentBrake = lastHardBrakingTimestamp != nil && now.timeIntervalSince(lastHardBrakingTimestamp!) <= 1.5
            return (false, wasRecentBrake, 0.0, 0.0)
        }
        
        let peakDynG = recent.map { $0.dynMagnitude }.max() ?? 0.0
        let peakTotalG = recent.map { $0.totalMagG }.max() ?? 0.0
        let peakLongitudinalG = recent.map { abs($0.ay) }.max() ?? 0.0
        
        // 1. Check for genuine collision impact shock (dynMagnitude >= 1.5G or totalMagG >= 2.0G)
        let hadImpact = peakDynG >= 1.5 || peakTotalG >= 2.0 || peakLongitudinalG >= 1.5
        
        // 2. Check for true hard braking deceleration without collision impact
        let integratedDecel = recent.reduce(0.0) { sum, item in
            sum + abs(item.ay) * 9.81 * 0.01
        }
        let peakGyro = recent.map { $0.gyroMagDegS }.max() ?? 0.0
        let wasRecentFlag = lastHardBrakingTimestamp != nil && now.timeIntervalSince(lastHardBrakingTimestamp!) <= 1.5
        let hadHardBrake = !hadImpact && (wasRecentFlag || ((integratedDecel >= 2.0 || peakLongitudinalG >= 0.5) && peakGyro < 120.0))
        
        return (hadImpact, hadHardBrake, peakDynG, integratedDecel)
    }
    
    // SCENARIO 2 MANUAL STOP AT DESTINATION:
    // Evaluates recent stored running telemetry:
    // 1. If impact shock detected -> reports ACCIDENT (computes force from speed/accel)
    // 2. If true hard braking detected -> reports HARD BRAKING (safe stop)
    // 3. Otherwise -> reports NO ACCIDENT (safe normal drive completed)
    func stopDriveAtDestination() {
        guard isDrivingMode, let start = trackRunStartTime else { return }
        let elapsed = Date().timeIntervalSince(start)
        isDrivingMode = false
        isTrackRunActive = false
        trackRunTimer?.invalidate()
        trackRunTimer = nil
        lastTrackElapsedTime = elapsed
        
        let (hadImpact, hadHardBrake, peakG, _) = checkRecentBrakingAndImpact()
        let coords = currentLocation ?? CLLocationCoordinate2D(latitude: 0, longitude: 0)
        let decelAccel = (2.0 * trackDistanceMeters) / max(elapsed * elapsed, 0.01)
        
        if hadImpact {
            // CASE 1: Vehicle hit barrier / obstacle at destination!
            liveTrackElapsedString = String(format: "%.3fs (Impact Shock)", elapsed)
            debugStatus = String(format: "💥 Barrier Hit: %.3fs across %.1fm (G=%.2f) — Calculating Force from Speed!", elapsed, trackDistanceMeters, peakG)
            logStateTransition(String(format: "💥 [STOPPING AT DESTINATION: BARRIER HIT] Detected impact shock (peakG=%.2f) on track run (t=%.3fs, d=%.1fm). Transmitting ACCIDENT.", peakG, elapsed, trackDistanceMeters))
            
            let (classifiedDirection, _) = classifyImpactDirection(ax: accelX, ay: accelY)
            sendImpact(
                acceleration: max(decelAccel, peakG * 9.81),
                coords: coords,
                detectedSide: classifiedDirection,
                dynX: accelX,
                dynY: accelY,
                dynZ: accelZ,
                gravX: gravityX,
                gravY: gravityY,
                gravZ: gravityZ,
                durationMs: 40.0,
                isPhoneFall: false,
                freeFallMs: 0.0,
                elapsedTimeSeconds: elapsed,
                trackDistanceMeters: trackDistanceMeters,
                isDrivingMode: true,
                isManualHardBrake: false // ACCIDENT!
            )
        } else if hadHardBrake {
            // CASE 2: Controlled Hard Braking before destination!
            liveTrackElapsedString = String(format: "%.3fs (Hard Brake)", elapsed)
            debugStatus = String(format: "🛑 Hard Braking at %.2fs across %.1fm (Vehicle Safe)", elapsed, trackDistanceMeters)
            logStateTransition(String(format: "🛑 [STOPPING AT DESTINATION: HARD BRAKE] Detected controlled deceleration on track run (t=%.3fs, d=%.1fm).", elapsed, trackDistanceMeters))
            
            sendImpact(
                acceleration: max(decelAccel, 9.81),
                coords: coords,
                detectedSide: "Hard Braking",
                dynX: accelX,
                dynY: accelY,
                dynZ: accelZ,
                gravX: gravityX,
                gravY: gravityY,
                gravZ: gravityZ,
                durationMs: max(elapsed * 1000.0, 40.0),
                isPhoneFall: false,
                freeFallMs: 0.0,
                elapsedTimeSeconds: elapsed,
                trackDistanceMeters: trackDistanceMeters,
                isDrivingMode: true,
                isManualHardBrake: true
            )
        } else {
            // CASE 3: Normal Driving Completed / No Accident!
            liveTrackElapsedString = String(format: "%.3fs (Safe Stop)", elapsed)
            debugStatus = String(format: "✅ Safe Run Completed: %.2fs across %.1fm (No Accident)", elapsed, trackDistanceMeters)
            logStateTransition(String(format: "✅ [STOPPING AT DESTINATION: NO ACCIDENT] Normal driving completed (t=%.3fs, d=%.1fm). No hard braking, no collision.", elapsed, trackDistanceMeters))
            
            sendImpact(
                acceleration: decelAccel,
                coords: coords,
                detectedSide: "No Accident",
                dynX: accelX,
                dynY: accelY,
                dynZ: accelZ,
                gravX: gravityX,
                gravY: gravityY,
                gravZ: gravityZ,
                durationMs: max(elapsed * 1000.0, 40.0),
                isPhoneFall: false,
                freeFallMs: 0.0,
                elapsedTimeSeconds: elapsed,
                trackDistanceMeters: trackDistanceMeters,
                isDrivingMode: true,
                isManualHardBrake: false
            )
        }
    }
    
    func stopDriveManualHardBrake() {
        stopDriveAtDestination()
    }
    
    func stopTrackRunManual() {
        stopDriveAtDestination()
    }

    
    func sendImpact(
        acceleration: Double,
        coords: CLLocationCoordinate2D,
        detectedSide: String = "Front",
        dynX: Double = 0,
        dynY: Double = 0,
        dynZ: Double = 0,
        gravX: Double = 0.0,
        gravY: Double = 0.0,
        gravZ: Double = 0.0,
        durationMs: Double = 40.0,
        isPhoneFall: Bool = false,
        freeFallMs: Double = 0.0,
        elapsedTimeSeconds: Double? = nil,
        trackDistanceMeters: Double? = nil,
        isDrivingMode: Bool? = nil,
        isManualHardBrake: Bool = false
    ) {
        let effectiveCarId = carId > 0 ? carId : 1
        
        let now = Date()
        if now.timeIntervalSince(lastSent) * 1000 < DEBOUNCE_MS { return }
        lastSent = now
        
        let isRollover = detectedSide.lowercased().contains("rollover")
        let isFall = !isRollover && (isPhoneFall || detectedSide.lowercased().contains("fall") || detectedSide.lowercased().contains("drop"))
        let isDrivingEdgeCase = !isRollover && !isFall && (isManualHardBrake || detectedSide.contains("Bump") || detectedSide.contains("Breaker") || detectedSide.contains("Braking") || detectedSide.contains("Drift") || detectedSide.contains("Cornering"))
        
        DispatchQueue.main.async {
            if isFall {
                self.debugStatus = "📱 Sending Phone Fall Edge Case…"
            } else if isManualHardBrake {
                self.debugStatus = "🛑 Transmitting Manual Hard Brake…"
            } else if isDrivingEdgeCase {
                self.debugStatus = "🛡️ Sending \(detectedSide) Edge Case…"
            } else if isRollover {
                self.debugStatus = "🔄 Sending Rollover Crash…"
            } else {
                self.debugStatus = "📡 Sending to API…"
            }
        }
        
        guard let url = URL(string: "\(API)/DetectAccident/ImpactCalculation") else { return }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let gForce = acceleration / 9.81
        let clientSeverity = gForce > 7.0 ? "High" : (gForce > 4.0 ? "Medium" : "Low")
        let isoFormatter = ISO8601DateFormatter()
        let timeIso = isoFormatter.string(from: now)
        
        let isNoAccident = detectedSide.contains("No Accident")
        
        let apiAccidentType: String
        if isRollover {
            apiAccidentType = "Rollover"
        } else if isFall {
            apiAccidentType = "Phone Fall"
        } else if isManualHardBrake {
            apiAccidentType = "Hard Braking"
        } else if isNoAccident {
            apiAccidentType = "No Accident"
        } else if isDrivingEdgeCase {
            apiAccidentType = detectedSide
        } else {
            apiAccidentType = "Impact"
        }
        
        let effectiveDrivingMode = isDrivingMode ?? self.isDrivingMode
        let effectiveTrackDistance = trackDistanceMeters ?? self.trackDistanceMeters
        let effectiveElapsed = elapsedTimeSeconds ?? (effectiveDrivingMode ? self.lastTrackElapsedTime : nil)
        
        var body: [String: Any] = [
            "CarId": effectiveCarId,
            "Car_Id": effectiveCarId,
            "AccidentType": apiAccidentType,
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
            "GravityX": gravX,
            "GravityY": gravY,
            "GravityZ": gravZ,
            "GyroX": gyroX,
            "GyroY": gyroY,
            "GyroZ": gyroZ,
            "Latitude": coords.latitude,
            "Longitude": coords.longitude,
            "Severity": isNoAccident ? "Safe (No Accident)" : ((isFall || isDrivingEdgeCase || isManualHardBrake) ? "Safe (Edge Case)" : (isRollover ? "High" : clientSeverity)),
            "Time": timeIso,
            "IsDrivingMode": effectiveDrivingMode,
            "Is_Driving_Mode": effectiveDrivingMode,
            "IsManualHardBrake": isManualHardBrake,
            "Is_Manual_Hard_Brake": isManualHardBrake
        ]
        
        if effectiveDrivingMode, let elapsed = effectiveElapsed, elapsed > 0 {
            body["ElapsedTimeSeconds"] = elapsed
            body["TrackDistanceMeters"] = effectiveTrackDistance
        }
        
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

                        let isEdgeCase = apiStatus == "EDGE_CASE" || apiStatus == "PHONE_FALL" || accidentType.contains("Fall") || accidentType.contains("Bump") || accidentType.contains("Breaker") || accidentType.contains("Braking") || accidentType.contains("Drift")

                        if let trackUsed = json["isTrackCalculationUsed"] as? Bool, trackUsed {
                            let tSec = json["elapsedTimeSeconds"] as? Double ?? (effectiveElapsed ?? 0.0)
                            let aCalc = json["calculatedTrackAccel"] as? Double ?? 0.0
                            let toySpeed = json["toyImpactSpeedMs"] as? Double
                            let realSpeedKmh = json["realWorldSpeedKmh"] as? Double
                            self.lastTrackAccel = aCalc
                            self.lastTrackGForce = aCalc / 9.81
                            self.lastToySpeedMs = toySpeed
                            self.lastRealWorldSpeedKmh = realSpeedKmh
                            
                            if let rSpeed = realSpeedKmh, let tSpeed = toySpeed {
                                self.debugStatus = String(format: "🏁 Crash: t=%.2fs | Toy=%.1fm/s | Real Speed=%.1f km/h | Force=%.0fN", tSec, tSpeed, rSpeed, impactForce)
                            } else {
                                self.debugStatus = String(format: "🏁 Track Run: t=%.2fs | a=%.2fm/s² (%.1fG) | Force=%.0fN", tSec, aCalc, aCalc / 9.81, impactForce)
                            }
                        } else if apiStatus == "PHONE_FALL" || accidentType.contains("Fall") {
                            self.debugStatus = String(format: "📱 Phone Fall Edge Case Detected! (Force=%.0fN | Vehicle Safe)", impactForce)
                        } else if accidentType.contains("Bump") || accidentType.contains("Breaker") {
                            self.debugStatus = String(format: "🚧 Speed Bump Edge Case Detected! (Force=%.0fN | Vehicle Safe)", impactForce)
                        } else if accidentType.contains("Braking") || accidentType.contains("Brake") {
                            self.debugStatus = String(format: "🛑 Hard Braking Edge Case Detected! (Force=%.0fN | Vehicle Safe)", impactForce)
                        } else if accidentType.contains("Drift") || accidentType.contains("Cornering") {
                            self.debugStatus = String(format: "🔄 Drift / Cornering Edge Case! (Force=%.0fN | Vehicle Safe)", impactForce)
                        } else if isEdgeCase {
                            self.debugStatus = String(format: "🛡️ %@ Edge Case! (Force=%.0fN | Vehicle Safe)", accidentType, impactForce)
                        } else if apiStatus == "ACCIDENT" {
                            // If API confirms an accident and timer was still ticking, stop it
                            if self.isDrivingMode || self.isTrackRunActive {
                                if let start = self.trackRunStartTime {
                                    let elapsed = Date().timeIntervalSince(start)
                                    self.lastTrackElapsedTime = elapsed
                                    self.liveTrackElapsedString = String(format: "%.3fs (Accident)", elapsed)
                                }
                                self.isDrivingMode = false
                                self.isTrackRunActive = false
                                self.trackRunTimer?.invalidate()
                                self.trackRunTimer = nil
                            }
                            self.debugStatus = String(format: "🚨 %@ [%@]! Force=%.0fN Damage=%.0f%%", accidentType.uppercased(), passengerSeverity.uppercased(), impactForce, cabinDamage)
                        } else if accidentType.contains("No Accident") || (apiStatus == "SAFE" && !accidentType.contains("Braking") && !isEdgeCase) {
                            self.debugStatus = String(format: "✅ No Accident: Safe Drive Completed (Force=%.0fN | 0%% Damage)", impactForce)
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
        let lr = ax // Left/Right axis
        let fb = ay // Front/Back axis
        let absLR = abs(lr)
        let absFB = abs(fb)
        let thetaRad = atan2(ay, ax)
        let thetaDeg = thetaRad * (180.0 / Double.pi)
        
        let direction: String
        if absLR < 0.3 && absFB < 0.3 {
            direction = "Minor"
        } else if absFB > absLR {
            if fb > 0 {
                direction = (absLR > 0.3) ? (lr > 0 ? "Front-Right" : "Front-Left") : "Front"
            } else {
                direction = (absLR > 0.3) ? (lr > 0 ? "Rear-Right" : "Rear-Left") : "Rear"
            }
        } else {
            direction = lr > 0 ? "Right" : "Left"
        }
        return (direction, thetaDeg)
    }
    
    /// Top Priority: Evaluates pre-impact rolling buffer for zero-g state (|a_total| < 0.40g for >= 50ms in the last 200ms buffer)
    /// Physics Principle: Airborne free-fall causes sensor weightlessness (< 0.40g). Ground vehicle impacts are never preceded by weightlessness.
    /// If AT LEAST 5 samples within the last 200ms buffer read |a_total| < 0.40g, returns isFreefall = true.
    private func checkWindowedFreefall(priorTo spikeTime: Date) -> (isFreefall: Bool, lowGSampleCount: Int, totalSamplesInWindow: Int, durationMs: Double) {
        // Filter rolling buffer readings in the 200ms window preceding the impact spike
        let windowReadings = imuBuffer.filter { reading in
            let delta = spikeTime.timeIntervalSince(reading.timestamp)
            return delta >= 0 && delta <= (FREEFALL_WINDOW_MS / 1000.0) // 200ms buffer window
        }
        
        let lowGSamples = windowReadings.filter { $0.totalAccelG < FREEFALL_ACC_THRESHOLD_G } // < 0.40g
        let lowGCount = lowGSamples.count
        let totalCount = windowReadings.count
        
        var durationMs: Double = 0.0
        if let earliest = lowGSamples.min(by: { $0.timestamp < $1.timestamp }),
           let latest = lowGSamples.max(by: { $0.timestamp < $1.timestamp }) {
            durationMs = abs(latest.timestamp.timeIntervalSince(earliest.timestamp)) * 1000.0 + 10.0
        }
        
        // Windowed counter requirement: AT LEAST 5 samples at 100 Hz (< 0.40g for >= 50ms) within 200ms window
        let isFreefall = lowGCount >= FREEFALL_MIN_SAMPLES
        return (isFreefall, lowGCount, totalCount, max(durationMs, Double(lowGCount) * 10.0))
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
        let now = Date()
        
        // ---------------------------------------------------------------------
        // STRICT PHASE 2 ROLLOVER BLOCK (PERSISTENT FREE-FALL LATCH)
        // ---------------------------------------------------------------------
        // Physics Principle: Free-fall precedes landing tumbling; vehicles on ground
        // do not experience pre-impact free-fall. If free-fall was latched within 3.0s,
        // any post-landing tilt/inversion (phi > 60°) is pure landing bounce/tumble noise.
        if (self.is_freefall_latched && now < self.freefall_latch_expiration) ||
           (self.is_freefall_locked && now < self.freefall_lockout_until) {
            let ratio = min(1.0, max(0.0, abs(totZ) / max(totalMagG, 0.0001)))
            let phiDeg = acos(ratio) * (180.0 / Double.pi)
            logStateTransition("🛡️ [FREE-FALL LATCH ACTIVE] Suppressing post-landing rollover check (a_total spike: \(String(format: "%.1f", totalMagG))g, tilt: \(String(format: "%.0f", phiDeg))° ignored).")
            in_phase_2 = false
            primary_event = nil
            impact_timestamp = nil
            phase2_settled_start_time = nil
            return // EXIT PHASE 2 IMMEDIATELY; DO NOT EVALUATE TILT ANGLE
        }
        
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
            gravX: motion.gravity.x,
            gravY: motion.gravity.y,
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
    
    func confirmAccident(
        dynX: Double,
        dynY: Double,
        dynZ: Double,
        gravX: Double = 0.0,
        gravY: Double = 0.0,
        gravZ: Double = 0.0,
        gyroX: Double,
        gyroY: Double,
        gyroZ: Double,
        acc: Double,
        durationMs: Double = 40.0,
        isPhoneFall: Bool = false,
        freeFallMs: Double = 0.0,
        rotatedPast90Deg: Bool = false,
        classifiedSide: String? = nil
    ) {
        let now = Date()
        if now.timeIntervalSince(lastSent) * 1000 < DEBOUNCE_MS { return }
        
        // Filter out extreme sensor resets (> 350 m/s²)
        if acc > 350 { return }
        
        let gyroMagnitude = sqrt(gyroX*gyroX + gyroY*gyroY + gyroZ*gyroZ)
        let detectedSide = classifiedSide ?? determineExactSide(dynX: dynX, dynY: dynY, dynZ: dynZ, gravZ: gravZ, gyroMag: gyroMagnitude, isPhoneFall: isPhoneFall, rotatedPast90Deg: rotatedPast90Deg)
        
        let isActuallyFall = isPhoneFall || detectedSide.contains("Fall") || detectedSide.contains("FALL") || detectedSide.contains("DROP")
        let isDrivingEdgeCase = detectedSide.contains("Bump") || detectedSide.contains("Breaker") || detectedSide.contains("Braking") || detectedSide.contains("Drift") || detectedSide.contains("Cornering")
        let isRealAccident = !isActuallyFall && !isDrivingEdgeCase
        
        // -------------------------------------------------------------------------
        // CRITICAL TIMER STOP POLICY:
        // The timer will stop after starting ONLY IF a verified accident happens!
        // If there is no accident (phone drop, speed bump, drift, normal driving),
        // the timer should NEVER stop on its own.
        // -------------------------------------------------------------------------
        var capturedElapsed: Double? = self.lastTrackElapsedTime
        let wasDrivingMode = self.isDrivingMode || self.isTrackRunActive
        
        if isRealAccident && wasDrivingMode {
            if let start = self.trackRunStartTime {
                let impactMoment = self.impact_timestamp ?? now
                let elapsed = max(0.01, impactMoment.timeIntervalSince(start))
                capturedElapsed = elapsed
                self.lastTrackElapsedTime = elapsed
                self.liveTrackElapsedString = String(format: "%.3fs (Accident Stopped)", elapsed)
            }
            self.isDrivingMode = false
            self.isTrackRunActive = false
            self.trackRunTimer?.invalidate()
            self.trackRunTimer = nil
            self.logStateTransition(String(format: "💥 [ACCIDENT CONFIRMED - TIMER STOPPED] Track run stopped at %.3fs across %.1fm for [%@]", capturedElapsed ?? 0.0, self.trackDistanceMeters, detectedSide))
        }
        
        if isActuallyFall {
            debugStatus = String(format: "📱 Phone Fall Edge Case: Acc=%.1f m/s² (FF=%.0fms)", acc, freeFallMs)
        } else {
            debugStatus = String(format: "🚨 Verified %@! Acc=%.1f m/s² (%.0fms)", detectedSide, acc, durationMs)
        }
        
        let coords = currentLocation ?? CLLocationCoordinate2D(latitude: 0, longitude: 0)
        sendImpact(
            acceleration: acc,
            coords: coords,
            detectedSide: detectedSide,
            dynX: dynX,
            dynY: dynY,
            dynZ: dynZ,
            gravX: gravX,
            gravY: gravY,
            gravZ: gravZ,
            durationMs: durationMs,
            isPhoneFall: isActuallyFall,
            freeFallMs: isActuallyFall ? freeFallMs : 0.0,
            elapsedTimeSeconds: capturedElapsed,
            trackDistanceMeters: self.trackDistanceMeters,
            isDrivingMode: wasDrivingMode,
            isManualHardBrake: false
        )
    }
    
    func startSensors() {
        self.lastAccel = 1.0
        self.prevAcc = 0
        self.shake = 0
        self.readCount = 0
        self.is_freefall_locked = false
        self.freefall_lockout_until = Date.distantPast
        self.is_freefall_latched = false
        self.freefall_latch_expiration = Date.distantPast
        self.impact_timestamp = nil
        self.primary_event = nil
        self.in_phase_2 = false
        self.phase2_settled_start_time = nil
        self.standalone_rollover_posture_start_time = nil
        self.standalone_rollover_rest_start_time = nil
        self.imuBuffer.removeAll()
        self.freefallStreakStartTime = nil
        self.lastQualifiedFreefallDurationMs = 0.0
        self.lastQualifiedFreefallEndTime = Date.distantPast
        self.hardBrakingWindow.removeAll()
        self.driftStreakStartTime = nil
        self.speedBumpFirstPeakTime = nil
        self.lastEdgeCaseSent = Date.distantPast
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
                
                // Track driving telemetry samples during active driving mode for stopping analysis
                if self.isDrivingMode || self.isTrackRunActive {
                    self.recentDrivingSamples.append(DrivingTelemetrySample(
                        timestamp: now,
                        ax: uX,
                        ay: uY,
                        az: uZ,
                        dynMagnitude: dynMagnitude,
                        totalMagG: totalMagG,
                        gyroMagDegS: gyroMagDegS
                    ))
                    self.recentDrivingSamples.removeAll { now.timeIntervalSince($0.timestamp) > 1.5 }
                }

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
                // 1. PERSISTENT FREE-FALL LATCH INTERLOCK (LOCKOUT ACTIVE CHECK)
                // =========================================================================
                // Physics Principle: Free-fall precedes landing tumbling; vehicles on ground
                // do not experience pre-impact free-fall. Ground vehicles stay grounded (1.0g
                // baseline) prior to collision impacts. Airborne drops produce weightlessness
                // (|a_total| < 0.40g for >= 50ms in the 200ms pre-impact buffer).
                // During the 3.0s latch window post-drop, all bounce spikes and rollover checks are blocked.
                if self.is_freefall_latched || self.is_freefall_locked {
                    self.standalone_rollover_posture_start_time = nil // Never accumulate rollover streak while drop lockout is active
                    self.standalone_rollover_rest_start_time = nil
                    if now < self.freefall_latch_expiration {
                        let ratio = min(1.0, max(0.0, abs(totZ) / max(totalMagG, 0.0001)))
                        let phiDeg = acos(ratio) * (180.0 / Double.pi)
                        
                        // Terminal demo logging: Prove post-landing tumbling is explicitly classified as drop noise
                        if totalMagG >= self.IMPACT_COLLISION_THRESHOLD_G || gyroMagDegS > 150.0 {
                            self.logStateTransition(String(format: "🛡️ [FREE-FALL LATCH ACTIVE] Suppressing post-landing rollover check (a_total spike: %.1fg, tilt: %.0f° ignored).", totalMagG, phiDeg))
                        }
                        
                        let remainingMs = self.freefall_latch_expiration.timeIntervalSince(now) * 1000.0
                        self.debugStatus = String(format: "🔒 Free-Fall Latch Active: %.0fms remaining (Drop Noise Filtered)", remainingMs)
                        return // Exit immediately for this frame — do not evaluate collision or rollover
                    } else {
                        self.is_freefall_latched = false
                        self.is_freefall_locked = false
                        self.logStateTransition("🔓 [FREE-FALL LATCH EXPIRED] 3.0s free-fall lockout completed. Vehicle crash detection re-armed.")
                    }
                }
                
                // =========================================================================
                // 2. PRE-IMPACT ROLLING BUFFER ZERO-G CHECK & PERSISTENT LATCH TRIGGER
                // =========================================================================
                // Check pre-impact rolling buffer for zero-g state (|a_total| < 0.40g for >= 50ms total in the last 200ms buffer).
                let (is_freefall_detected, lowGSampleCount, totalSamplesInWindow, dropDurationMs) = self.checkWindowedFreefall(priorTo: now)
                
                // When Free-Fall is identified (either at landing impact spike or during airborne zero-g):
                if is_freefall_detected && (!self.is_freefall_latched || now >= self.freefall_latch_expiration) {
                    // 1. Set is_freefall_latched = True
                    self.is_freefall_latched = true
                    // 2. Set freefall_latch_expiration = current_time + 3.0s (3-second window)
                    self.freefall_latch_expiration = now.addingTimeInterval(self.FREEFALL_LOCKOUT_MS / 1000.0) // 3.0s
                    self.is_freefall_locked = true
                    self.freefall_lockout_until = self.freefall_latch_expiration
                    
                    // Abort any in-progress Phase 2 or Standalone Rollover immediately
                    self.in_phase_2 = false
                    self.primary_event = nil
                    self.impact_timestamp = nil
                    self.phase2_settled_start_time = nil
                    self.standalone_rollover_posture_start_time = nil
                    self.standalone_rollover_rest_start_time = nil
                    
                    // 3. Output Event: "PHONE DROP / FALL DETECTED"
                    self.logStateTransition("⚠️ [PHONE DROP / FALL DETECTED] Pre-impact zero-g verified (|a_total| < 0.40g for \(lowGSampleCount)/\(totalSamplesInWindow) samples [\(String(format: "%.0f", dropDurationMs))ms] in last 200ms, spike: \(String(format: "%.1f", totalMagG))g). Persistent Free-Fall Latch set for 3.0s.")
                    self.debugStatus = String(format: "📱 PHONE DROP / FALL DETECTED (%d/%d low-g samples) — Latch 3.0s", lowGSampleCount, totalSamplesInWindow)
                    
                    // Transmit drop event telemetry to backend
                    let coords = self.currentLocation ?? CLLocationCoordinate2D(latitude: 0, longitude: 0)
                    self.sendImpact(
                        acceleration: max(totalMagG * 9.81, 9.81),
                        coords: coords,
                        detectedSide: "PHONE DROP / FALL DETECTED",
                        dynX: uX,
                        dynY: uY,
                        dynZ: uZ,
                        gravZ: gZ,
                        durationMs: max(dropDurationMs, 30.0),
                        isPhoneFall: true,
                        freeFallMs: dropDurationMs
                    )
                    
                    // Exit immediately for this frame — DO NOT pass execution to Phase 1 or Phase 2
                    return
                }
                
                // =========================================================================
                // PHASE 2: DYNAMIC MOTION SETTLEMENT & ROLLOVER VERIFICATION
                // =========================================================================
                if self.in_phase_2 {
                    // ---------------------------------------------------------------------
                    // STRICT PHASE 2 ROLLOVER BLOCK (INTERLOCK CONDITION AT VERY TOP)
                    // ---------------------------------------------------------------------
                    // Physics Principle: Free-fall precedes landing tumbling; vehicles on ground
                    // do not experience pre-impact free-fall. If free-fall was latched within 3.0s,
                    // any post-landing tilt/inversion (phi > 60°) is pure landing bounce/tumble noise.
                    if (self.is_freefall_latched && now < self.freefall_latch_expiration) ||
                       (self.is_freefall_locked && now < self.freefall_lockout_until) {
                        let ratio = min(1.0, max(0.0, abs(totZ) / max(totalMagG, 0.0001)))
                        let phiDeg = acos(ratio) * (180.0 / Double.pi)
                        self.logStateTransition(String(format: "🛡️ [FREE-FALL LATCH ACTIVE] Suppressing post-landing rollover check (a_total spike: %.1fg, tilt: %.0f° ignored).", totalMagG, phiDeg))
                        self.in_phase_2 = false
                        self.primary_event = nil
                        self.impact_timestamp = nil
                        self.phase2_settled_start_time = nil
                        return // EXIT PHASE 2 IMMEDIATELY; DO NOT EVALUATE TILT ANGLE
                    }
                    
                    guard let impactTime = self.impact_timestamp, let currentPrimary = self.primary_event else {
                        self.in_phase_2 = false
                        return
                    }
                    
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
                // VEHICLE COLLISION IMPACT SPIKE EVALUATION: PRIORITIES 2 & PHASE 1
                // =========================================================================
                let isTrackRunning = self.isDrivingMode || self.isTrackRunActive
                let collisionThreshold = isTrackRunning ? 1.5 : 2.5
                let totalThreshold = isTrackRunning ? 2.2 : self.IMPACT_COLLISION_THRESHOLD_G
                let isDirectionalTrackSpike = isTrackRunning && (abs(uY) >= 1.4 || abs(uX) >= 1.4)
                
                if totalMagG >= totalThreshold || dynMagnitude >= collisionThreshold || isDirectionalTrackSpike {
                    // Interlock: Persistent Free-Fall Latch blocks all vehicle collision checks
                    if (self.is_freefall_latched && now < self.freefall_latch_expiration) ||
                       (self.is_freefall_locked && now < self.freefall_lockout_until) {
                        return
                    }
                    
                    // Debounce check
                    if now.timeIntervalSince(self.lastSent) * 1000.0 < self.DEBOUNCE_MS { return }
                    
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
                
                // =========================================================================
                // STANDALONE / SCREEN ORIENTATION MATRIX ROLLOVER DETECTION (HANDHELD)
                // =========================================================================
                // Physics Principle:
                // - Path 1 (Impact-Induced): Vehicle crashes at speed (|a_total| >= 4.0g) and then
                //   tumbles into a rollover (verified via Phase 1 -> Phase 2 settlement).
                // - Path 2 (Standalone Handheld & Slow-Tip): Evaluates a Screen Orientation Matrix
                //   with a 35° tilt threshold and 150ms settlement window. Triggers reliably for
                //   lateral side-rolls (|ay| or |ax| > 0.45g), steep tilts (phi > 35°), and face-down turns (az > -0.30g).
                // Interlock: If Free-Fall is latched, standalone rollover is completely bypassed.
                if !self.is_freefall_latched && !self.is_freefall_locked && !self.in_phase_2 {
                    // Pure Apple CoreMotion Gravity Vector Check (Normalized 1.0g reference, prevents NaN / sign bugs)
                    let gx = motion.gravity.x
                    let gy = motion.gravity.y
                    let gz = motion.gravity.z
                    
                    // Pure Gravity Posture Check: Only genuine sideways roll (> 58°) or roof inversion
                    let isSideRolled = abs(gx) > 0.85 || abs(gy) > 0.85   // Rolled completely onto left/right/top edge
                    let isTiltedOrFlipped = gz > 0.20                      // Screen inverted face-down on roof
                    let isRolledOverState = isSideRolled || isTiltedOrFlipped
                    
                    // Safe posture angle calculation for display / telemetry (clamped to prevent NaN)
                    let safeGz = min(1.0, max(0.0, abs(gz)))
                    let phiDeg = acos(safeGz) * (180.0 / Double.pi)
                    
                    if isRolledOverState {
                        // 1. Posture Duration Tracker (Continuous time in rolled-over orientation)
                        if self.standalone_rollover_posture_start_time == nil {
                            self.standalone_rollover_posture_start_time = now
                        }
                        let postureDurationMs = now.timeIntervalSince(self.standalone_rollover_posture_start_time!) * 1000.0
                        
                        // 2. Resting / Quiet Arrival Tracker (||w|| < 45 deg/s in rolled-over orientation)
                        let isQuietRest = gyroMagDegS < self.STANDALONE_ROLLOVER_REST_GYRO_DEG_S
                        if isQuietRest {
                            if self.standalone_rollover_rest_start_time == nil {
                                self.standalone_rollover_rest_start_time = now
                            }
                        } else {
                            // Rotation still in progress during flip — reset rest timer, but DO NOT reset posture timer!
                            self.standalone_rollover_rest_start_time = nil
                        }
                        
                        let restDurationMs = self.standalone_rollover_rest_start_time != nil ?
                            now.timeIntervalSince(self.standalone_rollover_rest_start_time!) * 1000.0 : 0.0
                        
                        // Dual-Window Trigger Condition:
                        // Either arrived at rest (||w|| < 45 deg/s for >= 150ms) OR sustained posture for >= 250ms
                        let hasSettledAtRest = isQuietRest && (restDurationMs >= self.STANDALONE_ROLLOVER_MIN_REST_MS) // >= 150ms
                        let hasSustainedPosture = postureDurationMs >= self.STANDALONE_ROLLOVER_MAX_POSTURE_MS        // >= 250ms
                        
                        if hasSettledAtRest || hasSustainedPosture {
                            if now.timeIntervalSince(self.lastSent) * 1000.0 >= self.DEBOUNCE_MS {
                                // Output clear timestamped console logs for handheld rollover
                                self.logStateTransition(String(format: "🔄 [HANDHELD ROLLOVER DETECTED] Posture phi = %.1f° | gx = %.2fg | gy = %.2fg | gz = %.2fg (Settled for %.0fms).", phiDeg, gx, gy, gz, hasSettledAtRest ? restDurationMs : postureDurationMs))
                                
                                self.debugStatus = String(format: "🔄 ROLLOVER DETECTED (STATIC / SLOW TIPPED) | phi=%.0f°", phiDeg)
                                
                                // Trigger backend alert dispatch
                                self.confirmAccident(
                                    dynX: uX,
                                    dynY: uY,
                                    dynZ: uZ,
                                    gravX: gx,
                                    gravY: gy,
                                    gravZ: gz,
                                    gyroX: motion.rotationRate.x,
                                    gyroY: motion.rotationRate.y,
                                    gyroZ: motion.rotationRate.z,
                                    acc: max(totalMagG * 9.81, 9.81),
                                    durationMs: max(hasSettledAtRest ? restDurationMs : postureDurationMs, 150.0),
                                    isPhoneFall: false,
                                    freeFallMs: 0.0,
                                    classifiedSide: "ROLLOVER DETECTED (STATIC / SLOW TIPPED)"
                                )
                            }
                            
                            // Reset tracking variables after trigger to prevent multi-frame spam
                            self.standalone_rollover_posture_start_time = nil
                            self.standalone_rollover_rest_start_time = nil
                            return
                        } else {
                            if isQuietRest {
                                self.debugStatus = String(format: "🔄 Rollover Settling: phi=%.0f° (rest=%.0f/150ms)", phiDeg, restDurationMs)
                            } else {
                                self.debugStatus = String(format: "🔄 Rollover Motion: phi=%.0f° (||w||=%.0f°/s | %.0f/250ms)", phiDeg, gyroMagDegS, postureDurationMs)
                            }
                        }
                    } else {
                        // Phone is upright — reset both posture and resting timers
                        self.standalone_rollover_posture_start_time = nil
                        self.standalone_rollover_rest_start_time = nil
                    }
                } else {
                    self.standalone_rollover_posture_start_time = nil
                    self.standalone_rollover_rest_start_time = nil
                }
                
                // =========================================================================
                // [TIER 3: DRIVING DYNAMIC EDGE CASES — SECONDARY FILTER]
                // =========================================================================
                // Evaluate Tier 3 ONLY IF Tier 1 (Fall) and Tier 2 (Accidents) are ALL FALSE (dynMagnitude < 2.5G and totalGyro < 50 rad/s)
                let totalGyroRadS = sqrt(rX*rX + rY*rY + rZ*rZ)
                if !self.in_phase_2 && !self.is_freefall_locked && dynMagnitude < 2.5 && totalGyroRadS < 50.0 {
                    
                    // 3A. HARD BRAKING:
                    // Requires integrated longitudinal deceleration window (Sum(a_user_y * dt) >= 2.5 m/s)
                    // AND lateral force |a_user_x| < 0.6G
                    // AND total gyro ||gyro|| < 1.5 rad/s (prevents trigger when holding/tilting phone).
                    self.hardBrakingWindow.append((timestamp: now, ay: uY))
                    self.hardBrakingWindow.removeAll { now.timeIntervalSince($0.timestamp) > 0.50 }
                    
                    let integratedDecel = self.hardBrakingWindow.reduce(0.0) { sum, item in
                        sum + abs(item.ay) * 9.81 * 0.01
                    }
                    
                    let isHardBraking = integratedDecel >= 2.5 && abs(uX) < 0.6 && totalGyroRadS < 1.5
                    if isHardBraking {
                        self.lastHardBrakingTimestamp = now
                    }
                    if isHardBraking && now.timeIntervalSince(self.lastEdgeCaseSent) * 1000.0 >= self.EDGE_CASE_DEBOUNCE_MS {
                        self.lastEdgeCaseSent = now
                        self.logStateTransition(String(format: "🛑 [TIER 3: HARD BRAKING] Integrated decel = %.2f m/s >= 2.5 m/s, lateral |ax| = %.2fg < 0.6g, gyro = %.2f rad/s < 1.5 rad/s.", integratedDecel, abs(uX), totalGyroRadS))
                        self.debugStatus = String(format: "🛑 Hard Braking Edge Case (int=%.1fm/s)", integratedDecel)
                        let coords = self.currentLocation ?? CLLocationCoordinate2D(latitude: 0, longitude: 0)
                        self.sendImpact(
                            acceleration: max(abs(uY) * 9.81, 9.81),
                            coords: coords,
                            detectedSide: "Hard Braking",
                            dynX: uX,
                            dynY: uY,
                            dynZ: uZ,
                            gravX: gX,
                            gravY: gY,
                            gravZ: gZ,
                            durationMs: 250.0,
                            isPhoneFall: false
                        )
                        self.hardBrakingWindow.removeAll()
                        return
                    }
                    
                    // 3B. DRIFT / SHARP CORNERING:
                    // Requires sustained lateral dynamic acceleration |a_user_x| >= 1.2G for >= 300ms
                    // AND longitudinal dynamic force |a_user_y| >= 0.3G
                    // AND yaw rotation rate |GyroZ| >= 0.8 rad/s (confirms true vehicle turning).
                    let isDriftDynamics = abs(uX) >= 1.2 && abs(uY) >= 0.3 && abs(rZ) >= 0.8
                    if isDriftDynamics {
                        if self.driftStreakStartTime == nil {
                            self.driftStreakStartTime = now
                        }
                        let driftDurationMs = now.timeIntervalSince(self.driftStreakStartTime!) * 1000.0
                        if driftDurationMs >= 300.0 && now.timeIntervalSince(self.lastEdgeCaseSent) * 1000.0 >= self.EDGE_CASE_DEBOUNCE_MS {
                            self.lastEdgeCaseSent = now
                            self.logStateTransition(String(format: "🔄 [TIER 3: DRIFT / CORNERING] Sustained lateral |ax| = %.2fg >= 1.2g for %.0fms >= 300ms, yaw |rZ| = %.2f rad/s >= 0.8 rad/s.", abs(uX), driftDurationMs, abs(rZ)))
                            self.debugStatus = String(format: "🔄 Drift / Cornering Edge Case (%.1fg | %.0fms)", abs(uX), driftDurationMs)
                            let coords = self.currentLocation ?? CLLocationCoordinate2D(latitude: 0, longitude: 0)
                            self.sendImpact(
                                acceleration: max(abs(uX) * 9.81, 9.81),
                                coords: coords,
                                detectedSide: "Drift / Cornering",
                                dynX: uX,
                                dynY: uY,
                                dynZ: uZ,
                                gravX: gX,
                                gravY: gY,
                                gravZ: gZ,
                                durationMs: driftDurationMs,
                                isPhoneFall: false
                            )
                            self.driftStreakStartTime = nil
                            return
                        }
                    } else {
                        self.driftStreakStartTime = nil
                    }
                    
                    // 3C. SPEED BUMP:
                    // Requires 200ms vertical dynamic dual-peak wave (+Z >= 1.2G followed within 80-200ms by +Z >= 0.8G)
                    // AND horizontal dynamic force |a_user_x| < 0.8G and |a_user_y| < 0.8G.
                    let isLowHorizontalForBump = abs(uX) < 0.8 && abs(uY) < 0.8
                    if isLowHorizontalForBump {
                        if uZ >= 1.2 {
                            self.speedBumpFirstPeakTime = now
                        } else if let firstPeak = self.speedBumpFirstPeakTime {
                            let elapsedMs = now.timeIntervalSince(firstPeak) * 1000.0
                            if elapsedMs >= 80.0 && elapsedMs <= 200.0 && uZ >= 0.8 {
                                if now.timeIntervalSince(self.lastEdgeCaseSent) * 1000.0 >= self.EDGE_CASE_DEBOUNCE_MS {
                                    self.lastEdgeCaseSent = now
                                    self.logStateTransition(String(format: "🚧 [TIER 3: SPEED BUMP] Vertical dynamic dual-peak wave confirmed (+Z peak 1 >= 1.2g, peak 2 = %.2fg at %.0fms).", uZ, elapsedMs))
                                    self.debugStatus = String(format: "🚧 Speed Bump Edge Case (az=%.1fg | %.0fms)", uZ, elapsedMs)
                                    let coords = self.currentLocation ?? CLLocationCoordinate2D(latitude: 0, longitude: 0)
                                    self.sendImpact(
                                        acceleration: max(abs(uZ) * 9.81, 9.81),
                                        coords: coords,
                                        detectedSide: "Speed Bump",
                                        dynX: uX,
                                        dynY: uY,
                                        dynZ: uZ,
                                        gravX: gX,
                                        gravY: gY,
                                        gravZ: gZ,
                                        durationMs: elapsedMs,
                                        isPhoneFall: false
                                    )
                                    self.speedBumpFirstPeakTime = nil
                                    return
                                }
                            } else if elapsedMs > 200.0 {
                                self.speedBumpFirstPeakTime = nil
                            }
                        }
                    } else {
                        self.speedBumpFirstPeakTime = nil
                    }
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
                
                // =========================================================================
                // TOP DASHBOARD CONTROLS: DUAL-SCENARIO MODE (STATIONARY VS DRIVING)
                // =========================================================================
                VStack(spacing: 10) {
                    // Scenario Mode Status Header & Running Timer Badge
                    HStack {
                        HStack(spacing: 6) {
                            Circle()
                                .fill(viewModel.isDrivingMode ? Color.green : Color.blue)
                                .frame(width: 10, height: 10)
                            Text(viewModel.isDrivingMode ? "ACTIVE DRIVING MODE" : "STATIONARY / PARKED MODE")
                                .font(.system(size: 12, weight: .heavy))
                                .foregroundColor(viewModel.isDrivingMode ? .green : .blue)
                        }
                        
                        Spacer()
                        
                        if viewModel.isDrivingMode {
                            HStack(spacing: 5) {
                                HStack(spacing: 4) {
                                    Image(systemName: "timer")
                                        .font(.system(size: 11, weight: .bold))
                                    Text(viewModel.liveTrackElapsedString)
                                        .font(.system(size: 13, weight: .heavy, design: .monospaced))
                                }
                                .foregroundColor(.white)
                                .padding(.horizontal, 7)
                                .padding(.vertical, 3)
                                .background(Color.green)
                                .cornerRadius(6)
                                
                                if viewModel.liveRealWorldSpeedKmh > 0 {
                                    HStack(spacing: 3) {
                                        Image(systemName: "speedometer")
                                            .font(.system(size: 9, weight: .bold))
                                        Text(String(format: "%.1f km/h", viewModel.liveRealWorldSpeedKmh))
                                            .font(.system(size: 10, weight: .heavy, design: .monospaced))
                                    }
                                    .foregroundColor(.white)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 3)
                                    .background(Color.orange)
                                    .cornerRadius(6)
                                }
                            }
                        } else if let lastSpeed = viewModel.lastRealWorldSpeedKmh {
                            HStack(spacing: 4) {
                                if let lastTime = viewModel.lastTrackElapsedTime {
                                    HStack(spacing: 3) {
                                        Image(systemName: "flag.checkered")
                                            .font(.system(size: 9, weight: .bold))
                                        Text(String(format: "%.2fs", lastTime))
                                            .font(.system(size: 10, weight: .heavy, design: .monospaced))
                                    }
                                    .foregroundColor(.blue)
                                    .padding(.horizontal, 5)
                                    .padding(.vertical, 3)
                                    .background(Color.blue.opacity(0.12))
                                    .cornerRadius(5)
                                }
                                HStack(spacing: 3) {
                                    Image(systemName: "speedometer")
                                        .font(.system(size: 9, weight: .bold))
                                    Text(String(format: "%.1f km/h", lastSpeed))
                                        .font(.system(size: 10, weight: .heavy, design: .monospaced))
                                }
                                .foregroundColor(.purple)
                                .padding(.horizontal, 5)
                                .padding(.vertical, 3)
                                .background(Color.purple.opacity(0.12))
                                .cornerRadius(5)
                            }
                        } else if let lastTime = viewModel.lastTrackElapsedTime {
                            HStack(spacing: 4) {
                                Image(systemName: "flag.checkered")
                                    .font(.system(size: 10, weight: .bold))
                                Text(String(format: "Last: %.3fs", lastTime))
                                    .font(.system(size: 11, weight: .heavy, design: .monospaced))
                            }
                            .foregroundColor(.blue)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 3)
                            .background(Color.blue.opacity(0.12))
                            .cornerRadius(6)
                        } else {
                            Text("IMU Sensor Mode")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundColor(.secondary)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 3)
                                .background(Color(white: 0.90))
                                .cornerRadius(6)
                        }
                    }
                    
                    // Fixed Prominent Action Buttons (Side by Side)
                    HStack(spacing: 10) {
                        // "Start Drive Run (4m Track)" - Green / Active
                        Button(action: {
                            viewModel.startDriveRun()
                        }) {
                            HStack(spacing: 6) {
                                Image(systemName: "play.circle.fill")
                                    .font(.system(size: 16))
                                Text(String(format: "Start Drive (%.1fm)", viewModel.trackDistanceMeters))
                                    .font(.system(size: 13, weight: .bold))
                            }
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .background(
                                viewModel.isDrivingMode
                                    ? LinearGradient(gradient: Gradient(colors: [Color.gray.opacity(0.5), Color.gray.opacity(0.4)]), startPoint: .leading, endPoint: .trailing)
                                    : LinearGradient(gradient: Gradient(colors: [Color(red: 46/255, green: 180/255, blue: 80/255), Color(red: 35/255, green: 160/255, blue: 70/255)]), startPoint: .leading, endPoint: .trailing)
                            )
                            .cornerRadius(12)
                            .shadow(color: viewModel.isDrivingMode ? Color.clear : Color.green.opacity(0.3), radius: 4, x: 0, y: 2)
                        }
                        .disabled(viewModel.isDrivingMode)
                        
                        // "Stop Drive Run" - Red / Enabled only when driving
                        Button(action: {
                            viewModel.stopDriveAtDestination()
                        }) {
                            HStack(spacing: 6) {
                                Image(systemName: "stop.circle.fill")
                                    .font(.system(size: 15))
                                Text("Stop Drive Run")
                                    .font(.system(size: 13, weight: .bold))
                            }
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .background(
                                viewModel.isDrivingMode
                                    ? LinearGradient(gradient: Gradient(colors: [Color(red: 225/255, green: 45/255, blue: 45/255), Color(red: 195/255, green: 30/255, blue: 30/255)]), startPoint: .leading, endPoint: .trailing)
                                    : LinearGradient(gradient: Gradient(colors: [Color.gray.opacity(0.35), Color.gray.opacity(0.25)]), startPoint: .leading, endPoint: .trailing)
                            )
                            .cornerRadius(12)
                            .shadow(color: viewModel.isDrivingMode ? Color.red.opacity(0.35) : Color.clear, radius: 4, x: 0, y: 2)
                        }
                        .disabled(!viewModel.isDrivingMode)
                    }
                    
                    // Track Distance Input Box & Quick Presets
                    HStack(spacing: 6) {
                        Image(systemName: "ruler.fill")
                            .font(.system(size: 11))
                            .foregroundColor(.blue)
                        Text("Track Distance:")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(.primary)
                        
                        TextField("4.0", text: $viewModel.trackDistanceInput)
                            .keyboardType(.decimalPad)
                            .font(.system(size: 12, weight: .bold, design: .monospaced))
                            .multilineTextAlignment(.center)
                            .frame(width: 48, height: 24)
                            .background(Color(white: 0.92))
                            .cornerRadius(5)
                            .disabled(viewModel.isDrivingMode)
                            .onChange(of: viewModel.trackDistanceInput) { newVal in
                                viewModel.updateTrackDistance(newVal)
                            }
                        Text("m")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundColor(.secondary)
                        
                        Spacer()
                        
                        HStack(spacing: 3) {
                            ForEach(["2.0", "4.0", "6.0"], id: \.self) { preset in
                                Button(action: {
                                    viewModel.updateTrackDistance(preset)
                                }) {
                                    Text("\(preset)m")
                                        .font(.system(size: 9, weight: .bold))
                                        .padding(.horizontal, 5)
                                        .padding(.vertical, 2)
                                        .background(viewModel.trackDistanceInput == preset ? Color.blue : Color(white: 0.88))
                                        .foregroundColor(viewModel.trackDistanceInput == preset ? .white : .primary)
                                        .cornerRadius(4)
                                }
                                .disabled(viewModel.isDrivingMode)
                            }
                        }
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color(white: 0.96))
                    .cornerRadius(6)
                }
                .padding(12)
                .background(Color.white)
                .cornerRadius(14)
                .shadow(color: Color.black.opacity(0.05), radius: 4, x: 0, y: 2)
                .padding(.bottom, 2)
                
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
                    let isSpeedBump = sd.accidentType.contains("Bump") || sd.accidentType.contains("Breaker")
                    let isHardBraking = sd.accidentType.contains("Braking") || sd.accidentType.contains("Brake")
                    let isDrift = sd.accidentType.contains("Drift") || sd.accidentType.contains("Cornering")
                    let isDrivingEdgeCase = isSpeedBump || isHardBraking || isDrift
                    let isAnyEdgeCase = isPhoneFall || isDrivingEdgeCase || sd.status == "EDGE_CASE"
                    let isAccident = sd.status == "ACCIDENT"
                    
                    let bannerIcon: String = {
                        if isAccident { return "exclamationmark.triangle.fill" }
                        if isPhoneFall { return "arrow.down.to.line.compact" }
                        if isSpeedBump { return "arrow.up.and.down.and.sparkles" }
                        if isHardBraking { return "exclamationmark.octagon.fill" }
                        if isDrift { return "arrow.triangle.swap" }
                        if isAnyEdgeCase { return "shield.lefthalf.filled" }
                        return "checkmark.shield.fill"
                    }()
                    
                    let bannerTitle: String = {
                        if isAccident { return "🚨 \(sd.accidentType.uppercased()) DETECTED" }
                        if isPhoneFall { return "📱 PHONE FALL DETECTED (EDGE CASE)" }
                        if isSpeedBump { return "🚧 SPEED BUMP DETECTED (EDGE CASE)" }
                        if isHardBraking { return "🛑 HARD BRAKING DETECTED (EDGE CASE)" }
                        if isDrift { return "🔄 DRIFT / SHARP TURN (EDGE CASE)" }
                        if isAnyEdgeCase { return "🛡️ \(sd.accidentType.uppercased()) (EDGE CASE)" }
                        return "✅ Safe — No Accident"
                    }()
                    
                    let bannerSubtitle: String = {
                        if isPhoneFall { return "Non-collision phone drop filtered with zero vehicle damage." }
                        if isSpeedBump { return "Vertical road hump pitch rotation isolated with zero vehicle damage." }
                        if isHardBraking { return "Normal emergency ABS stopping dynamics isolated with zero vehicle damage." }
                        if isDrift { return "Lateral cornering dynamics isolated with zero vehicle damage." }
                        if isAnyEdgeCase { return "Non-collision driving dynamic isolated with zero vehicle damage." }
                        return ""
                    }()
                    
                    HStack(spacing: 12) {
                        Image(systemName: bannerIcon)
                            .font(.system(size: 24))
                            .foregroundColor(.white)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(bannerTitle)
                                .bold()
                                .foregroundColor(.white)
                            if isAccident || isAnyEdgeCase {
                                HStack(spacing: 8) {
                                    if let sev = sd.passengerSeverity ?? sd.severity {
                                        Text(isAnyEdgeCase ? "Edge Case: 0% Damage" : "Severity: \(sev)")
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
                            
                            if !bannerSubtitle.isEmpty {
                                Text(bannerSubtitle)
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
                    .background(isAccident ? Color.red : (isAnyEdgeCase ? Color.orange : Color(red: 0.1, green: 0.7, blue: 0.3)))
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
                    if let realSpeed = viewModel.lastRealWorldSpeedKmh, realSpeed > 0 {
                        InfoCard(
                            title: "Real Vehicle Speed",
                            value: String(format: "%.1f km/h", realSpeed),
                            sub: String(format: "Toy: %.1fm/s (Froude 1:10)", viewModel.lastToySpeedMs ?? 0.0),
                            highlight: viewModel.sensorData?.status == "ACCIDENT"
                        )
                    }
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
                
                // =========================================================================
                // 4-METER / CUSTOM TEST TRACK RUN CONTROLS (COMMITTEE DEMO)
                // =========================================================================
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        HStack(spacing: 8) {
                            ZStack {
                                Circle()
                                    .fill(viewModel.isTrackRunActive ? Color.green.opacity(0.2) : Color.blue.opacity(0.15))
                                    .frame(width: 24, height: 24)
                                Image(systemName: viewModel.isTrackRunActive ? "timer" : "flag.checkered")
                                    .font(.system(size: 12, weight: .bold))
                                    .foregroundColor(viewModel.isTrackRunActive ? .green : .blue)
                            }
                            Text("TEST TRACK ACCELERATION RUN")
                                .font(.system(size: 13, weight: .bold))
                                .foregroundColor(.primary)
                        }
                        Spacer()
                        Text(String(format: "d = %.1fm", viewModel.trackDistanceMeters))
                            .font(.system(size: 12, weight: .bold, design: .monospaced))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(Color.blue.opacity(0.12))
                            .foregroundColor(.blue)
                            .cornerRadius(6)
                    }
                    
                    // Destination Distance Input Text Box & Quick Presets
                    HStack(spacing: 8) {
                        Image(systemName: "ruler.fill")
                            .font(.system(size: 12))
                            .foregroundColor(.blue)
                        
                        Text("Destination Distance:")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(.primary)
                        
                        Spacer()
                        
                        HStack(spacing: 4) {
                            TextField("4.0", text: $viewModel.trackDistanceInput)
                                .keyboardType(.decimalPad)
                                .font(.system(size: 13, weight: .bold, design: .monospaced))
                                .multilineTextAlignment(.center)
                                .frame(width: 55, height: 28)
                                .background(Color(white: 0.92))
                                .cornerRadius(6)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 6)
                                        .stroke(viewModel.isTrackRunActive ? Color.green : Color.blue.opacity(0.4), lineWidth: 1)
                                )
                                .disabled(viewModel.isTrackRunActive)
                                .onChange(of: viewModel.trackDistanceInput) { newVal in
                                    viewModel.updateTrackDistance(newVal)
                                }
                            
                            Text("m")
                                .font(.system(size: 12, weight: .bold))
                                .foregroundColor(.secondary)
                        }
                        
                        // Preset Buttons
                        HStack(spacing: 4) {
                            ForEach(["2.0", "4.0", "6.0"], id: \.self) { preset in
                                Button(action: {
                                    viewModel.updateTrackDistance(preset)
                                }) {
                                    Text("\(preset)m")
                                        .font(.system(size: 10, weight: .bold))
                                        .padding(.horizontal, 5)
                                        .padding(.vertical, 3)
                                        .background(viewModel.trackDistanceInput == preset ? Color.blue : Color(white: 0.88))
                                        .foregroundColor(viewModel.trackDistanceInput == preset ? .white : .primary)
                                        .cornerRadius(5)
                                }
                                .disabled(viewModel.isTrackRunActive)
                            }
                        }
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Color(white: 0.97))
                    .cornerRadius(8)
                    
                    // Metrics Row (Elapsed Time, Velocity, Acceleration)
                    HStack(spacing: 8) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("ELAPSED TIME")
                                .font(.system(size: 9, weight: .bold))
                                .foregroundColor(.secondary)
                            Text(viewModel.liveTrackElapsedString)
                                .font(.system(size: 16, weight: .heavy, design: .monospaced))
                                .foregroundColor(viewModel.isTrackRunActive ? .green : .primary)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        
                        Divider().frame(height: 28)
                        
                        VStack(alignment: .leading, spacing: 2) {
                            Text("IMPACT SPEED")
                                .font(.system(size: 9, weight: .bold))
                                .foregroundColor(.secondary)
                            Text(String(format: "%.2f m/s", viewModel.liveTrackEstimatedSpeed))
                                .font(.system(size: 13, weight: .bold, design: .monospaced))
                                .foregroundColor(.primary)
                            Text(String(format: "%.1f km/h", viewModel.liveTrackEstimatedSpeed * 3.6))
                                .font(.system(size: 9, weight: .medium))
                                .foregroundColor(.secondary)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        
                        Divider().frame(height: 28)
                        
                        VStack(alignment: .leading, spacing: 2) {
                            Text("CALC ACCEL / G")
                                .font(.system(size: 9, weight: .bold))
                                .foregroundColor(.secondary)
                            Text(String(format: "%.1fm/s²", viewModel.liveTrackEstimatedAccel))
                                .font(.system(size: 13, weight: .bold, design: .monospaced))
                                .foregroundColor(.primary)
                            Text(String(format: "%.2f G", viewModel.liveTrackEstimatedAccel / 9.81))
                                .font(.system(size: 9, weight: .bold))
                                .foregroundColor(.orange)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .padding(10)
                    .background(Color(white: 0.96))
                    .cornerRadius(10)
                    
                    // Control Action Buttons
                    if !viewModel.isTrackRunActive {
                        Button(action: {
                            viewModel.startTrackRun()
                        }) {
                            HStack(spacing: 8) {
                                Image(systemName: "play.circle.fill")
                                    .font(.system(size: 16))
                                Text(String(format: "Start Track Run (%.1fm)", viewModel.trackDistanceMeters))
                                    .font(.system(size: 14, weight: .bold))
                            }
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .background(LinearGradient(gradient: Gradient(colors: [Color.blue, Color(red: 0/255, green: 130/255, blue: 230/255)]), startPoint: .leading, endPoint: .trailing))
                            .cornerRadius(12)
                            .shadow(color: Color.blue.opacity(0.3), radius: 4, x: 0, y: 2)
                        }
                    } else {
                        HStack(spacing: 8) {
                            HStack(spacing: 6) {
                                ProgressView()
                                    .scaleEffect(0.75)
                                Text("Auto-stops at G ≥ 1.5G")
                                    .font(.system(size: 11, weight: .medium))
                                    .foregroundColor(.green)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            
                            Button(action: {
                                viewModel.stopTrackRunManual()
                            }) {
                                HStack(spacing: 6) {
                                    Image(systemName: "hand.raised.fill")
                                        .font(.system(size: 13))
                                    Text("Stop / Hard Brake")
                                        .font(.system(size: 12, weight: .bold))
                                }
                                .foregroundColor(.white)
                                .padding(.horizontal, 14)
                                .padding(.vertical, 10)
                                .background(Color.red)
                                .cornerRadius(10)
                                .shadow(color: Color.red.opacity(0.25), radius: 3, x: 0, y: 2)
                            }
                        }
                    }
                }
                .padding(15)
                .background(Color.white)
                .cornerRadius(15)
                .shadow(color: Color.black.opacity(0.04), radius: 5, x: 0, y: 2)
                .padding(.top, 4)
                
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
