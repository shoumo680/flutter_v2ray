import Flutter
import UIKit

public class FlutterV2rayPlugin: NSObject, FlutterPlugin {
    
    private let channel: FlutterMethodChannel
    private let vpnManager = VPNManager.shared
    
    let suiteName: String = {
        let identifier = Bundle.main.infoDictionary?["CFBundleIdentifier"] as! String
        return "group.\(identifier)"
    }()
    
    init(channel: FlutterMethodChannel) {
        self.channel = channel
    }
    
    public static func register(with registrar: FlutterPluginRegistrar) {
        let channel = FlutterMethodChannel(name: "flutter_v2ray", binaryMessenger: registrar.messenger())
        let instance = FlutterV2rayPlugin(channel: channel)
        registrar.addMethodCallDelegate(instance, channel: channel)
    }
    
    public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        switch call.method {
        case "startV2Ray":
            Task.init {
                do {
                    let arg = call.arguments as! [String : NSObject]
                    try await vpnManager.installVPNConfiguration()
                    let controller = await vpnManager.loadController()
                    if(controller == nil) {
                        result(false)
                        return
                    }
                    try await Task.sleep(nanoseconds: 100_000_000)//0.1s
                    
                    try await controller?.startVPN(socksPort: arg["socksPort"] as! Int,config: arg["config"] as! String)
                } catch {
                    result(false)
                    return
                }
                result(nil)
            }
            
        case "stopV2Ray":
            vpnManager.controller?.stopVPN()
            result(nil)
            
        case "initializeV2Ray":
            result(nil)
            
        case "getServerDelay":
            result(nil)
            
        case "requestPermission":
            result(true)
            
        default:
            result(FlutterMethodNotImplemented)
        }
    }
}
