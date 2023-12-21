import NetworkExtension
import Combine

@MainActor
final class VPNManager: ObservableObject {
    
    public static let shared = VPNManager()

    private let providerBundleIdentifier: String = {
        let identifier = Bundle.main.infoDictionary?["CFBundleIdentifier"] as! String
        return "\(identifier).PacketTunnel"
    }()
    
    private var cancellables: Set<AnyCancellable> = []
    
    @Published private var manager: NETunnelProviderManager?
    
    @Published private(set) var isProcessing: Bool = false
    
    var status: NEVPNStatus? {
        manager.flatMap { $0.connection.status }
    }
    
    var connectedDate: Date? {
        manager.flatMap { $0.connection.connectedDate }
    }
    
    init() {
        isProcessing = true
        Task(priority: .userInitiated) {
            await self.reload()
//            do {
//                try await Task.sleep(for: .milliseconds(250))
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                    // 延时后要执行的代码
                    self.isProcessing = false
                }
//            } catch {
//                debugPrint(error.localizedDescription)
//            }
//            await MainActor.run {
//                isProcessing = false
//            }
        }
    }
    
    func reload() async {
        self.cancellables.removeAll()
        self.manager = await self.loadTunnelProviderManager()
        NotificationCenter.default
            .publisher(for: .NEVPNConfigurationChange, object: nil)
            .receive(on: DispatchQueue.main)
            .sink { [unowned self] _ in
                Task(priority: .high) {
                    self.manager = await self.loadTunnelProviderManager()
                }
            }
            .store(in: &cancellables)
        NotificationCenter.default
            .publisher(for: .NEVPNStatusDidChange)
            .receive(on: DispatchQueue.main)
            .sink { [unowned self] _ in objectWillChange.send() }
            .store(in: &cancellables)
    }
    
    func saveToPreferences() async throws {
        let manager = NETunnelProviderManager()
//        manager.localizedDescription = "Xray"
        manager.protocolConfiguration = {
            let configuration = NETunnelProviderProtocol()
            configuration.providerBundleIdentifier = self.providerBundleIdentifier
            configuration.serverAddress = "Proxy"
            configuration.disconnectOnSleep = false

            configuration.providerConfiguration = [:]
            if #available(iOS 14.2, *) {
                configuration.providerConfiguration = [:]
                configuration.excludeLocalNetworks = true
    //            config.includeAllNetworks = true
            }
            return configuration
        }()
        manager.isEnabled = true
        manager.isOnDemandEnabled = true

        try await manager.saveToPreferences()
    }

    func removeFromPreferences() async throws {
        guard let manager = manager else {
            return
        }
        try await manager.removeFromPreferences()
    }
    
    func start(socksPort:Int,config:String) async throws {
        guard let manager = manager else {
            return
        }
        if !manager.isEnabled {
            manager.isEnabled = true
            try await manager.saveToPreferences()
        }
        let options = ["socksPort" : socksPort as NSObject,"config" : config as NSObject]
        try manager.connection.startVPNTunnel(options: options)
    }
    
    func stop() {
        guard let manager = manager else {
            return
        }
        manager.connection.stopVPNTunnel()
    }
    
    @discardableResult
    func sendProviderMessage(data: Data) async throws -> Data? {
        guard let manager = manager else {
            return nil
        }
        return try await withCheckedThrowingContinuation { continuation in
            do {
                try (manager.connection as! NETunnelProviderSession).sendProviderMessage(data) {
                    continuation.resume(with: .success($0))
                }
            } catch {
                continuation.resume(with: .failure(error))
            }
        }
    }

    private func loadTunnelProviderManager() async -> NETunnelProviderManager? {
        do {
            let managers = try await NETunnelProviderManager.loadAllFromPreferences()
            guard let reval = managers.first(where: {
                guard let configuration = $0.protocolConfiguration as? NETunnelProviderProtocol else {
                    return false
                }
                return configuration.providerBundleIdentifier == self.providerBundleIdentifier
            }) else {
                return nil
            }
            try await reval.loadFromPreferences()
            return reval
        } catch {
            return nil
        }
    }
}
