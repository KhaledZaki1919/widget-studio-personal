import CoreLocation
import Observation
import SwiftUI
import WidgetKitCore

/// The phone's compass heading while the Qibla screen is open.
@MainActor
@Observable
final class HeadingModel: NSObject, CLLocationManagerDelegate {
    private(set) var heading: Double?
    /// Degrees; negative when the compass has no valid reading.
    private(set) var accuracy: Double = -1
    let isAvailable = CLLocationManager.headingAvailable()

    @ObservationIgnored private let manager = CLLocationManager()

    override init() {
        super.init()
        manager.delegate = self
        manager.headingFilter = 1
    }

    func start() {
        guard isAvailable else { return }
        manager.headingOrientation = .portrait
        manager.startUpdatingHeading()
        // True north needs a location; magnetic north is used until there is one.
        if [.authorizedWhenInUse, .authorizedAlways].contains(manager.authorizationStatus) {
            manager.desiredAccuracy = kCLLocationAccuracyKilometer
            manager.startUpdatingLocation()
        }
    }

    func stop() {
        manager.stopUpdatingHeading()
        manager.stopUpdatingLocation()
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateHeading newHeading: CLHeading) {
        // True north when location is known, else magnetic north.
        let value = newHeading.trueHeading >= 0 ? newHeading.trueHeading : newHeading.magneticHeading
        let accuracy = newHeading.headingAccuracy
        Task { @MainActor in
            self.heading = value
            self.accuracy = accuracy
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {}

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {}

    nonisolated func locationManagerShouldDisplayHeadingCalibration(_ manager: CLLocationManager) -> Bool {
        false
    }
}

/// Live Qibla compass (M4 feedback): the dial turns with the phone, the needle points to the
/// Qibla, a haptic confirms alignment. The Qibla widget opens it (`widgetstudio://qibla`).
struct QiblaView: View {
    @Environment(LiveDataModel.self) private var live
    @State private var compass = HeadingModel()
    @State private var aligned = false
    /// Follows Dynamic Type (M6).
    @ScaledMetric(relativeTo: .largeTitle) private var degreesSize: CGFloat = 44

    private var qibla: Double? {
        live.inputs.location.map { PrayerCalculator.qibla(latitude: $0.latitude, longitude: $0.longitude) }
    }

    var body: some View {
        VStack(spacing: 24) {
            if let qibla {
                if let heading = compass.heading {
                    dial(qibla: qibla, heading: heading)
                } else {
                    dial(qibla: qibla, heading: 0).opacity(0.35)
                    Text(compass.isAvailable ? "compass.waiting" : "compass.noCompass")
                        .font(M3Type.bodyMedium).foregroundStyle(M3.onSurfaceVariant).multilineTextAlignment(.center)
                }
                Text(verbatim: "\(Int(qibla.rounded()))°")
                    .font(.system(size: degreesSize, weight: .bold, design: .rounded)).monospacedDigit()
                    .accessibilityIdentifier("ax.qibla.degrees")
                Text("compass.fromNorth").font(M3Type.bodySmall).foregroundStyle(M3.onSurfaceVariant)
                if aligned {
                    Label("compass.aligned", systemImage: "checkmark.circle.fill")
                        .font(M3Type.titleMedium).foregroundStyle(M3.success)
                }
                if compass.heading != nil, QiblaCompass.needsCalibration(accuracy: compass.accuracy) {
                    Label("compass.calibrate", systemImage: "figure.wave")
                        .font(M3Type.bodySmall).foregroundStyle(M3.warning).multilineTextAlignment(.center)
                        .padding(12)
                        .background(RoundedRectangle(cornerRadius: M3Shape.medium, style: .continuous).fill(M3.surfaceContainerHigh))
                }
            } else {
                ContentUnavailableView {
                    Label("compass.noLocation", systemImage: "location.slash")
                } description: {
                    Text("compass.noLocation.body")
                } actions: {
                    if live.authorization == .notDetermined {
                        Button("settings.location.allow", action: live.requestLocation)
                    }
                }
            }
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .navigationTitle("compass.title")
        .navigationBarTitleDisplayMode(.inline)
        .sensoryFeedback(trigger: aligned) { _, now in now ? .success : nil }
        .onAppear(perform: compass.start)
        .onDisappear(perform: compass.stop)
        .onChange(of: compass.heading) { _, heading in
            guard let heading, let qibla else { return }
            aligned = QiblaCompass.isAligned(needle: QiblaCompass.needleAngle(qibla: qibla, heading: heading), wasAligned: aligned)
        }
        .task { await live.refresh() }
    }

    /// A dial whose north turns against the heading, with the Qibla needle on top.
    private func dial(qibla: Double, heading: Double) -> some View {
        let needle = QiblaCompass.needleAngle(qibla: qibla, heading: heading)
        return ZStack {
            Circle().stroke(Color.secondary.opacity(0.3), lineWidth: 2)
            ForEach(0..<72, id: \.self) { tick in
                Capsule()
                    .fill(Color.secondary.opacity(tick % 18 == 0 ? 0.9 : 0.35))
                    .frame(width: 2, height: tick % 18 == 0 ? 14 : 7)
                    .offset(y: -128)
                    .rotationEffect(.degrees(Double(tick) * 5))
            }
            Text(verbatim: "N")
                .font(M3Type.titleMedium).foregroundStyle(M3.error)
                .offset(y: -104)
        }
        .rotationEffect(.degrees(-heading))
        .overlay {
            VStack(spacing: 0) {
                Image(systemName: "location.north.fill")
                    .font(.system(size: 34))
                    .foregroundStyle(aligned ? Color.green : M3.primary)
                Capsule().fill(aligned ? M3.success : M3.primary).frame(width: 4, height: 70)
                Spacer()
            }
            .frame(height: 220)
            .rotationEffect(.degrees(needle))
            Image(systemName: "building.columns.fill")
                .font(.title2)
                .foregroundStyle(aligned ? M3.success : M3.onSurface)
                .offset(y: -150)
                .rotationEffect(.degrees(needle))
        }
        .frame(width: 270, height: 270)
        .padding(.top, 30)
        .animation(.easeOut(duration: 0.15), value: heading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("compass.title"))
        .accessibilityValue(Text(verbatim: "\(Int(needle.rounded()))°"))
    }
}
