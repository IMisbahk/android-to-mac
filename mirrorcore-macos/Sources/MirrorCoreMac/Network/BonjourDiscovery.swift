import Foundation

/// Discovers MirrorCore devices on the local network via Bonjour/mDNS.
/// Looks for `_mirrorcore._tcp.` services broadcast by the Android agent.
class BonjourDiscovery: NSObject {
    private var browser: NetServiceBrowser?
    private var discoveredServices: [NetService] = []

    struct DiscoveredDevice {
        let name: String
        let host: String
        let controlPort: UInt16
        let videoPort: UInt16
        let audioPort: UInt16
    }

    var onDeviceFound: ((DiscoveredDevice) -> Void)?
    var onDeviceLost: ((String) -> Void)?

    func startDiscovery() {
        browser = NetServiceBrowser()
        browser?.delegate = self
        browser?.searchForServices(ofType: "_mirrorcore._tcp.", inDomain: "local.")
        Log.info("Bonjour discovery started")
    }

    func stopDiscovery() {
        browser?.stop()
        browser = nil
        discoveredServices.removeAll()
    }
}

extension BonjourDiscovery: NetServiceBrowserDelegate {
    func netServiceBrowser(_ browser: NetServiceBrowser, didFind service: NetService, moreComing: Bool) {
        discoveredServices.append(service)
        service.delegate = self
        service.resolve(withTimeout: 5.0)
        Log.info("Bonjour found: \(service.name)")
    }

    func netServiceBrowser(_ browser: NetServiceBrowser, didRemove service: NetService, moreComing: Bool) {
        discoveredServices.removeAll { $0.name == service.name }
        onDeviceLost?(service.name)
        Log.info("Bonjour lost: \(service.name)")
    }

    func netServiceBrowser(_ browser: NetServiceBrowser, didNotSearch errorDict: [String : NSNumber]) {
        Log.error("Bonjour search failed: \(errorDict)")
    }
}

extension BonjourDiscovery: NetServiceDelegate {
    func netServiceDidResolveAddress(_ sender: NetService) {
        guard let hostName = sender.hostName else { return }

        // Parse TXT record for additional ports
        var videoPort: UInt16 = ConnectionManager.videoPort
        var audioPort: UInt16 = ConnectionManager.audioPort

        if let txtData = sender.txtRecordData() {
            let dict = NetService.dictionary(fromTXTRecord: txtData)
            if let vpData = dict["video_port"], let vpStr = String(data: vpData, encoding: .utf8) {
                videoPort = UInt16(vpStr) ?? videoPort
            }
            if let apData = dict["audio_port"], let apStr = String(data: apData, encoding: .utf8) {
                audioPort = UInt16(apStr) ?? audioPort
            }
        }

        let device = DiscoveredDevice(
            name: sender.name,
            host: hostName,
            controlPort: UInt16(sender.port),
            videoPort: videoPort,
            audioPort: audioPort
        )
        onDeviceFound?(device)
        Log.info("Bonjour resolved: \(device.name) at \(device.host):\(device.controlPort)")
    }

    func netService(_ sender: NetService, didNotResolve errorDict: [String : NSNumber]) {
        Log.error("Bonjour resolve failed for \(sender.name): \(errorDict)")
    }
}
