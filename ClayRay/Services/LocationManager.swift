import CoreLocation
import Foundation

@MainActor
final class LocationManager: NSObject, ObservableObject {
    @Published var latitude: Double = 39.3988   // Carbondale, CO default
    @Published var longitude: Double = -107.2117
    @Published var locationName: String = "Carbondale, CO"
    @Published var isAuthorized = false
    @Published var authorizationDenied = false

    private let manager = CLLocationManager()
    private let geocoder = CLGeocoder()

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyKilometer
    }

    func requestPermission() {
        manager.requestWhenInUseAuthorization()
    }

    func requestLocation() {
        manager.requestLocation()
    }

    func reverseGeocode(latitude: Double, longitude: Double) async -> String? {
        let location = CLLocation(latitude: latitude, longitude: longitude)
        do {
            let placemarks = try await geocoder.reverseGeocodeLocation(location)
            if let place = placemarks.first {
                let city = place.locality ?? place.name ?? ""
                let state = place.administrativeArea ?? ""
                if !city.isEmpty && !state.isEmpty {
                    return "\(city), \(state)"
                }
                return city.isEmpty ? state : city
            }
        } catch {
            // Fall through
        }
        return nil
    }
}

extension LocationManager: CLLocationManagerDelegate {
    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
        Task { @MainActor in
            self.latitude = location.coordinate.latitude
            self.longitude = location.coordinate.longitude
            if let name = await self.reverseGeocode(latitude: self.latitude, longitude: self.longitude) {
                self.locationName = name
            }
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        // Keep using defaults (Carbondale, CO)
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        Task { @MainActor in
            switch manager.authorizationStatus {
            case .authorizedAlways:
                self.isAuthorized = true
                self.authorizationDenied = false
                manager.requestLocation()
            case .denied, .restricted:
                self.isAuthorized = false
                self.authorizationDenied = true
            case .notDetermined:
                self.isAuthorized = false
                self.authorizationDenied = false
            @unknown default:
                break
            }
        }
    }
}
