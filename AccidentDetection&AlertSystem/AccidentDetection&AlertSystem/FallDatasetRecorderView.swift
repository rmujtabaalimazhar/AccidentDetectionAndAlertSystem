//
//  FallDatasetRecorderView.swift
//  AccidentDetection&AlertSystem
//
//  Multi-Scenario Dataset Recorder (Phone Fall & Vehicle Rollover Kinematics)
//

import SwiftUI
import CoreMotion
import Combine
import UniformTypeIdentifiers
import AudioToolbox

// MARK: - Dataset Recording Modes

enum DatasetRecordingMode: String, CaseIterable, Identifiable {
    case fall = "Fall Drops"
    case rollover = "Rollover Flips"
    
    var id: String { rawValue }
    
    var icon: String {
        switch self {
        case .fall: return "arrow.down.to.line.compact"
        case .rollover: return "arrow.triangle.2.circlepath"
        }
    }
}

// MARK: - Models for Sensor Capture

struct SensorSample: Codable, Identifiable {
    var id: String = UUID().uuidString
    let timestampMs: Double
    let timeIso: String
    
    // Dynamic Linear Acceleration (Gravity isolated)
    let linearAccelX: Double
    let linearAccelY: Double
    let linearAccelZ: Double
    let linearAccelMagMps2: Double
    let linearAccelMagG: Double
    
    // Total Acceleration (Raw including Gravity)
    let totalAccelX: Double
    let totalAccelY: Double
    let totalAccelZ: Double
    let totalAccelMagG: Double
    
    // Gravity Components
    let gravityX: Double
    let gravityY: Double
    let gravityZ: Double
    
    // Gyroscope / Angular Velocity
    let gyroX: Double
    let gyroY: Double
    let gyroZ: Double
    let gyroMagRads: Double
    
    // Physical state flags
    let isFreeFallState: Bool
    let isRolloverState: Bool
}

struct KineticEvent: Codable, Identifiable {
    var id: String = UUID().uuidString
    let eventType: String // "Drop Impact" or "Rollover Flip"
    let eventTimeIso: String
    let elapsedMs: Double
    let peakLinearMps2: Double
    let peakTotalG: Double
    let peakGyroRads: Double
    let durationMs: Double
    let dominantAxis: String
    let label: String
}

struct RecordedSession: Codable, Identifiable {
    var id: String = UUID().uuidString
    let sessionName: String
    let mode: String
    let label: String
    let startTime: String
    let endTime: String
    let durationSeconds: Double
    let sampleRateHz: Double
    let totalSamples: Int
    let peakLinearMps2: Double
    let peakTotalG: Double
    let peakGyroRads: Double
    let detectedEventsCount: Int
    let events: [KineticEvent]
    let samples: [SensorSample]
}

// MARK: - View Model for Sensor Capture

class DatasetRecorderViewModel: NSObject, ObservableObject {
    private let motionManager = CMMotionManager()
    
    // Current Mode
    @Published var recordingMode: DatasetRecordingMode = .fall {
        didSet {
            if recordingMode == .rollover {
                selectedLabel = predefinedRolloverLabels.first ?? "Lateral Rollover (360°)"
                liveStatusMessage = "Ready to record vehicle rollover dynamics"
            } else {
                selectedLabel = predefinedFallLabels.first ?? "Free Fall Drop (1m)"
                liveStatusMessage = "Ready to record phone drop dynamics"
            }
        }
    }
    
    // Recording state
    @Published var isRecording: Bool = false
    @Published var recordingDuration: Double = 0.0
    @Published var sampleCount: Int = 0
    @Published var selectedLabel: String = "Free Fall Drop (1m)"
    
    // Real-time live sensor metrics
    @Published var currentLinearMps2: Double = 0.0
    @Published var currentLinearG: Double = 0.0
    @Published var currentTotalG: Double = 0.0
    @Published var currentGyroRads: Double = 0.0
    @Published var currentLinX: Double = 0.0
    @Published var currentLinY: Double = 0.0
    @Published var currentLinZ: Double = 0.0
    @Published var currentGravZ: Double = -1.0
    @Published var currentGyroX: Double = 0.0
    @Published var currentGyroY: Double = 0.0
    @Published var currentGyroZ: Double = 0.0
    
    // Peak tracking for current session
    @Published var sessionPeakLinearMps2: Double = 0.0
    @Published var sessionPeakTotalG: Double = 0.0
    @Published var sessionPeakGyroRads: Double = 0.0
    @Published var isCurrentlyInFreeFall: Bool = false
    @Published var isCurrentlyRollingOver: Bool = false
    @Published var liveStatusMessage: String = "Ready to record"
    
    // Detected events during active session
    @Published var currentSessionEvents: [KineticEvent] = []
    
    // History of all sessions
    @Published var savedSessions: [RecordedSession] = []
    
    // Internal buffers
    private var activeSamples: [SensorSample] = []
    private var sessionStartTime: Date? = nil
    private var durationTimer: AnyCancellable? = nil
    
    // Fall state machine tracking
    private var freeFallStartTime: Date? = nil
    private var freeFallDurationMs: Double = 0.0
    private var lastImpactTime: Date = Date.distantPast
    
    // Rollover state machine tracking
    private var rolloverStartTime: Date? = nil
    private var lastRolloverEventTime: Date = Date.distantPast
    
    // Detection threshold parameters
    private let FREEFALL_TOTAL_G_THRESHOLD: Double = 0.40  // Near zero gravity (~0.4G or lower indicates phone in free fall)
    private let IMPACT_PEAK_MPS2_THRESHOLD: Double = 20.0   // Sharp impact shock (> 20 m/s²)
    private let ROLLOVER_GYRO_THRESHOLD: Double = 4.5       // Angular velocity threshold for rollover (rad/s)
    private let ROOF_INVERSION_GRAV_Z: Double = 0.55        // Positive GravZ indicates inverted on roof
    
    let predefinedFallLabels = [
        "Free Fall Drop (1m)",
        "Desk Drop (0.7m)",
        "Floor Drop (0.3m)",
        "Pocket Slip & Fall",
        "Tumble / Roll Drop",
        "Vehicle Crash Shock",
        "Harsh Braking",
        "Normal Hand Shake",
        "Walking / Running (Negative Test)"
    ]
    
    let predefinedRolloverLabels = [
        "Lateral Rollover (360°)",
        "Quarter Roll (Roof Inversion)",
        "Dynamic Vehicle Rollover",
        "Violent Tumble Rollover",
        "Barrel Roll",
        "Sharp Drift / Cornering (Negative Test)",
        "Normal Driving Curve (Negative Test)"
    ]
    
    var currentLabels: [String] {
        recordingMode == .rollover ? predefinedRolloverLabels : predefinedFallLabels
    }
    
    override init() {
        super.init()
        loadPersistedSessions()
        startLivePreview()
    }
    
    deinit {
        stopSensors()
    }
    
    func startLivePreview() {
        guard motionManager.isDeviceMotionAvailable else {
            liveStatusMessage = "⚠️ Device Motion not available on this device"
            return
        }
        
        motionManager.deviceMotionUpdateInterval = 0.02 // 50 Hz
        motionManager.startDeviceMotionUpdates(to: .main) { [weak self] motion, _ in
            guard let self = self, let motion = motion else { return }
            self.processMotionFrame(motion: motion)
        }
    }
    
    func stopSensors() {
        if motionManager.isDeviceMotionActive {
            motionManager.stopDeviceMotionUpdates()
        }
    }
    
    func startRecording() {
        guard !isRecording else { return }
        
        activeSamples.removeAll()
        currentSessionEvents.removeAll()
        sessionPeakLinearMps2 = 0.0
        sessionPeakTotalG = 0.0
        sessionPeakGyroRads = 0.0
        sampleCount = 0
        recordingDuration = 0.0
        sessionStartTime = Date()
        isRecording = true
        liveStatusMessage = "🔴 Recording \(recordingMode.rawValue) at 50Hz..."
        
        let generator = UINotificationFeedbackGenerator()
        generator.notificationOccurred(.warning)
        
        durationTimer = Timer.publish(every: 0.1, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                guard let self = self, let start = self.sessionStartTime else { return }
                self.recordingDuration = Date().timeIntervalSince(start)
            }
    }
    
    func stopRecording() {
        guard isRecording else { return }
        
        durationTimer?.cancel()
        durationTimer = nil
        isRecording = false
        
        let endTime = Date()
        let start = sessionStartTime ?? endTime
        let totalDuration = endTime.timeIntervalSince(start)
        
        let prefix = recordingMode == .rollover ? "Rollover" : "Drop"
        let session = RecordedSession(
            sessionName: "Trial #\(savedSessions.count + 1) - \(selectedLabel)",
            mode: recordingMode.rawValue,
            label: selectedLabel,
            startTime: ISO8601DateFormatter().string(from: start),
            endTime: ISO8601DateFormatter().string(from: endTime),
            durationSeconds: totalDuration,
            sampleRateHz: totalDuration > 0 ? Double(activeSamples.count) / totalDuration : 50.0,
            totalSamples: activeSamples.count,
            peakLinearMps2: sessionPeakLinearMps2,
            peakTotalG: sessionPeakTotalG,
            peakGyroRads: sessionPeakGyroRads,
            detectedEventsCount: currentSessionEvents.count,
            events: currentSessionEvents,
            samples: activeSamples
        )
        
        savedSessions.insert(session, at: 0)
        persistSessions()
        
        exportSessionToConsole(session: session)
        
        liveStatusMessage = "✅ Saved \(prefix) session with \(activeSamples.count) samples & \(currentSessionEvents.count) event(s)."
        
        let generator = UINotificationFeedbackGenerator()
        generator.notificationOccurred(.success)
    }
    
    private func processMotionFrame(motion: CMDeviceMotion) {
        let uX = motion.userAcceleration.x
        let uY = motion.userAcceleration.y
        let uZ = motion.userAcceleration.z
        
        let gX = motion.gravity.x
        let gY = motion.gravity.y
        let gZ = motion.gravity.z
        
        let rX = motion.rotationRate.x
        let rY = motion.rotationRate.y
        let rZ = motion.rotationRate.z
        
        // Dynamic Linear Acceleration
        let linMagG = sqrt(uX*uX + uY*uY + uZ*uZ)
        let linMagMps2 = linMagG * 9.80665
        
        // Total Raw Acceleration vector
        let totX = uX + gX
        let totY = uY + gY
        let totZ = uZ + gZ
        let totalMagG = sqrt(totX*totX + totY*totY + totZ*totZ)
        
        // Angular rotation magnitude
        let gyroMag = sqrt(rX*rX + rY*rY + rZ*rZ)
        
        // State checks
        let inFreeFall = totalMagG < FREEFALL_TOTAL_G_THRESHOLD
        let inRollover = gyroMag >= ROLLOVER_GYRO_THRESHOLD || (gZ > ROOF_INVERSION_GRAV_Z && gyroMag >= 1.5)
        
        // Publish live telemetry
        self.currentLinearMps2 = linMagMps2
        self.currentLinearG = linMagG
        self.currentTotalG = totalMagG
        self.currentGyroRads = gyroMag
        self.currentLinX = uX
        self.currentLinY = uY
        self.currentLinZ = uZ
        self.currentGravZ = gZ
        self.currentGyroX = rX
        self.currentGyroY = rY
        self.currentGyroZ = rZ
        self.isCurrentlyInFreeFall = inFreeFall
        self.isCurrentlyRollingOver = inRollover
        
        let now = Date()
        
        // --- Freefall Tracker ---
        if inFreeFall {
            if freeFallStartTime == nil {
                freeFallStartTime = now
            }
        } else {
            if let ffStart = freeFallStartTime {
                let durationMs = now.timeIntervalSince(ffStart) * 1000.0
                if durationMs > 30.0 {
                    self.freeFallDurationMs = durationMs
                }
                freeFallStartTime = nil
            }
        }
        
        // --- Mode 1: Fall Drop Impact Detection ---
        if recordingMode == .fall && linMagMps2 >= IMPACT_PEAK_MPS2_THRESHOLD {
            if now.timeIntervalSince(lastImpactTime) > 0.4 {
                lastImpactTime = now
                
                let dominantAxis: String
                let absX = abs(uX)
                let absY = abs(uY)
                let absZ = abs(uZ)
                if absZ > absX && absZ > absY {
                    dominantAxis = "Z-Axis (\(uZ < 0 ? "Face-Down" : "Face-Up"))"
                } else if absY > absX {
                    dominantAxis = "Y-Axis (\(uY < 0 ? "Bottom Edge" : "Top Edge"))"
                } else {
                    dominantAxis = "X-Axis (\(uX < 0 ? "Left Edge" : "Right Edge"))"
                }
                
                let event = KineticEvent(
                    eventType: "Drop Impact",
                    eventTimeIso: ISO8601DateFormatter().string(from: now),
                    elapsedMs: sessionStartTime != nil ? now.timeIntervalSince(sessionStartTime!) * 1000.0 : 0.0,
                    peakLinearMps2: linMagMps2,
                    peakTotalG: totalMagG,
                    peakGyroRads: gyroMag,
                    durationMs: freeFallDurationMs,
                    dominantAxis: dominantAxis,
                    label: selectedLabel
                )
                
                if isRecording {
                    currentSessionEvents.append(event)
                    liveStatusMessage = String(format: "💥 Drop Impact: %.1f m/s² (FF: %.0fms, %@)", linMagMps2, freeFallDurationMs, dominantAxis)
                    AudioServicesPlaySystemSound(1003)
                }
                freeFallDurationMs = 0.0
            }
        }
        
        // --- Mode 2: Rollover Flip Detection ---
        if recordingMode == .rollover && inRollover {
            if now.timeIntervalSince(lastRolloverEventTime) > 0.6 {
                lastRolloverEventTime = now
                
                let rollAxis: String
                let absRX = abs(rX)
                let absRY = abs(rY)
                let absRZ = abs(rZ)
                if absRX > absRY && absRX > absRZ {
                    rollAxis = "X-Roll (Lateral Tilt)"
                } else if absRY > absRX {
                    rollAxis = "Y-Pitch (End-over-End)"
                } else {
                    rollAxis = "Z-Yaw (Spin)"
                }
                
                let event = KineticEvent(
                    eventType: "Rollover Flip",
                    eventTimeIso: ISO8601DateFormatter().string(from: now),
                    elapsedMs: sessionStartTime != nil ? now.timeIntervalSince(sessionStartTime!) * 1000.0 : 0.0,
                    peakLinearMps2: linMagMps2,
                    peakTotalG: totalMagG,
                    peakGyroRads: gyroMag,
                    durationMs: 0.0,
                    dominantAxis: "\(rollAxis) (gZ: \(String(format: "%+.2f", gZ)))",
                    label: selectedLabel
                )
                
                if isRecording {
                    currentSessionEvents.append(event)
                    liveStatusMessage = String(format: "🔄 Rollover Flip: %.1f rad/s (%@)", gyroMag, rollAxis)
                    AudioServicesPlaySystemSound(1004)
                }
            }
        }
        
        // Record active sample
        if isRecording, let start = sessionStartTime {
            let elapsedMs = now.timeIntervalSince(start) * 1000.0
            
            if linMagMps2 > sessionPeakLinearMps2 { sessionPeakLinearMps2 = linMagMps2 }
            if totalMagG > sessionPeakTotalG { sessionPeakTotalG = totalMagG }
            if gyroMag > sessionPeakGyroRads { sessionPeakGyroRads = gyroMag }
            
            let sample = SensorSample(
                timestampMs: elapsedMs,
                timeIso: ISO8601DateFormatter().string(from: now),
                linearAccelX: uX,
                linearAccelY: uY,
                linearAccelZ: uZ,
                linearAccelMagMps2: linMagMps2,
                linearAccelMagG: linMagG,
                totalAccelX: totX,
                totalAccelY: totY,
                totalAccelZ: totZ,
                totalAccelMagG: totalMagG,
                gravityX: gX,
                gravityY: gY,
                gravityZ: gZ,
                gyroX: rX,
                gyroY: rY,
                gyroZ: rZ,
                gyroMagRads: gyroMag,
                isFreeFallState: inFreeFall,
                isRolloverState: inRollover
            )
            
            activeSamples.append(sample)
            sampleCount = activeSamples.count
        }
    }
    
    // MARK: - Persistence & Export
    
    private func getDocumentsDirectory() -> URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
    }
    
    private var storageUrl: URL {
        getDocumentsDirectory().appendingPathComponent("recorded_kinetics_sessions.json")
    }
    
    private func persistSessions() {
        do {
            let data = try JSONEncoder().encode(savedSessions)
            try data.write(to: storageUrl, options: .atomic)
        } catch {
            print("Failed to persist sessions: \(error)")
        }
    }
    
    private func loadPersistedSessions() {
        guard FileManager.default.fileExists(atPath: storageUrl.path) else { return }
        do {
            let data = try Data(contentsOf: storageUrl)
            self.savedSessions = try JSONDecoder().decode([RecordedSession].self, from: data)
        } catch {
            print("Failed to load sessions: \(error)")
        }
    }
    
    func deleteSession(at indexSet: IndexSet) {
        savedSessions.remove(atOffsets: indexSet)
        persistSessions()
    }
    
    func clearAllSessions() {
        savedSessions.removeAll()
        persistSessions()
    }
    
    func exportCSV(session: RecordedSession) -> URL? {
        var csv = "timestamp_ms,time_iso,linear_accel_x,linear_accel_y,linear_accel_z,linear_mag_mps2,linear_mag_g,total_accel_x,total_accel_y,total_accel_z,total_mag_g,gravity_x,gravity_y,gravity_z,gyro_x,gyro_y,gyro_z,gyro_mag_rads,is_freefall,is_rollover,label,mode\n"
        
        for s in session.samples {
            csv += String(format: "%.1f,%@,%.4f,%.4f,%.4f,%.4f,%.4f,%.4f,%.4f,%.4f,%.4f,%.4f,%.4f,%.4f,%.4f,%.4f,%.4f,%.4f,%@,%@,%@,%@\n",
                          s.timestampMs,
                          s.timeIso,
                          s.linearAccelX, s.linearAccelY, s.linearAccelZ,
                          s.linearAccelMagMps2, s.linearAccelMagG,
                          s.totalAccelX, s.totalAccelY, s.totalAccelZ,
                          s.totalAccelMagG,
                          s.gravityX, s.gravityY, s.gravityZ,
                          s.gyroX, s.gyroY, s.gyroZ,
                          s.gyroMagRads,
                          s.isFreeFallState ? "1" : "0",
                          s.isRolloverState ? "1" : "0",
                          session.label,
                          session.mode)
        }
        
        let sanitizedName = session.sessionName.replacingOccurrences(of: " ", with: "_").replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "#", with: "")
        let fileUrl = getDocumentsDirectory().appendingPathComponent("\(sanitizedName).csv")
        
        do {
            try csv.write(to: fileUrl, atomically: true, encoding: .utf8)
            return fileUrl
        } catch {
            print("Failed to export CSV: \(error)")
            return nil
        }
    }
    
    func exportJSON(session: RecordedSession) -> URL? {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .prettyPrinted
        guard let data = try? encoder.encode(session) else { return nil }
        
        let sanitizedName = session.sessionName.replacingOccurrences(of: " ", with: "_").replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "#", with: "")
        let fileUrl = getDocumentsDirectory().appendingPathComponent("\(sanitizedName).json")
        
        do {
            try data.write(to: fileUrl, options: .atomic)
            return fileUrl
        } catch {
            print("Failed to export JSON: \(error)")
            return nil
        }
    }
    
    private func exportSessionToConsole(session: RecordedSession) {
        let headerIcon = session.mode.contains("Rollover") ? "🚗 ROLLOVER" : "📱 FALL"
        print("\n================== \(headerIcon) DATASET RECORDED ==================")
        print("Name: \(session.sessionName)")
        print("Mode: \(session.mode)")
        print("Label: \(session.label)")
        print("Duration: \(String(format: "%.2fs", session.durationSeconds)) | Samples: \(session.totalSamples) (\(String(format: "%.1f", session.sampleRateHz)) Hz)")
        print("Peak Gyroscope: \(String(format: "%.2f rad/s", session.peakGyroRads))")
        print("Peak Linear Accel: \(String(format: "%.2f m/s² (%.2f G)", session.peakLinearMps2, session.peakLinearMps2 / 9.80665))")
        print("Peak Total Raw Accel: \(String(format: "%.2f G", session.peakTotalG))")
        print("Events Detected: \(session.detectedEventsCount)")
        for (idx, ev) in session.events.enumerated() {
            print("  -> [\(ev.eventType) #\(idx + 1)]: PeakGyro=\(String(format: "%.1f rad/s", ev.peakGyroRads)), PeakLin=\(String(format: "%.1f m/s²", ev.peakLinearMps2)), Axis=\(ev.dominantAxis), Time=\(String(format: "%.1f ms", ev.elapsedMs))")
        }
        print("==============================================================\n")
    }
}

// MARK: - Activity Share Sheet Bridge

struct ShareSheet: UIViewControllerRepresentable {
    var items: [Any]
    
    func makeUIViewController(context: Context) -> UIActivityViewController {
        let controller = UIActivityViewController(activityItems: items, applicationActivities: nil)
        return controller
    }
    
    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

// MARK: - Main SwiftUI Dataset Recorder View

struct FallDatasetRecorderView: View {
    var initialMode: DatasetRecordingMode = .fall
    
    @StateObject private var viewModel = DatasetRecorderViewModel()
    @Environment(\.presentationMode) var presentationMode
    
    @State private var shareItems: [Any] = []
    @State private var showShareSheet: Bool = false
    @State private var selectedSessionDetail: RecordedSession? = nil
    
    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 16) {
                    
                    // Mode Selector (Fall Drops vs Rollover Flips)
                    Picker("Mode", selection: $viewModel.recordingMode) {
                        ForEach(DatasetRecordingMode.allCases) { mode in
                            HStack {
                                Image(systemName: mode.icon)
                                Text(mode.rawValue)
                            }
                            .tag(mode)
                        }
                    }
                    .pickerStyle(SegmentedPickerStyle())
                    .padding(.horizontal, 4)
                    .disabled(viewModel.isRecording)
                    
                    // Header Status Card
                    headerCard
                    
                    // Live Real-Time Sensor Telemetry
                    liveTelemetryCard
                    
                    // Record / Stop Control Action Card
                    recordingControlCard
                    
                    // Trial Events Live Indicator
                    if !viewModel.currentSessionEvents.isEmpty {
                        liveEventsCard
                    }
                    
                    // Saved Dataset Sessions History
                    savedSessionsSection
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
            }
            .background(Color(red: 245/255, green: 246/255, blue: 250/255).edgesIgnoringSafeArea(.all))
            .navigationTitle(viewModel.recordingMode == .rollover ? "Rollover Dataset Recorder" : "Fall Dataset Recorder")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button(action: { presentationMode.wrappedValue.dismiss() }) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 20))
                            .foregroundColor(.gray)
                    }
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    if !viewModel.savedSessions.isEmpty {
                        Menu {
                            Button(role: .destructive, action: { viewModel.clearAllSessions() }) {
                                Label("Clear All Trials", systemImage: "trash")
                            }
                        } label: {
                            Image(systemName: "ellipsis.circle")
                                .font(.system(size: 20))
                                .foregroundColor(.primary)
                        }
                    }
                }
            }
            .sheet(isPresented: $showShareSheet) {
                ShareSheet(items: shareItems)
            }
            .sheet(item: $selectedSessionDetail) { session in
                SessionDetailView(session: session, viewModel: viewModel, onShare: { items in
                    shareItems = items
                    showShareSheet = true
                })
            }
            .onAppear {
                viewModel.recordingMode = initialMode
            }
        }
        .navigationViewStyle(StackNavigationViewStyle())
    }
    
    // MARK: - UI Components
    
    private var headerCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Image(systemName: viewModel.recordingMode == .rollover ? "arrow.triangle.2.circlepath.circle.fill" : "waveform.path.ecg.rectangle.fill")
                    .foregroundColor(viewModel.recordingMode == .rollover ? .indigo : .purple)
                    .font(.title2)
                
                Text(viewModel.recordingMode == .rollover ? "Vehicle Rollover & Inversion Calibration" : "Phone Drop & Fall Calibration")
                    .font(.headline.weight(.bold))
                
                Spacer()
                
                if viewModel.isRecording {
                    HStack(spacing: 6) {
                        Circle()
                            .fill(Color.red)
                            .frame(width: 10, height: 10)
                        Text("REC")
                            .font(.system(size: 12, weight: .black))
                            .foregroundColor(.red)
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.red.opacity(0.12))
                    .cornerRadius(8)
                }
            }
            
            Text(viewModel.liveStatusMessage)
                .font(.caption)
                .foregroundColor(viewModel.isRecording ? .red : .secondary)
                .lineLimit(2)
        }
        .padding(14)
        .background(Color.white)
        .cornerRadius(14)
        .shadow(color: Color.black.opacity(0.04), radius: 4, x: 0, y: 2)
    }
    
    private var liveTelemetryCard: some View {
        VStack(spacing: 12) {
            HStack {
                Text(viewModel.recordingMode == .rollover ? "Live Gyroscope & Orientation" : "Live Shock & Telemetry")
                    .font(.subheadline.weight(.bold))
                    .foregroundColor(.primary)
                Spacer()
                
                if viewModel.recordingMode == .rollover {
                    if viewModel.isCurrentlyRollingOver {
                        HStack(spacing: 4) {
                            Image(systemName: "arrow.triangle.2.circlepath")
                            Text("ROLLOVER ACTIVE (≥4.5 rad/s)")
                        }
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(.white)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.indigo)
                        .cornerRadius(6)
                    } else if viewModel.currentGravZ > 0.55 {
                        HStack(spacing: 4) {
                            Image(systemName: "arrow.up.and.down.circle.fill")
                            Text("INVERTED ON ROOF")
                        }
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(.white)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.orange)
                        .cornerRadius(6)
                    } else {
                        Text("Upright Stance")
                            .font(.caption2)
                            .foregroundColor(.gray)
                    }
                } else {
                    if viewModel.isCurrentlyInFreeFall {
                        HStack(spacing: 4) {
                            Image(systemName: "arrow.down.to.line.compact")
                            Text("FREE FALL (<0.4G)")
                        }
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(.white)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.orange)
                        .cornerRadius(6)
                    } else {
                        Text("1G Gravity Baseline")
                            .font(.caption2)
                            .foregroundColor(.gray)
                    }
                }
            }
            
            Divider()
            
            // Highlighted Metrics
            HStack(spacing: 12) {
                telemetryMetricBox(
                    title: "Gyro Rotation",
                    value: String(format: "%.1f", viewModel.currentGyroRads),
                    unit: "rad/s",
                    color: viewModel.currentGyroRads >= 4.5 ? .indigo : .teal
                )
                
                telemetryMetricBox(
                    title: "Roof Inversion",
                    value: String(format: "%+.2f", viewModel.currentGravZ),
                    unit: "gZ",
                    color: viewModel.currentGravZ > 0.55 ? .orange : .blue
                )
                
                telemetryMetricBox(
                    title: "Linear Shock",
                    value: String(format: "%.1f", viewModel.currentLinearMps2),
                    unit: "m/s²",
                    color: viewModel.currentLinearMps2 > 20 ? .red : .purple
                )
            }
            
            // XYZ Gyro / Accel Breakdown
            HStack(spacing: 8) {
                axisPill(axis: "Roll (X)", value: viewModel.currentGyroX)
                axisPill(axis: "Pitch (Y)", value: viewModel.currentGyroY)
                axisPill(axis: "Yaw (Z)", value: viewModel.currentGyroZ)
            }
        }
        .padding(14)
        .background(Color.white)
        .cornerRadius(14)
        .shadow(color: Color.black.opacity(0.04), radius: 4, x: 0, y: 2)
    }
    
    private func telemetryMetricBox(title: String, value: String, unit: String, color: Color) -> some View {
        VStack(spacing: 3) {
            Text(title)
                .font(.system(size: 10, weight: .medium))
                .foregroundColor(.secondary)
            
            HStack(alignment: .lastTextBaseline, spacing: 2) {
                Text(value)
                    .font(.system(size: 18, weight: .bold, design: .rounded))
                    .foregroundColor(color)
                Text(unit)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(.secondary)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .background(color.opacity(0.08))
        .cornerRadius(10)
    }
    
    private func axisPill(axis: String, value: Double) -> some View {
        HStack(spacing: 4) {
            Text(axis + ":")
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(.gray)
            Text(String(format: "%+.2f", value))
                .font(.system(size: 11, weight: .bold, design: .monospaced))
                .foregroundColor(.primary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 4)
        .background(Color(white: 0.95))
        .cornerRadius(6)
    }
    
    private var recordingControlCard: some View {
        VStack(spacing: 14) {
            // Label Selector
            VStack(alignment: .leading, spacing: 6) {
                Text(viewModel.recordingMode == .rollover ? "Rollover Scenario / Tag" : "Fall Trial Scenario / Tag")
                    .font(.caption.weight(.bold))
                    .foregroundColor(.secondary)
                
                Menu {
                    ForEach(viewModel.currentLabels, id: \.self) { label in
                        Button(action: { viewModel.selectedLabel = label }) {
                            if viewModel.selectedLabel == label {
                                Label(label, systemImage: "checkmark")
                            } else {
                                Text(label)
                            }
                        }
                    }
                } label: {
                    HStack {
                        Image(systemName: "tag.fill")
                            .foregroundColor(viewModel.recordingMode == .rollover ? .indigo : .purple)
                        Text(viewModel.selectedLabel)
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(.primary)
                        Spacer()
                        Image(systemName: "chevron.up.chevron.down")
                            .font(.system(size: 12))
                            .foregroundColor(.gray)
                    }
                    .padding(12)
                    .background(Color(white: 0.94))
                    .cornerRadius(10)
                }
                .disabled(viewModel.isRecording)
            }
            
            // Session Live Stats (if recording)
            if viewModel.isRecording {
                HStack(spacing: 16) {
                    VStack {
                        Text("Duration")
                            .font(.caption2)
                            .foregroundColor(.gray)
                        Text(String(format: "%.1f s", viewModel.recordingDuration))
                            .font(.system(size: 16, weight: .bold, design: .monospaced))
                            .foregroundColor(.primary)
                    }
                    
                    VStack {
                        Text("Samples")
                            .font(.caption2)
                            .foregroundColor(.gray)
                        Text("\(viewModel.sampleCount)")
                            .font(.system(size: 16, weight: .bold, design: .monospaced))
                            .foregroundColor(.blue)
                    }
                    
                    VStack {
                        Text(viewModel.recordingMode == .rollover ? "Peak Gyro" : "Peak Shock")
                            .font(.caption2)
                            .foregroundColor(.gray)
                        Text(viewModel.recordingMode == .rollover
                             ? String(format: "%.1f rad/s", viewModel.sessionPeakGyroRads)
                             : String(format: "%.1f m/s²", viewModel.sessionPeakLinearMps2))
                            .font(.system(size: 16, weight: .bold, design: .monospaced))
                            .foregroundColor(viewModel.recordingMode == .rollover ? .indigo : .red)
                    }
                }
                .padding(.vertical, 8)
                .frame(maxWidth: .infinity)
                .background((viewModel.recordingMode == .rollover ? Color.indigo : Color.red).opacity(0.06))
                .cornerRadius(10)
            }
            
            // Big Record / Stop Button
            Button(action: {
                if viewModel.isRecording {
                    viewModel.stopRecording()
                } else {
                    viewModel.startRecording()
                }
            }) {
                HStack(spacing: 10) {
                    Image(systemName: viewModel.isRecording ? "stop.fill" : "record.circle.fill")
                        .font(.system(size: 22))
                    Text(viewModel.isRecording
                         ? "STOP RECORDING"
                         : (viewModel.recordingMode == .rollover
                            ? "START RECORDING ROLLOVER DATA"
                            : "START RECORDING FALL DATA"))
                        .font(.system(size: 15, weight: .bold))
                }
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 15)
                .background(viewModel.isRecording ? Color.red : (viewModel.recordingMode == .rollover ? Color(red: 45/255, green: 85/255, blue: 215/255) : Color(red: 130/255, green: 40/255, blue: 215/255)))
                .cornerRadius(14)
                .shadow(color: (viewModel.isRecording ? Color.red : (viewModel.recordingMode == .rollover ? Color.blue : Color.purple)).opacity(0.3), radius: 6, x: 0, y: 3)
            }
        }
        .padding(14)
        .background(Color.white)
        .cornerRadius(14)
        .shadow(color: Color.black.opacity(0.04), radius: 4, x: 0, y: 2)
    }
    
    private var liveEventsCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Image(systemName: viewModel.recordingMode == .rollover ? "arrow.triangle.2.circlepath" : "bolt.horizontal.fill")
                    .foregroundColor(viewModel.recordingMode == .rollover ? .indigo : .orange)
                Text("Detected \(viewModel.recordingMode == .rollover ? "Rollover Flips" : "Drop Impacts") (\(viewModel.currentSessionEvents.count))")
                    .font(.subheadline.weight(.bold))
                Spacer()
            }
            
            ForEach(viewModel.currentSessionEvents) { ev in
                HStack(spacing: 10) {
                    Image(systemName: viewModel.recordingMode == .rollover ? "arrow.triangle.2.circlepath" : "arrow.down.forward.and.arrow.up.backward")
                        .foregroundColor(viewModel.recordingMode == .rollover ? .indigo : .red)
                        .font(.system(size: 14))
                    
                    VStack(alignment: .leading, spacing: 2) {
                        Text(ev.dominantAxis)
                            .font(.system(size: 13, weight: .bold))
                        Text(String(format: "Time: %.1f s", ev.elapsedMs / 1000.0))
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                    
                    Spacer()
                    
                    VStack(alignment: .trailing, spacing: 2) {
                        Text(String(format: "%.1f rad/s", ev.peakGyroRads))
                            .font(.system(size: 14, weight: .black, design: .rounded))
                            .foregroundColor(.indigo)
                        Text(String(format: "%.1f m/s²", ev.peakLinearMps2))
                            .font(.caption2)
                            .foregroundColor(.gray)
                    }
                }
                .padding(10)
                .background(Color(white: 0.96))
                .cornerRadius(8)
            }
        }
        .padding(14)
        .background(Color.white)
        .cornerRadius(14)
        .shadow(color: Color.black.opacity(0.04), radius: 4, x: 0, y: 2)
    }
    
    private var savedSessionsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Recorded Dataset Trials (\(viewModel.savedSessions.count))")
                    .font(.subheadline.weight(.bold))
                    .foregroundColor(.primary)
                Spacer()
            }
            
            if viewModel.savedSessions.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "tray")
                        .font(.system(size: 32))
                        .foregroundColor(.gray)
                    Text("No dataset trials recorded yet")
                        .font(.footnote)
                        .foregroundColor(.gray)
                    Text("Press 'Start Recording' to capture high-frequency motion dynamics.")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 24)
                .background(Color.white)
                .cornerRadius(14)
            } else {
                ForEach(viewModel.savedSessions) { session in
                    sessionRowView(session: session)
                }
            }
        }
    }
    
    private func sessionRowView(session: RecordedSession) -> some View {
        Button(action: { selectedSessionDetail = session }) {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    VStack(alignment: .leading, spacing: 3) {
                        HStack(spacing: 6) {
                            Text(session.sessionName)
                                .font(.system(size: 14, weight: .bold))
                                .foregroundColor(.primary)
                            
                            Text(session.mode.contains("Rollover") ? "ROLLOVER" : "FALL")
                                .font(.system(size: 9, weight: .black))
                                .padding(.horizontal, 5)
                                .padding(.vertical, 2)
                                .background((session.mode.contains("Rollover") ? Color.indigo : Color.purple).opacity(0.15))
                                .foregroundColor(session.mode.contains("Rollover") ? .indigo : .purple)
                                .cornerRadius(4)
                        }
                        Text(session.startTime)
                            .font(.caption2)
                            .foregroundColor(.gray)
                    }
                    
                    Spacer()
                    
                    VStack(alignment: .trailing, spacing: 2) {
                        Text(String(format: "Peak %.1f rad/s", session.peakGyroRads))
                            .font(.system(size: 13, weight: .bold, design: .rounded))
                            .foregroundColor(.indigo)
                        Text("\(session.totalSamples) samples (\(String(format: "%.1fs", session.durationSeconds)))")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }
                
                HStack(spacing: 8) {
                    HStack(spacing: 4) {
                        Image(systemName: "bolt.fill")
                            .font(.system(size: 10))
                        Text("\(session.detectedEventsCount) Event(s)")
                            .font(.system(size: 11, weight: .semibold))
                    }
                    .foregroundColor(.orange)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(Color.orange.opacity(0.12))
                    .cornerRadius(6)
                    
                    HStack(spacing: 4) {
                        Image(systemName: "speedometer")
                            .font(.system(size: 10))
                        Text(String(format: "%.1f m/s²", session.peakLinearMps2))
                            .font(.system(size: 11, weight: .semibold))
                    }
                    .foregroundColor(.teal)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(Color.teal.opacity(0.12))
                    .cornerRadius(6)
                    
                    Spacer()
                    
                    Image(systemName: "chevron.right")
                        .font(.system(size: 12))
                        .foregroundColor(.gray)
                }
            }
            .padding(12)
            .background(Color.white)
            .cornerRadius(12)
            .shadow(color: Color.black.opacity(0.03), radius: 3, x: 0, y: 1)
        }
    }
}

// MARK: - Detailed Session Inspection View

struct SessionDetailView: View {
    let session: RecordedSession
    @ObservedObject var viewModel: DatasetRecorderViewModel
    var onShare: ([Any]) -> Void
    @Environment(\.presentationMode) var presentationMode
    
    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 14) {
                    
                    // Stats Summary Card
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Session Summary")
                            .font(.headline.weight(.bold))
                        
                        Divider()
                        
                        VStack(spacing: 8) {
                            detailRow(label: "Mode:", value: session.mode, isBold: true)
                            detailRow(label: "Scenario Label:", value: session.label, isBold: true)
                            detailRow(label: "Duration:", value: String(format: "%.2f seconds", session.durationSeconds))
                            detailRow(label: "Total Samples:", value: "\(session.totalSamples) (\(String(format: "%.1f", session.sampleRateHz)) Hz)")
                            detailRow(label: "Peak Gyro Rotation:", value: String(format: "%.2f rad/s", session.peakGyroRads), valueColor: .indigo, isBold: true)
                            detailRow(label: "Peak Linear Accel:", value: String(format: "%.2f m/s² (%.2f G)", session.peakLinearMps2, session.peakLinearMps2 / 9.80665), valueColor: .red)
                            detailRow(label: "Peak Total Raw Accel:", value: String(format: "%.2f G", session.peakTotalG), valueColor: .purple)
                        }
                    }
                    .padding(14)
                    .background(Color.white)
                    .cornerRadius(14)
                    
                    // Export Actions Card
                    VStack(spacing: 10) {
                        Text("Export Dataset")
                            .font(.subheadline.weight(.bold))
                        
                        HStack(spacing: 12) {
                            Button(action: {
                                if let url = viewModel.exportCSV(session: session) {
                                    onShare([url])
                                }
                            }) {
                                HStack {
                                    Image(systemName: "doc.text.fill")
                                    Text("Export CSV")
                                }
                                .font(.system(size: 14, weight: .bold))
                                .foregroundColor(.white)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 12)
                                .background(Color.blue)
                                .cornerRadius(10)
                            }
                            
                            Button(action: {
                                if let url = viewModel.exportJSON(session: session) {
                                    onShare([url])
                                }
                            }) {
                                HStack {
                                    Image(systemName: "curlybraces")
                                    Text("Export JSON")
                                }
                                .font(.system(size: 14, weight: .bold))
                                .foregroundColor(.white)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 12)
                                .background(Color.indigo)
                                .cornerRadius(10)
                            }
                        }
                    }
                    .padding(14)
                    .background(Color.white)
                    .cornerRadius(14)
                    
                    // Events List
                    if !session.events.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Kinetic Events (\(session.events.count))")
                                .font(.subheadline.weight(.bold))
                            
                            ForEach(session.events) { ev in
                                VStack(alignment: .leading, spacing: 4) {
                                    HStack {
                                        Text(ev.dominantAxis).bold()
                                        Spacer()
                                        Text(String(format: "%.1f rad/s", ev.peakGyroRads))
                                            .foregroundColor(.indigo)
                                            .bold()
                                    }
                                    Text(String(format: "Time: %.0f ms | Shock: %.1f m/s²", ev.elapsedMs, ev.peakLinearMps2))
                                        .font(.caption2)
                                        .foregroundColor(.secondary)
                                }
                                .padding(10)
                                .background(Color(white: 0.96))
                                .cornerRadius(8)
                            }
                        }
                        .padding(14)
                        .background(Color.white)
                        .cornerRadius(14)
                    }
                    
                    // Samples Preview Table
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Sample Stream Preview (First 20)")
                            .font(.subheadline.weight(.bold))
                        
                        ForEach(session.samples.prefix(20)) { s in
                            HStack {
                                Text(String(format: "%.0fms", s.timestampMs))
                                    .font(.caption2.monospaced())
                                    .foregroundColor(.gray)
                                Spacer()
                                Text(String(format: "Gyro: %.1f", s.gyroMagRads))
                                    .font(.caption2.monospaced())
                                    .foregroundColor(s.gyroMagRads >= 4.5 ? .indigo : .teal)
                                Text(String(format: "gZ: %+.2f", s.gravityZ))
                                    .font(.caption2.monospaced())
                                    .foregroundColor(s.gravityZ > 0.55 ? .orange : .secondary)
                                Text(String(format: "Lin: %.1f", s.linearAccelMagMps2))
                                    .font(.caption2.monospaced())
                                    .foregroundColor(s.linearAccelMagMps2 > 20 ? .red : .primary)
                            }
                            .padding(.vertical, 2)
                            Divider()
                        }
                    }
                    .padding(14)
                    .background(Color.white)
                    .cornerRadius(14)
                }
                .padding(16)
            }
            .background(Color(red: 245/255, green: 246/255, blue: 250/255).edgesIgnoringSafeArea(.all))
            .navigationTitle(session.sessionName)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        presentationMode.wrappedValue.dismiss()
                    }
                }
            }
        }
    }
    
    private func detailRow(label: String, value: String, valueColor: Color = .primary, isBold: Bool = false) -> some View {
        HStack {
            Text(label)
                .font(.system(size: 13))
                .foregroundColor(.gray)
            Spacer()
            Text(value)
                .font(.system(size: 13, weight: isBold ? .bold : .regular))
                .foregroundColor(valueColor)
        }
    }
}
