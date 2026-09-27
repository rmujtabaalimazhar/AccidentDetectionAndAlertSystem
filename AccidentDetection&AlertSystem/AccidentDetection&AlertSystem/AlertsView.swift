import SwiftUI
import MapKit
import CoreLocation

enum AlertViewMode {
    case guardian
    case rescue
}

struct EmergencyAlert: Identifiable, Decodable {
    var id: Int { alertId }
    let alertId: Int
    let accidentId: Int
    let time: String
    let status: Bool
    let driverUid: String
    let driverName: String
    let driverContact: String
    let relationship: String
    let carMake: String
    let plateNumber: String
    let location: String
    let impactSide: String
    let impactForce: Double
    let cabinDamage: Double
    let severity: String
    let distanceKm: Double?
}

struct AlertsView: View {
    let mode: AlertViewMode
    let identifier: String   // guardianId (email) or rescue Rid (string)
    var onLogout: () -> Void = {}
    var onDismiss: (() -> Void)? = nil
    
    @State private var alerts: [EmergencyAlert] = []
    @State private var isLoading = false
    @State private var errorMessage: String? = nil
    @State private var selectedAlertForDetail: EmergencyAlert? = nil
    @State private var selectedAlertForTracking: EmergencyAlert? = nil
    
    let API = AppConfig.apiBaseURL
    
    var title: String {
        switch mode {
        case .guardian: return "Guardian Emergency Alerts"
        case .rescue:   return "Rescue Dispatch Center"
        }
    }
    
    var subtitle: String {
        switch mode {
        case .guardian: return "Emergency notifications for your family & loved ones"
        case .rescue:   return "Rescue Unit #\(identifier) • Priority Dispatch"
        }
    }
    
    var body: some View {
        NavigationView {
            ZStack {
                Color(red: 245/255, green: 246/255, blue: 250/255).edgesIgnoringSafeArea(.all)
                
                VStack(spacing: 0) {
                    // Custom Header
                    headerBar
                    
                    if isLoading && alerts.isEmpty {
                        Spacer()
                        ProgressView("Checking for emergency alerts…")
                            .padding()
                        Spacer()
                    } else if alerts.isEmpty {
                        emptyStateView
                    } else {
                        alertsList
                    }
                }
            }
            .navigationBarHidden(true)
            .sheet(item: $selectedAlertForDetail) { alert in
                AlertDetailSheet(alert: alert, onTrackLocation: {
                    selectedAlertForDetail = nil
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                        selectedAlertForTracking = alert
                    }
                }, onAcknowledge: {
                    markAlertAsSeen(alertId: alert.alertId)
                })
            }
            .sheet(item: $selectedAlertForTracking) { alert in
                AccidentLocationTrackingView(alert: alert)
            }
            .onAppear {
                fetchAlerts()
            }
        }
        .navigationViewStyle(StackNavigationViewStyle())
    }
    
    // ================= HEADER =================
    private var headerBar: some View {
        HStack {
            if let onDismiss = onDismiss {
                Button(action: onDismiss) {
                    Image(systemName: "arrow.left")
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundColor(.black)
                        .frame(width: 40, height: 40)
                        .background(Color.white)
                        .clipShape(Circle())
                        .shadow(color: Color.black.opacity(0.08), radius: 4)
                }
            }
            
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.headline.weight(.bold))
                    .foregroundColor(.black)
                Text(subtitle)
                    .font(.caption)
                    .foregroundColor(.gray)
            }
            
            Spacer()
            
            Button(action: fetchAlerts) {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(.blue)
                    .frame(width: 36, height: 36)
                    .background(Color.white)
                    .clipShape(Circle())
                    .shadow(color: Color.black.opacity(0.08), radius: 3)
            }
            
            Button(action: onLogout) {
                Image(systemName: "rectangle.portrait.and.arrow.right")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(.red)
                    .frame(width: 36, height: 36)
                    .background(Color.white)
                    .clipShape(Circle())
                    .shadow(color: Color.black.opacity(0.08), radius: 3)
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 12)
        .padding(.bottom, 12)
        .background(Color.white)
        .shadow(color: Color.black.opacity(0.04), radius: 3, y: 2)
    }
    
    // ================= EMPTY STATE =================
    private var emptyStateView: some View {
        VStack(spacing: 16) {
            Spacer()
            
            Circle()
                .fill(Color.green.opacity(0.12))
                .frame(width: 90, height: 90)
                .overlay(
                    Image(systemName: "checkmark.shield.fill")
                        .font(.system(size: 42))
                        .foregroundColor(.green)
                )
            
            Text("All Clear — No Active Alerts")
                .font(.title3.weight(.bold))
                .foregroundColor(.black)
            
            Text(mode == .guardian
                 ? "None of your loved ones or registered family members have active accident alerts."
                 : "No active accident dispatches currently require assistance in your sector.")
                .font(.subheadline)
                .foregroundColor(.gray)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
            
            Button(action: fetchAlerts) {
                HStack(spacing: 8) {
                    Image(systemName: "arrow.clockwise")
                    Text("Check Again")
                }
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(.white)
                .padding(.horizontal, 20)
                .padding(.vertical, 10)
                .background(Color.blue)
                .cornerRadius(20)
            }
            .padding(.top, 8)
            
            Spacer()
        }
    }
    
    // ================= ALERTS LIST =================
    private var alertsList: some View {
        ScrollView {
            VStack(spacing: 14) {
                // Warning Banner
                HStack(spacing: 12) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.title2)
                        .foregroundColor(.red)
                    
                    VStack(alignment: .leading, spacing: 2) {
                        Text("\(alerts.count) ACTIVE EMERGENCY ALERT\(alerts.count > 1 ? "S" : "")")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundColor(.red)
                        Text("Immediate attention and response recommended")
                            .font(.caption2)
                            .foregroundColor(.black.opacity(0.7))
                    }
                    Spacer()
                }
                .padding(12)
                .background(Color.red.opacity(0.12))
                .cornerRadius(12)
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.red.opacity(0.3), lineWidth: 1))
                .padding(.horizontal, 16)
                .padding(.top, 12)
                
                ForEach(alerts) { alert in
                    AlertCard(
                        alert: alert,
                        mode: mode,
                        onViewDetail: {
                            selectedAlertForDetail = alert
                        },
                        onTrackLocation: {
                            selectedAlertForTracking = alert
                        },
                        onAcknowledge: {
                            markAlertAsSeen(alertId: alert.alertId)
                        }
                    )
                }
                .padding(.horizontal, 16)
            }
            .padding(.bottom, 24)
        }
    }
    
    // ================= API CALLS =================
    private func fetchAlerts() {
        isLoading = true
        errorMessage = nil
        
        let endpoint: String
        switch mode {
        case .guardian:
            endpoint = "\(API)/Alerts/Guardian?guardianId=\(identifier.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? identifier)"
        case .rescue:
            endpoint = "\(API)/Alerts/Rescue?rid=\(identifier)"
        }
        
        guard let url = URL(string: endpoint) else {
            isLoading = false
            return
        }
        
        URLSession.shared.dataTask(with: url) { data, response, error in
            DispatchQueue.main.async {
                self.isLoading = false
                if let error = error {
                    self.errorMessage = error.localizedDescription
                    return
                }
                guard let data = data else { return }
                do {
                let decoded = try JSONDecoder().decode([EmergencyAlert].self, from: data)
                    self.alerts = decoded
                } catch {
                    print("Decode error in alerts: \(error)")
                }
            }
        }.resume()
    }
    
    private func markAlertAsSeen(alertId: Int) {
        guard let url = URL(string: "\(API)/Alerts/MarkAsSeen?alertId=\(alertId)") else { return }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        
        URLSession.shared.dataTask(with: req) { data, _, error in
            DispatchQueue.main.async {
                if error == nil {
                    withAnimation {
                        self.alerts.removeAll { $0.alertId == alertId }
                        if self.selectedAlertForDetail?.alertId == alertId {
                            self.selectedAlertForDetail = nil
                        }
                    }
                }
            }
        }.resume()
    }
}

// Helper for situation-specific severity badge styling
func severityBadgeColors(for severity: String) -> (bg: Color, text: Color, icon: String) {
    let lower = severity.lowercased()
    if lower.contains("critical") || lower.contains("fatal") || lower.contains("5") || lower.contains("6") {
        // Critical / Fatal: Solid Red filled block with white text
        return (Color(red: 0.88, green: 0.12, blue: 0.14), .white, "exclamationmark.octagon.fill")
    } else if lower.contains("severe") || lower.contains("serious") || lower.contains("high") || lower.contains("3") || lower.contains("4") {
        // Serious to Severe: Vibrant Crimson / Deep Red-Orange filled block
        return (Color(red: 0.94, green: 0.30, blue: 0.10), .white, "exclamationmark.triangle.fill")
    } else if lower.contains("moderate") || lower.contains("medium") || lower.contains("2") {
        // Moderate: Warm Orange filled block
        return (Color(red: 0.96, green: 0.55, blue: 0.05), .white, "exclamationmark.circle.fill")
    } else if lower.contains("minor") || lower.contains("low") || lower.contains("1") {
        // Minor: Golden Amber filled block
        return (Color(red: 0.92, green: 0.72, blue: 0.12), .black, "info.circle.fill")
    } else {
        // None / Safe: Fresh Green filled block
        return (Color(red: 0.15, green: 0.68, blue: 0.35), .white, "checkmark.shield.fill")
    }
}

// ================= ALERT CARD =================
struct AlertCard: View {
    let alert: EmergencyAlert
    let mode: AlertViewMode
    //for getting location name in runtime
    @State private var locationName = "Loading..."
    var onViewDetail: () -> Void
    var onTrackLocation: () -> Void
    var onAcknowledge: () -> Void
    
    var badgeInfo: (bg: Color, text: Color, icon: String) {
        severityBadgeColors(for: alert.severity)
    }
    
    //location name getting function
    private func getLocationName(_ location: String, completion: @escaping (String) -> Void) {
        let parts = location.split(separator: ",")

        guard parts.count == 2,
              let lat = Double(parts[0].trimmingCharacters(in: .whitespaces)),
              let lon = Double(parts[1].trimmingCharacters(in: .whitespaces)) else {
            completion("Unknown Location")
            return
        }

        let coordinate = CLLocation(latitude: lat, longitude: lon)

        CLGeocoder().reverseGeocodeLocation(coordinate) { placemarks, error in
            guard let placemark = placemarks?.first, error == nil else {
                completion("Unknown Location")
                return
            }

            var locationParts: [String] = []

            // Specific area / sector / neighborhood
            if let subLocality = placemark.subLocality,
               !subLocality.isEmpty {
                locationParts.append(subLocality)
            }

            // Street / road
            if let street = placemark.thoroughfare,
               !street.isEmpty,
               !locationParts.contains(street) {
                locationParts.append(street)
            }

            // City
            if let city = placemark.locality,
               !city.isEmpty,
               !locationParts.contains(city) {
                locationParts.append(city)
            }

            if locationParts.isEmpty {
                completion("Unknown Location")
            } else {
                completion(locationParts.joined(separator: ", "))
            }
        }
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Top row: filled severity badge block & time
            HStack {
                HStack(spacing: 6) {
                    Image(systemName: badgeInfo.icon)
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(badgeInfo.text)
                    Text(alert.severity.uppercased())
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(badgeInfo.text)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(badgeInfo.bg)
                .cornerRadius(8)
                .shadow(color: badgeInfo.bg.opacity(0.35), radius: 3, y: 1)
                
                if mode == .rescue , let dist = alert.distanceKm, dist > 0 {
                    HStack(spacing: 4) {
                        Image(systemName: "location.fill")
                            .font(.system(size: 10))
                        Text(String(format: "%.1f km (Nearest Unit)", dist))
                            .font(.system(size: 11, weight: .semibold))
                    }
                    .foregroundColor(.blue)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.blue.opacity(0.1))
                    .cornerRadius(8)
                }
                
                Spacer()
                
                Text(alert.time)
                    .font(.caption2)
                    .foregroundColor(.gray)
            }
            
            // Driver & Relationship
            HStack(alignment: .top, spacing: 12) {
                Circle()
                    .fill(Color.red.opacity(0.15))
                    .frame(width: 44, height: 44)
                    .overlay(
                        Image(systemName: mode == .guardian ? "heart.fill" : "cross.case.fill")
                            .foregroundColor(.red)
                    )
                
                VStack(alignment: .leading, spacing: 3) {
                    HStack {
                        Text(alert.driverName)
                            .font(.system(size: 16, weight: .bold))
                            .foregroundColor(.black)
                        
                        Text("• \(alert.relationship)")
                            .font(.caption.weight(.medium))
                            .foregroundColor(.gray)
                    }
                    
                    Text("\(alert.carMake) • \(alert.plateNumber)")
                        .font(.system(size: 13))
                        .foregroundColor(Color(white: 0.3))
                    
                        
                }
            }
            
            // Key impact stats pills
            HStack(spacing: 8) {
                StatPill(label: "Damage", value: String(format: "%.0f%%", alert.cabinDamage))
                StatPill(label: "Impact", value: alert.impactSide)
               // StatPill(label: "Force", value: String(format: "%.0f N", //alert.impactForce))
                //location name display
                HStack(spacing: 5) {
                    Image(systemName: "location.fill")
                        .foregroundColor(.blue)

                    Text(locationName)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(.black)
                }
            }
            
            Divider()
            
            // Action Buttons
            HStack(spacing: 10) {
                Button(action: onTrackLocation) {
                    HStack(spacing: 6) {
                        Image(systemName: "map.fill")
                        Text("See Location")
                    }
                    .font(.system(size: 13, weight: .bold))
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 9)
                    .background(LinearGradient(colors: [Color.blue, Color(red: 0, green: 0.4, blue: 0.9)], startPoint: .leading, endPoint: .trailing))
                    .cornerRadius(9)
                }
                
                Button(action: onViewDetail) {
                    HStack(spacing: 4) {
                        Image(systemName: "info.circle")
                        Text("Details")
                    }
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.black)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 9)
                    .background(Color(.systemGray6))
                    .cornerRadius(9)
                }
                
                Button(action: onAcknowledge) {
                    Image(systemName: "checkmark")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(.green)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 9)
                        .background(Color.green.opacity(0.12))
                        .cornerRadius(9)
                }
            }
        }
        .padding(14)
        .background(Color.white)
        .cornerRadius(16)
        .shadow(color: Color.black.opacity(0.06), radius: 6, y: 3)
        //gettig locatio name ,calling function
        .onAppear {
            getLocationName(alert.location) { name in
                locationName = name
            }
        }
    }
}

struct StatPill: View {
    let label: String
    let value: String
    
    var body: some View {
        HStack(spacing: 4) {
            Text(label + ":")
                .font(.caption2)
                .foregroundColor(.gray)
            Text(value)
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(.black)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Color(.systemGray6))
        .cornerRadius(6)
    }
}

// ================= DETAILS MODAL SHEET =================
struct AlertDetailSheet: View {
    let alert: EmergencyAlert
    var onTrackLocation: () -> Void
    var onAcknowledge: () -> Void
    @Environment(\.presentationMode) var presentationMode
    
    var body: some View {
        NavigationView {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    // Alert Summary Card
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            Text("🚨 EMERGENCY REPORT")
                                .font(.caption.weight(.bold))
                                .foregroundColor(.red)
                            Spacer()
                            Text(alert.time)
                                .font(.caption2)
                                .foregroundColor(.gray)
                        }
                        
                        Text(alert.driverName)
                            .font(.title2.weight(.bold))
                        
                        Text("Relationship: \(alert.relationship)  •  Vehicle: \(alert.carMake) (\(alert.plateNumber))")
                            .font(.subheadline)
                            .foregroundColor(.gray)
                    }
                    .padding(16)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.red.opacity(0.08))
                    .cornerRadius(14)
                    
                    // Driver contact
                    if !alert.driverContact.isEmpty {
                        HStack {
                            Image(systemName: "phone.circle.fill")
                                .font(.system(size: 28))
                                .foregroundColor(.green)
                            VStack(alignment: .leading) {
                                Text("Driver Contact")
                                    .font(.caption)
                                    .foregroundColor(.gray)
                                Text(alert.driverContact)
                                    .font(.subheadline.weight(.semibold))
                            }
                            Spacer()
                            if let phoneUrl = URL(string: "tel://\(alert.driverContact.filter { !" -()".contains($0) })") {
                                Link("Call Now", destination: phoneUrl)
                                    .font(.system(size: 14, weight: .bold))
                                    .foregroundColor(.white)
                                    .padding(.horizontal, 14)
                                    .padding(.vertical, 7)
                                    .background(Color.green)
                                    .cornerRadius(8)
                            }
                        }
                        .padding(14)
                        .background(Color.white)
                        .cornerRadius(12)
                        .shadow(color: Color.black.opacity(0.04), radius: 4)
                    }
                    
                    // Accident Metrics
                    Text("Telemetry & Impact Metrics")
                        .font(.headline.weight(.bold))
                        .padding(.top, 4)
                    
                    VStack(spacing: 10) {
                        HStack {
                            Text("Severity").font(.subheadline).foregroundColor(.gray)
                            Spacer()
                            let info = severityBadgeColors(for: alert.severity)
                            HStack(spacing: 5) {
                                Image(systemName: info.icon)
                                    .font(.system(size: 10, weight: .bold))
                                Text(alert.severity)
                                    .font(.subheadline.weight(.bold))
                            }
                            .foregroundColor(info.text)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 4)
                            .background(info.bg)
                            .cornerRadius(7)
                        }
                        Divider()
                        MetricRow(label: "Impact Direction", value: alert.impactSide)
                        Divider()
                        MetricRow(label: "Impact Force", value: String(format: "%.1f N", alert.impactForce))
                        Divider()
                        MetricRow(label: "Cabin Damage", value: String(format: "%.1f%%", alert.cabinDamage))
                        Divider()
                        MetricRow(label: "GPS Location", value: alert.location)
                       
                    }
                    .padding(14)
                    .background(Color.white)
                    .cornerRadius(12)
                    .shadow(color: Color.black.opacity(0.04), radius: 4)
                    
                    // Actions
                    Button(action: onTrackLocation) {
                        HStack {
                            Image(systemName: "location.fill")
                            Text("See Location on Map & Track")
                                .font(.headline)
                        }
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.blue)
                        .foregroundColor(.white)
                        .cornerRadius(14)
                    }
                    
                    Button(action: onAcknowledge) {
                        HStack {
                            Image(systemName: "checkmark.circle.fill")
                            Text("Acknowledge & Mark as Seen")
                                .font(.headline)
                        }
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.green)
                        .foregroundColor(.white)
                        .cornerRadius(14)
                    }
                }
                .padding(16)
            }
            .navigationTitle("Accident Details")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Close") {
                        presentationMode.wrappedValue.dismiss()
                    }
                }
            }
        }
    }
}

struct MetricRow: View {
    let label: String
    let value: String
    
    var body: some View {
        HStack {
            Text(label).font(.subheadline).foregroundColor(.gray)
            Spacer()
            Text(value).font(.subheadline.weight(.bold)).foregroundColor(.black)
        }
    }
}

// ================= LIVE MAP TRACKING SCREEN =================
struct AccidentLocationTrackingView: View {
    let alert: EmergencyAlert
    @Environment(\.presentationMode) var presentationMode
    
    private let API = AppConfig.apiBaseURL
    
    @State private var region: MKCoordinateRegion
    @State private var coordinate: CLLocationCoordinate2D?
    @State private var isLiveActive: Bool = false
    @State private var liveStatusText: String = "Connecting…"
    @State private var lastUpdateDate: Date? = nil
    @State private var pollingTimer: Timer? = nil
    @State private var tickerTimer: Timer? = nil
    @State private var hasInitiallyCentered: Bool = false
    
    init(alert: EmergencyAlert) {
        self.alert = alert
        let coord = GeolocationService.parseCoordinate(from: alert.location) ?? CLLocationCoordinate2D(latitude: 33.6844, longitude: 73.0479)
        _coordinate = State(initialValue: coord)
        _region = State(initialValue: MKCoordinateRegion(
            center: coord,
            span: MKCoordinateSpan(latitudeDelta: 0.015, longitudeDelta: 0.015)
        ))
    }
    
    var body: some View {
        NavigationView {
            ZStack(alignment: .bottom) {
                // Map
                if let target = coordinate {
                    Map(coordinateRegion: $region, annotationItems: [MapPinItem(coordinate: target)]) { item in
                        MapAnnotation(coordinate: item.coordinate) {
                            VStack(spacing: 2) {
                                Image(systemName: "car.circle.fill")
                                    .font(.system(size: 36))
                                    .foregroundColor(.red)
                                    .background(Circle().fill(Color.white).frame(width: 32, height: 32))
                                    .shadow(color: .red.opacity(0.4), radius: 6)
                                Text(alert.driverName)
                                    .font(.caption2.bold())
                                    .foregroundColor(.white)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(Color.black.opacity(0.75))
                                    .cornerRadius(6)
                            }
                        }
                    }
                    .edgesIgnoringSafeArea(.all)
                    
                    // Floating Top-Right Recenter Button
                    VStack {
                        HStack {
                            Spacer()
                            Button(action: {
                                withAnimation(.easeInOut(duration: 0.5)) {
                                    region.center = target
                                }
                            }) {
                                Image(systemName: "location.fill")
                                    .font(.system(size: 15, weight: .bold))
                                    .foregroundColor(.blue)
                                    .frame(width: 38, height: 38)
                                    .background(Color.white)
                                    .clipShape(Circle())
                                    .shadow(color: Color.black.opacity(0.2), radius: 5, y: 2)
                            }
                            .padding(.trailing, 16)
                            .padding(.top, 16)
                        }
                        Spacer()
                    }
                } else {
                    VStack {
                        Image(systemName: "location.slash.fill")
                            .font(.system(size: 40))
                            .foregroundColor(.gray)
                        Text("Location Coordinates Not Available")
                            .font(.headline)
                            .padding(.top, 4)
                        Text(alert.location)
                            .font(.caption)
                            .foregroundColor(.gray)
                    }
                }
                
                // Floating Bottom Card
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        VStack(alignment: .leading, spacing: 3) {
                            HStack(spacing: 6) {
                                Text("Accident Location")
                                    .font(.caption)
                                    .foregroundColor(.gray)
                                
                                // Live Status Badge
                                HStack(spacing: 4) {
                                    Circle()
                                        .fill(isLiveActive ? Color.green : Color.orange)
                                        .frame(width: 6, height: 6)
                                    Text(liveStatusText)
                                        .font(.system(size: 10, weight: .bold))
                                        .foregroundColor(isLiveActive ? Color.green : Color.orange)
                                }
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background((isLiveActive ? Color.green : Color.orange).opacity(0.12))
                                .cornerRadius(6)
                            }
                            
                            let displayCoord = coordinate != nil ? GeolocationService.formatCoordinate(coordinate!) : alert.location
                            Text(displayCoord)
                                .font(.system(size: 14, weight: .bold, design: .monospaced))
                        }
                        Spacer()
                        if let coord = coordinate {
                            Button(action: {
                                GeolocationService.openAppleMaps(destination: coord, name: "\(alert.driverName) Accident")
                            }) {
                                HStack(spacing: 6) {
                                    Image(systemName: "arrow.triangle.turn.up.right.diamond.fill")
                                    Text("Open Maps")
                                }
                                .font(.system(size: 13, weight: .bold))
                                .foregroundColor(.white)
                                .padding(.horizontal, 14)
                                .padding(.vertical, 8)
                                .background(Color.blue)
                                .cornerRadius(10)
                            }
                        }
                    }
                    
                    HStack(spacing: 12) {
                        Text("Driver: \(alert.driverName)")
                            .font(.caption.weight(.semibold))
                        Text("•")
                        Text("Plate: \(alert.plateNumber)")
                            .font(.caption)
                        Text("•")
                        let info = severityBadgeColors(for: alert.severity)
                        Text("Severity: \(alert.severity)")
                            .font(.caption.weight(.bold))
                            .foregroundColor(info.bg)
                    }
                    .foregroundColor(Color(white: 0.3))
                }
                .padding(16)
                .background(Color.white)
                .cornerRadius(18)
                .shadow(color: Color.black.opacity(0.12), radius: 10, y: -2)
                .padding(14)
            }
            .navigationTitle("Live Driver Location")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        presentationMode.wrappedValue.dismiss()
                    }
                }
            }
            .onAppear {
                startTracking()
            }
            .onDisappear {
                stopTracking()
            }
        }
    }
    
    // ================= LIVE POLLING & MAP CAMERA =================
    private func startTracking() {
        fetchLiveLocation()
        
        // 1. Backend location polling every 3 seconds
        pollingTimer?.invalidate()
        pollingTimer = Timer.scheduledTimer(withTimeInterval: 3.0, repeats: true) { _ in
            fetchLiveLocation()
        }
        
        // 2. Relative time ticker every 1 second
        tickerTimer?.invalidate()
        tickerTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { _ in
            updateStatusText()
        }
    }
    
    private func stopTracking() {
        pollingTimer?.invalidate()
        pollingTimer = nil
        tickerTimer?.invalidate()
        tickerTimer = nil
    }
    
    private func fetchLiveLocation() {
        guard let url = URL(string: "\(API)/DetectAccident/LiveLocation?accidentId=\(alert.accidentId)") else { return }
        
        URLSession.shared.dataTask(with: url) { data, response, error in
            guard let data = data, error == nil else {
                DispatchQueue.main.async {
                    self.updateStatusText()
                }
                return
            }
            
            do {
                if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let lat = json["latitude"] as? Double,
                   let lon = json["longitude"] as? Double,
                   (lat != 0.0 || lon != 0.0) {
                    
                    let newCoord = CLLocationCoordinate2D(latitude: lat, longitude: lon)
                    let status = json["status"] as? String ?? "LIVE"
                    
                    DispatchQueue.main.async {
                        self.coordinate = newCoord
                        self.isLiveActive = (status == "LIVE")
                        self.lastUpdateDate = Date()
                        self.updateStatusText()
                        
                        // Keep camera tracking sensible without fighting user's manual pan/zoom
                        let deltaLat = abs(self.region.center.latitude - newCoord.latitude)
                        let deltaLon = abs(self.region.center.longitude - newCoord.longitude)
                        if !self.hasInitiallyCentered || deltaLat > self.region.span.latitudeDelta * 0.40 || deltaLon > self.region.span.longitudeDelta * 0.40 {
                            withAnimation(.easeInOut(duration: 0.8)) {
                                self.region.center = newCoord
                            }
                            self.hasInitiallyCentered = true
                        }
                    }
                }
            } catch {
                print("Error parsing LiveLocation response: \(error)")
            }
        }.resume()
    }
    
    private func updateStatusText() {
        guard let last = lastUpdateDate else {
            liveStatusText = "Connecting…"
            return
        }
        let elapsed = Int(Date().timeIntervalSince(last))
        if isLiveActive {
            if elapsed <= 2 {
                liveStatusText = "Live • Just now"
            } else if elapsed < 60 {
                liveStatusText = "Live • \(elapsed)s ago"
            } else {
                liveStatusText = "Live • \(elapsed / 60)m ago"
            }
        } else {
            if elapsed < 60 {
                liveStatusText = "Last updated \(elapsed)s ago"
            } else {
                liveStatusText = "Last updated \(elapsed / 60)m ago"
            }
        }
    }
}

struct MapPinItem: Identifiable {
    var id: String = "victim_pin"
    let coordinate: CLLocationCoordinate2D
}
