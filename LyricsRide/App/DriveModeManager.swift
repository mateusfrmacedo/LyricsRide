import CoreLocation
import Foundation
import UIKit

/// Keeps an opt-in driving session alive while the iPhone is locked, using a
/// deliberately low-power location session. Location fixes are discarded;
/// this is only for personal, on-device testing and must stay user-controlled.
@MainActor
final class DriveModeManager: NSObject, ObservableObject, CLLocationManagerDelegate {
    @Published private(set) var isRunning = false
    @Published private(set) var status = "Desativado"
    @Published private(set) var isCarPlayConnected = false
    @Published var autoStartLiveActivityOnCarPlay: Bool {
        didSet { UserDefaults.standard.set(autoStartLiveActivityOnCarPlay, forKey: "autoStartLiveActivityOnCarPlay") }
    }

    private let locationManager = CLLocationManager()
    private var wantsRunning = false
    private var screenObservers: [NSObjectProtocol] = []

    var shouldStartLiveActivityForCarPlay: Bool {
        autoStartLiveActivityOnCarPlay && isCarPlayConnected
    }

    override init() {
        autoStartLiveActivityOnCarPlay = UserDefaults.standard.object(forKey: "autoStartLiveActivityOnCarPlay") as? Bool ?? true
        super.init()
        locationManager.delegate = self
        locationManager.desiredAccuracy = kCLLocationAccuracyThreeKilometers
        locationManager.distanceFilter = 1_000
        locationManager.activityType = .automotiveNavigation
        locationManager.pausesLocationUpdatesAutomatically = false

        // A Live Activity is displayed on CarPlay's Dashboard without requiring
        // this app to draw its own CarPlay UI. Watch scene connections so an
        // already-running app can react the moment the car connects.
        screenObservers = [
            NotificationCenter.default.addObserver(
                forName: UIScene.willConnectNotification,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                Task { @MainActor in self?.refreshCarPlayConnection() }
            },
            NotificationCenter.default.addObserver(
                forName: UIScene.didDisconnectNotification,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                Task { @MainActor in self?.refreshCarPlayConnection() }
            }
        ]
        refreshCarPlayConnection()
    }

    deinit {
        screenObservers.forEach(NotificationCenter.default.removeObserver)
    }

    func refreshCarPlayConnection() {
        isCarPlayConnected = UIScreen.screens.contains {
            $0.traitCollection.userInterfaceIdiom == .carPlay
        }
    }

    func start() {
        guard !isRunning else { return }
        wantsRunning = true

        switch locationManager.authorizationStatus {
        case .notDetermined:
            status = "Solicitando permissão de localização"
            locationManager.requestWhenInUseAuthorization()
        case .denied, .restricted:
            wantsRunning = false
            status = "Permita a localização para usar o Modo Direção"
        case .authorizedWhenInUse, .authorizedAlways:
            activate()
        @unknown default:
            wantsRunning = false
            status = "Não foi possível iniciar o Modo Direção"
        }
    }

    func stop() {
        wantsRunning = false
        locationManager.stopUpdatingLocation()
        locationManager.allowsBackgroundLocationUpdates = false
        isRunning = false
        status = "Desativado"
    }

    private func activate() {
        guard wantsRunning, !isRunning else { return }
        locationManager.allowsBackgroundLocationUpdates = true
        locationManager.startUpdatingLocation()
        isRunning = true
        status = "Ativo — letras continuam na tela bloqueada"

        // "Sempre" permite que uma automação de CarPlay inicie a sessão no
        // futuro. A localização nunca é lida, armazenada ou enviada.
        if locationManager.authorizationStatus == .authorizedWhenInUse {
            locationManager.requestAlwaysAuthorization()
        }
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        Task { @MainActor [weak self] in
            guard let self, self.wantsRunning else { return }
            switch manager.authorizationStatus {
            case .authorizedWhenInUse, .authorizedAlways:
                self.activate()
            case .denied, .restricted:
                self.wantsRunning = false
                self.isRunning = false
                self.status = "Permissão de localização negada"
            default:
                break
            }
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        Task { @MainActor [weak self] in
            self?.status = "Modo Direção indisponível: \(error.localizedDescription)"
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        // Intencionalmente vazio: os dados de localização são descartados.
    }
}
