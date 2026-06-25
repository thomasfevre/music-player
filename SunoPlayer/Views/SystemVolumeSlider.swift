import SwiftUI
import MediaPlayer

// MARK: - SystemVolumeSlider
/// Wraps `MPVolumeView` so the now-playing screen can control the real device output volume
/// (and follow route/AirPlay changes). Note: renders inert in the Simulator — test on device.
struct SystemVolumeSlider: UIViewRepresentable {
    var tint: Color

    func makeUIView(context: Context) -> MPVolumeView {
        let view = MPVolumeView(frame: .zero)
        view.showsRouteButton = false
        applyTint(to: view)
        return view
    }

    func updateUIView(_ uiView: MPVolumeView, context: Context) {
        applyTint(to: uiView)
    }

    private func applyTint(to view: MPVolumeView) {
        guard let slider = view.subviews.compactMap({ $0 as? UISlider }).first else { return }
        slider.minimumTrackTintColor = UIColor(tint)
        slider.maximumTrackTintColor = UIColor.white.withAlphaComponent(0.15)
    }
}
