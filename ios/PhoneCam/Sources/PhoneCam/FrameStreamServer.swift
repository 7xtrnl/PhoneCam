import Foundation
import Network

/// Einfacher TCP-Server, der auf einem festen Port lauscht.
/// Sobald sich der PC-Client verbindet, werden JPEG-Frames im Format
/// [4 Byte Länge (Big Endian UInt32)] + [JPEG-Bytes] gestreamt.
/// Dieses simple "length-prefixed" Framing macht das Parsing auf der
/// PC-Seite trivial und robust gegen TCP-Paketgrenzen.
final class FrameStreamServer: ObservableObject {

    @Published var isListening = false
    @Published var connectedClientCount = 0
    @Published var localIPAddress: String = "Unbekannt"
    @Published var bytesPerSecond: Double = 0

    let port: NWEndpoint.Port

    private var listener: NWListener?
    private var connections: [NWConnection] = []
    private let queue = DispatchQueue(label: "phonecam.server.queue")

    private var bytesSentSinceLastTick: Int = 0
    private var statsTimer: Timer?

    init(port: UInt16 = 5050) {
        self.port = NWEndpoint.Port(rawValue: port) ?? 5050
    }

    func start() {
        do {
            let params = NWParameters.tcp
            params.allowLocalEndpointReuse = true
            let listener = try NWListener(using: params, on: port)
            listener.newConnectionHandler = { [weak self] connection in
                self?.handleNewConnection(connection)
            }
            listener.stateUpdateHandler = { [weak self] state in
                switch state {
                case .ready:
                    DispatchQueue.main.async { self?.isListening = true }
                case .failed, .cancelled:
                    DispatchQueue.main.async { self?.isListening = false }
                default:
                    break
                }
            }
            listener.start(queue: queue)
            self.listener = listener
            refreshLocalIPAddress()
            startStatsTimer()
        } catch {
            print("Server konnte nicht gestartet werden: \(error)")
        }
    }

    func stop() {
        listener?.cancel()
        listener = nil
        connections.forEach { $0.cancel() }
        connections.removeAll()
        statsTimer?.invalidate()
        DispatchQueue.main.async {
            self.isListening = false
            self.connectedClientCount = 0
        }
    }

    /// Wird vom CameraManager für jeden neuen JPEG-Frame aufgerufen.
    func send(jpegData: Data) {
        guard !connections.isEmpty else { return }

        var lengthPrefix = UInt32(jpegData.count).bigEndian
        let header = Data(bytes: &lengthPrefix, count: 4)
        let payload = header + jpegData

        for connection in connections {
            connection.send(content: payload, completion: .contentProcessed { [weak self] error in
                if error == nil {
                    self?.bytesSentSinceLastTick += payload.count
                }
            })
        }
    }

    // MARK: - Private

    private func handleNewConnection(_ connection: NWConnection) {
        connection.stateUpdateHandler = { [weak self] state in
            switch state {
            case .ready:
                self?.queue.async {
                    self?.connections.append(connection)
                    DispatchQueue.main.async {
                        self?.connectedClientCount = self?.connections.count ?? 0
                    }
                }
            case .failed, .cancelled:
                self?.queue.async {
                    self?.connections.removeAll { $0 === connection }
                    DispatchQueue.main.async {
                        self?.connectedClientCount = self?.connections.count ?? 0
                    }
                }
            default:
                break
            }
        }
        connection.start(queue: queue)
    }

    private func startStatsTimer() {
        DispatchQueue.main.async { [weak self] in
            self?.statsTimer?.invalidate()
            self?.statsTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
                guard let self else { return }
                self.bytesPerSecond = Double(self.bytesSentSinceLastTick)
                self.bytesSentSinceLastTick = 0
            }
        }
    }

    private func refreshLocalIPAddress() {
        var address = "Unbekannt"
        var ifaddrPtr: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddrPtr) == 0, let firstAddr = ifaddrPtr else {
            self.localIPAddress = address
            return
        }
        defer { freeifaddrs(ifaddrPtr) }

        var ptr: UnsafeMutablePointer<ifaddrs>? = firstAddr
        while let current = ptr {
            let interface = current.pointee
            let addrFamily = interface.ifa_addr.pointee.sa_family
            if addrFamily == UInt8(AF_INET) {
                let name = String(cString: interface.ifa_name)
                // "en0" ist das WLAN-Interface auf iOS-Geräten
                if name == "en0" {
                    var hostname = [CChar](repeating: 0, count: Int(NI_MAXHOST))
                    getnameinfo(
                        interface.ifa_addr,
                        socklen_t(interface.ifa_addr.pointee.sa_len),
                        &hostname,
                        socklen_t(hostname.count),
                        nil,
                        0,
                        NI_NUMERICHOST
                    )
                    address = String(cString: hostname)
                }
            }
            ptr = current.pointee.ifa_next
        }
        DispatchQueue.main.async { self.localIPAddress = address }
    }
}
