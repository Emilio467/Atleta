import Flutter
import HealthKit
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)

    if let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "AtletaHealthAvailability") {
      let channel = FlutterMethodChannel(
        name: "br.com.atleta/health",
        binaryMessenger: registrar.messenger()
      )
      channel.setMethodCallHandler { call, result in
        if call.method == "isAvailable" {
          result(HKHealthStore.isHealthDataAvailable())
        } else {
          result(FlutterMethodNotImplemented)
        }
      }
    }
  }
}
