
import SwiftUI
import CoreMotion
import CoreLocation
import Combine

class AccidentDetector: NSObject, ObservableObject, CLLocationManagerDelegate {

    // ================= API =================
    let API = AppConfig.apiBaseURL

    // ================= MOTION =================
    private let motionManager = CMMotionManager()
    private let locationManager = CLLocationManager()

    // ================= STATE =================
    @Published var impactSide: String = "-"
    @Published var force: String = "OFF"
    @Published var cabinDamage: Double = 0
    @Published var status: String = "SAFE"
    @Published var lastEvent: String = "-"
    
    @Published var accelX: Double = 0
    @Published var accelY: Double = 0
    @Published var accelZ: Double = 0
    
    @Published var gyroX: Double = 0
    @Published var gyroY: Double = 0
    @Published var gyroZ: Double = 0
    
    @Published var latitude: Double = 0
    @Published var longitude: Double = 0

    // ================= INTERNAL =================
    var lastAccel = 0.0
    var prevAcc = 0.0
    var shake = 0.0
    var lastSent: TimeInterval = 0
    var readCount = 0 
    var confirm = 0
    var gravity = (x: 0.0, y: 0.0, z: 0.0)
    var gyro = (x: 0.0, y: 0.0, z: 0.0)

    let ACCEL_THRESHOLD = 0.5
    let SHAKE_THRESHOLD = 11.0
    let DEBOUNCE = 3.0
    let WARMUP = 15

    var currentLocation: CLLocation?

    override init() {
        super.init()
        locationManager.delegate = self
        locationManager.requestWhenInUseAuthorization()
        locationManager.startUpdatingLocation()
    }

    // ================= LOCATION =================
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        if let loc = locations.last {
            currentLocation = loc
            DispatchQueue.main.async {
                self.latitude = loc.coordinate.latitude
                self.longitude = loc.coordinate.longitude
            }
        }
    }

    // ================= START =================
    func start() {
        motionManager.accelerometerUpdateInterval = 0.1
        motionManager.gyroUpdateInterval = 0.1

        motionManager.startAccelerometerUpdates(to: .main) { data, _ in
            guard let d = data else { return }

            let x = d.acceleration.x * 9.8
            let y = d.acceleration.y * 9.8
            let z = d.acceleration.z * 9.8

            self.accelX = d.acceleration.x
            self.accelY = d.acceleration.y
            self.accelZ = d.acceleration.z

            self.handleAccelerometer(x: x, y: y, z: z)
        }

        motionManager.startGyroUpdates(to: .main) { data, _ in
            guard let g = data else { return }
            self.gyro = (g.rotationRate.x, g.rotationRate.y, g.rotationRate.z)
            self.gyroX = g.rotationRate.x
            self.gyroY = g.rotationRate.y
            self.gyroZ = g.rotationRate.z
        }
    }

    // ================= DETECTION =================
    func handleAccelerometer(x: Double, y: Double, z: Double) {

        let current = x*x + y*y + z*z
        let delta = abs(current - lastAccel)

        shake = max(delta, shake * 0.6)
        lastAccel = current

        if shake > SHAKE_THRESHOLD {
            confirmAccident(x: x, y: y, z: z)
        }
    }

    func confirmAccident(x: Double, y: Double, z: Double) {

        readCount += 1
        if readCount < WARMUP { return }

        let alpha = 0.8

        gravity.x = alpha * gravity.x + (1 - alpha) * x
        gravity.y = alpha * gravity.y + (1 - alpha) * y
        gravity.z = alpha * gravity.z + (1 - alpha) * z

        let linX = x - gravity.x
        let linY = y - gravity.y
        let linZ = z - gravity.z

        let acc = sqrt(linX*linX + linY*linY + linZ*linZ)

        if acc > 25 { return }

        let jerk = abs(acc - prevAcc)
        prevAcc = acc

        let directional = max(abs(linX), abs(linY))

        if acc > ACCEL_THRESHOLD && jerk > 2 && directional > 1.5 {
            confirm += 1
            if confirm < 2 { return }
        } else {
            confirm = 0
            return
        }

        sendImpact(acc: acc, linX: linX, linY: linY, linZ: linZ)
        confirm = 0
    }

    // ================= SPECIAL CASE =================
    func detectSpecial(linX: Double, linY: Double, linZ: Double) -> String? {
        let rotation = abs(gyro.x) + abs(gyro.y) + abs(gyro.z)
        let vertical = abs(linZ)

        if rotation > 5.5 { return "rollover" }
        if vertical > 11 && abs(linX) < 3 && abs(linY) < 3 { return "fall" }

        return nil
    }

    // ================= API =================
    func sendImpact(acc: Double, linX: Double, linY: Double, linZ: Double) {

        let now = Date().timeIntervalSince1970
        if now - lastSent < DEBOUNCE { return }
        lastSent = now

        guard let loc = currentLocation else { return }

        guard let url = URL(string: "\(API)/DetectAccident/ImpactCalculation") else {
            print("❌ Invalid URL")
            return
        }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body: [String: Any] = [
            "Car_Id": 1,
            "Acceleration": acc,
            "GyroX": linX,
            "GyroY": linY,
            "Latitude": loc.coordinate.latitude,
            "Longitude": loc.coordinate.longitude
        ]

        req.httpBody = try? JSONSerialization.data(withJSONObject: body)

        URLSession.shared.dataTask(with: req) { data, _, _ in
            guard let data = data else { return }

            if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {

                DispatchQueue.main.async {

                    let damage = json["cabinDamage"] as? Double ?? 0
                    let impact = json["impactForce"] as? Double ?? 0

                    let special = self.detectSpecial(linX: linX, linY: linY, linZ: linZ)
                    let side = special ?? (json["impactSide"] as? String ?? "-")

                    self.impactSide = side
                    self.force = impact > 0 ? "ON" : "OFF"
                    self.cabinDamage = damage
                    self.status = impact > 0 ? "ACCIDENT" : "SAFE"
                    self.lastEvent = Date().formatted()
                }
            }
        }.resume()
    }
}
// ================= UI VIEW =================

struct MonitoringView: View {

    @StateObject var detector = AccidentDetector()

    var body: some View {
        ScrollView {

            VStack(spacing: 15) {

                // STATUS
                Text(detector.status == "ACCIDENT"
                     ? "🚨 Accident Detected"
                     : "✅ Monitoring (Safe)")
                    .font(.title3.weight(.bold))

                // INFO BLOCK
                VStack(spacing: 10) {
                    Text("Impact Side: \(detector.impactSide)")
                    Text("Force: \(detector.force)")
                    Text("Damage: \(Int(detector.cabinDamage))%")
                    Text("Last Event: \(detector.lastEvent)")
                }
                .padding()
                .background(Color.white)
                .cornerRadius(12)
                .shadow(radius: 2)

                // Real-time Sensors Section
                VStack(alignment: .leading, spacing: 10) {
                    Text("Real-time Sensors").font(.body.weight(.bold)).padding(.bottom, 5)
                    
                    VStack(spacing: 8) {
                        SensorRow(label: "Accelerometer (G)", x: detector.accelX, y: detector.accelY, z: detector.accelZ)
                        Divider()
                        SensorRow(label: "Gyroscope (rad/s)", x: detector.gyroX, y: detector.gyroY, z: detector.gyroZ)
                        Divider()
                        HStack {
                            VStack(alignment: .leading) {
                                Text("GPS Coordinates").font(.caption).foregroundColor(.gray)
                                Text(String(format: "Lat: %.6f, Lon: %.6f", detector.latitude, detector.longitude))
                                    .font(.system(size: 14, weight: .medium, design: .monospaced))
                            }
                            Spacer()
                        }
                    }
                    .padding(15).background(Color.white).cornerRadius(15)
                    .shadow(radius: 2)
                }

            }
            .padding()
        }
        .background(Color(.systemGray6))

        // 🚀 START REAL-TIME DETECTION
        .onAppear {
            detector.start()
        }
    }
}


// ================= PREVIEW =================

struct MonitoringView_Previews: PreviewProvider {
    static var previews: some View {
        MonitoringView()
    }
}

