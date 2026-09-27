import Foundation
import CoreLocation
import MapKit
import Combine

/// Centralized geolocation service and utilities for accident tracking & rescue navigation
class GeolocationService: NSObject, ObservableObject, CLLocationManagerDelegate {
    static let shared = GeolocationService()
    
    private let locationManager = CLLocationManager()
    
    @Published var currentLocation: CLLocation?
    @Published var currentCoordinate: CLLocationCoordinate2D?
    @Published var authorizationStatus: CLAuthorizationStatus = .notDetermined
    @Published var locationError: String?
    
    override init() {
        super.init()
        locationManager.delegate = self
        locationManager.desiredAccuracy = kCLLocationAccuracyBest
        locationManager.distanceFilter = 5.0
        locationManager.requestWhenInUseAuthorization()
        locationManager.startUpdatingLocation()
    }
    
    func startUpdating() {
        locationManager.startUpdatingLocation()
    }
    
    func stopUpdating() {
        locationManager.stopUpdatingLocation()
    }
    
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let loc = locations.last else { return }
        DispatchQueue.main.async {
            self.currentLocation = loc
            self.currentCoordinate = loc.coordinate
        }
    }
    
    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        DispatchQueue.main.async {
            self.locationError = error.localizedDescription
        }
    }
    
    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        DispatchQueue.main.async {
            self.authorizationStatus = manager.authorizationStatus
            if manager.authorizationStatus == .authorizedWhenInUse || manager.authorizationStatus == .authorizedAlways {
                manager.startUpdatingLocation()
            }
        }
    }
    
    // ================= STATIC UTILITIES =================
    
    /// Parse a "latitude,longitude" string into CLLocationCoordinate2D
    static func parseCoordinate(from string: String?) -> CLLocationCoordinate2D? {
        guard let string = string, !string.isEmpty else { return nil }
        let parts = string.components(separatedBy: ",")
        guard parts.count >= 2,
              let lat = Double(parts[0].trimmingCharacters(in: .whitespacesAndNewlines)),
              let lon = Double(parts[1].trimmingCharacters(in: .whitespacesAndNewlines)),
              lat != 0 || lon != 0 else {
            return nil
        }
        return CLLocationCoordinate2D(latitude: lat, longitude: lon)
    }
    
    /// Format coordinate into "lat,lng" string
    static func formatCoordinate(_ coord: CLLocationCoordinate2D) -> String {
        return String(format: "%.6f,%.6f", coord.latitude, coord.longitude)
    }
    
    /// Compute distance in kilometers between two coordinates
    static func distanceInKm(from coord1: CLLocationCoordinate2D, to coord2: CLLocationCoordinate2D) -> Double {
        let loc1 = CLLocation(latitude: coord1.latitude, longitude: coord1.longitude)
        let loc2 = CLLocation(latitude: coord2.latitude, longitude: coord2.longitude)
        return loc1.distance(from: loc2) / 1000.0
    }
    
    /// Open Apple Maps with driving directions to the target coordinate
    static func openAppleMaps(destination: CLLocationCoordinate2D, name: String = "Accident Location") {
        let placemark = MKPlacemark(coordinate: destination)
        let mapItem = MKMapItem(placemark: placemark)
        mapItem.name = name
        let options = [MKLaunchOptionsDirectionsModeKey: MKLaunchOptionsDirectionsModeDriving]
        mapItem.openInMaps(launchOptions: options)
    }
}
