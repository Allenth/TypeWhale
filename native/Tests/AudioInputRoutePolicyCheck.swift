import Foundation
import CoreAudio

@main
struct AudioInputRoutePolicyCheck {
    static func main() {
        let builtIn = AudioInputDevice(id: 1, uid: "builtin", name: "MacBook Microphone", isDefault: true)
        let usb = AudioInputDevice(id: 2, uid: "usb", name: "USB Mic", isDefault: false)
        let airPods = AudioInputDevice(id: 3, uid: "airpods", name: "Wayne's AirPods Pro", isDefault: true)
        let px7 = AudioInputDevice(
            id: 4,
            uid: "px7",
            name: "Kingway’s B&W PX7",
            isDefault: true,
            transportType: kAudioDeviceTransportTypeBluetooth
        )
        let localizedBuiltIn = AudioInputDevice(
            id: 5,
            uid: "localized-builtin",
            name: "MacBook Pro麦克风",
            isDefault: false,
            transportType: kAudioDeviceTransportTypeBuiltIn
        )

        precondition(
            AudioInputRoutePolicy.resolve(
                selectedUID: "usb",
                devices: [builtIn, usb],
                defaultDeviceID: 1
            ) == .manual(usb)
        )
        precondition(
            AudioInputRoutePolicy.resolve(
                selectedUID: "usb",
                devices: [builtIn],
                defaultDeviceID: 1
            ) == .downgradeToSystemDefault(builtIn)
        )
        precondition(
            AudioInputRoutePolicy.resolve(
                selectedUID: "",
                devices: [builtIn],
                defaultDeviceID: 1
            ) == .systemDefault(builtIn)
        )
        precondition(
            AudioInputRoutePolicy.resolve(
                selectedUID: "",
                devices: [],
                defaultDeviceID: nil
            ) == .unavailable
        )
        precondition(
            AudioInputRoutePolicy.resolve(
                selectedUID: "",
                devices: [airPods, builtIn],
                defaultDeviceID: 3,
                preferBuiltInMicForBluetoothSystemDefault: true
            ) == .preferredBuiltIn(builtIn, originalDefault: airPods)
        )
        precondition(
            AudioInputRoutePolicy.resolve(
                selectedUID: "usb",
                devices: [airPods, builtIn, usb],
                defaultDeviceID: 3,
                preferBuiltInMicForBluetoothSystemDefault: true
            ) == .manual(usb)
        )
        precondition(
            AudioInputRoutePolicy.resolve(
                selectedUID: "",
                devices: [px7, localizedBuiltIn],
                defaultDeviceID: 4,
                preferBuiltInMicForBluetoothSystemDefault: true
            ) == .preferredBuiltIn(localizedBuiltIn, originalDefault: px7)
        )

        var generation = AudioInputSwitchGeneration()
        let first = generation.issue(targetUID: "usb")
        let latest = generation.issue(targetUID: "builtin")
        precondition(!generation.accepts(first))
        precondition(generation.accepts(latest))

        print("AudioInputRoutePolicyCheck passed")
    }
}
