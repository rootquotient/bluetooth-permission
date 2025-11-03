import Flutter
import UIKit
import CoreBluetooth
import CoreLocation

public class BleOperationsPlugin: NSObject, FlutterPlugin, CBPeripheralManagerDelegate, CBCentralManagerDelegate, CLLocationManagerDelegate {

    // Flutter Channels
    private var methodChannel: FlutterMethodChannel?
    private var eventChannel: FlutterEventChannel?
    private var eventSink: FlutterEventSink?

    // BLE Managers
    private var peripheralManager: CBPeripheralManager?
    private var centralManager: CBCentralManager?
    private var locationManager: CLLocationManager?

    // BLE State
    private var currentAdvertisingUUID: String = ""
    private var isAdvertising = false
    private var isScanning = false
    private var scannedDevices: [String: [String: Any]] = [:]

    // Background
    private var backgroundTask: UIBackgroundTaskIdentifier = .invalid
    private var shouldAutoResumeAdvertising = false
    private var backgroundThreadStarted = false
    private var shouldStopBackgroundTasks = false

    // Queue
    private let centralQueue = DispatchQueue.global(qos: .userInitiated)
    private let peripheralQueue = DispatchQueue.global(qos: .userInitiated)

    // MARK: - Plugin Registration
    public static func register(with registrar: FlutterPluginRegistrar) {
        let instance = BleOperationsPlugin()

        let methodChannel = FlutterMethodChannel(
            name: "ble_advertiser_scanner",
            binaryMessenger: registrar.messenger()
        )
        let eventChannel = FlutterEventChannel(
            name: "ble_advertiser_scan_results",
            binaryMessenger: registrar.messenger()
        )

        registrar.addMethodCallDelegate(instance, channel: methodChannel)
        eventChannel.setStreamHandler(instance.createEventStreamHandler() as? NSObject & FlutterStreamHandler)

        instance.methodChannel = methodChannel
        instance.eventChannel = eventChannel

        instance.setupBluetooth()
        instance.setupLocationServices()

        print("✅ BleAdvertiserScannerPlugin registered successfully")
    }

    private func createEventStreamHandler() -> FlutterStreamHandler {
        return EventStreamHandler(
            onListen: { [weak self] sink in
                self?.eventSink = sink
                print("EventSink connected")
            },
            onCancel: { [weak self] in
                self?.eventSink = nil
                print("EventSink disconnected")
            }
        )
    }

    // MARK: - Flutter Method Handler
    public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        switch call.method {
        case "startAdvertising":
            guard let args = call.arguments as? [String: Any],
                  let uuid = args["uuid"] as? String ?? args["serviceUuid"] as? String else {
                result(FlutterError(code: "INVALID_ARGUMENTS", message: "UUID required", details: nil))
                return
            }
            startAdvertising(uuid: uuid)
            result(true)

        case "stopAdvertising":
            stopAdvertising()
            result(true)

        case "startScanning":
            startScanning()
            result(true)

        case "stopScanning":
            stopScanning()
            result(true)

        case "isAdvertising":
            result(isAdvertising)

        case "isScanning":
            result(isScanning)

        case "isBluetoothEnabled":
            result(centralManager?.state == .poweredOn)

        case "getScannedDevices":
            result(Array(scannedDevices.values))

        case "clearScannedDevices":
            scannedDevices.removeAll()
            result(true)

        case "enableBackgroundMode":
            enableBackgroundMode()
            result(true)

        case "disableBackgroundMode":
            disableBackgroundMode()
            result(true)

        case "isBackgroundModeEnabled":
            result(backgroundTask != .invalid)

        case "requestBluetoothPermissions":
            if #available(iOS 13.1, *) {
                let central = CBCentralManager()
                switch central.authorization {
                case .allowedAlways:
                    result(true)
                case .denied, .restricted, .notDetermined:
                    self.locationManager?.requestAlwaysAuthorization()
                    result(true)
                @unknown default:
                    result(false)
                }
            } else {
                result(true)
            }

        default:
            result(FlutterMethodNotImplemented)
        }
    }

    // MARK: - Bluetooth Setup
    private func setupBluetooth() {
        centralManager = CBCentralManager(delegate: self, queue: centralQueue)
        peripheralManager = CBPeripheralManager(delegate: self, queue: peripheralQueue)
    }

    private func setupLocationServices() {
        locationManager = CLLocationManager()
        locationManager?.delegate = self
        locationManager?.requestAlwaysAuthorization()
        if #available(iOS 9.0, *) {
            locationManager?.allowsBackgroundLocationUpdates = true
        }
    }

    // MARK: - Advertising
    private func startAdvertising(uuid: String) {
        guard let peripheralManager = peripheralManager, peripheralManager.state == .poweredOn else {
            print("❌ PeripheralManager not ready")
            return
        }

        peripheralManager.stopAdvertising()
        let serviceUUID = CBUUID(string: uuid)
        let uuidData = uuid.data(using: .utf8) ?? Data()
        let manufacturerData = Data([0xFF, 0xFF]) + uuidData

        let advertisementData: [String: Any] = [
            CBAdvertisementDataLocalNameKey: "FlutterBLE",
            CBAdvertisementDataServiceUUIDsKey: [serviceUUID],
            CBAdvertisementDataManufacturerDataKey: manufacturerData
        ]

        peripheralManager.startAdvertising(advertisementData)
        isAdvertising = true
        currentAdvertisingUUID = uuid
        shouldAutoResumeAdvertising = true

        notifyFlutter(method: "onAdvertisingStarted", args: ["uuid": uuid])
        print("📡 Started advertising with UUID: \(uuid)")
    }

    private func stopAdvertising() {
        peripheralManager?.stopAdvertising()
        isAdvertising = false
        currentAdvertisingUUID = ""
        shouldAutoResumeAdvertising = false
        notifyFlutter(method: "onAdvertisingStopped", args: nil)
        print("🛑 Stopped advertising")
    }

    // MARK: - Scanning
    private func startScanning() {
        guard let centralManager = centralManager, centralManager.state == .poweredOn else {
            print("❌ CentralManager not ready")
            return
        }

        centralManager.stopScan()
        centralManager.scanForPeripherals(withServices: nil, options: [CBCentralManagerScanOptionAllowDuplicatesKey: true])
        isScanning = true
        notifyFlutter(method: "onScanningStarted", args: nil)
        print("🔍 Started scanning")

        DispatchQueue.main.asyncAfter(deadline: .now() + 30) { [weak self] in
            if self?.isScanning == true {
                self?.restartScanning()
            }
        }
    }

    private func stopScanning() {
        centralManager?.stopScan()
        isScanning = false
        notifyFlutter(method: "onScanningStopped", args: nil)
        print("🛑 Stopped scanning")
    }

    private func restartScanning() {
        stopScanning()
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
            self?.startScanning()
        }
    }

    // MARK: - Background Handling
    private func enableBackgroundMode() {
        startBackgroundTask()
        print("🌙 Background mode enabled")
        notifyFlutter(method: "onBackgroundModeEnabled", args: nil)
    }

    private func disableBackgroundMode() {
        stopBackgroundTask()
        print("☀️ Background mode disabled")
        notifyFlutter(method: "onBackgroundModeDisabled", args: nil)
    }

    private func startBackgroundTask() {
        guard !backgroundThreadStarted else { return }
        backgroundThreadStarted = true
        shouldStopBackgroundTasks = false
        backgroundTask = UIApplication.shared.beginBackgroundTask(withName: "BLEBackgroundTask") {
            self.stopBackgroundTask()
        }

        DispatchQueue.global().async { [weak self] in
            self?.backgroundTaskLoop()
        }
    }

    private func stopBackgroundTask() {
        shouldStopBackgroundTasks = true
        if backgroundTask != .invalid {
            UIApplication.shared.endBackgroundTask(backgroundTask)
            backgroundTask = .invalid
        }
        backgroundThreadStarted = false
    }

    private func backgroundTaskLoop() {
        while !shouldStopBackgroundTasks {
            DispatchQueue.main.async { [weak self] in
                if UIApplication.shared.applicationState == .background {
                    if self?.isScanning == true && self?.centralManager?.isScanning == false {
                        self?.startScanning()
                    }
                    if self?.shouldAutoResumeAdvertising == true && self?.peripheralManager?.isAdvertising == false {
                        if let uuid = self?.currentAdvertisingUUID, !uuid.isEmpty {
                            self?.startAdvertising(uuid: uuid)
                        }
                    }
                }
            }
            sleep(2)
        }
    }

    // MARK: - Bluetooth Delegates
    public func centralManagerDidUpdateState(_ central: CBCentralManager) {
        print("🔄 Central state: \(central.state.rawValue)")
        notifyFlutter(method: "onBluetoothStateChanged", args: ["state": central.state.rawValue])
    }

    public func peripheralManagerDidUpdateState(_ peripheral: CBPeripheralManager) {
        print("🔄 Peripheral state: \(peripheral.state.rawValue)")
        notifyFlutter(method: "onPeripheralStateChanged", args: ["state": peripheral.state.rawValue])
    }

    public func centralManager(
        _ central: CBCentralManager,
        didDiscover peripheral: CBPeripheral,
        advertisementData: [String: Any],
        rssi RSSI: NSNumber
    ) {
        let deviceId = peripheral.identifier.uuidString
        let name = peripheral.name ?? (advertisementData[CBAdvertisementDataLocalNameKey] as? String) ?? "Unknown"
        let deviceInfo: [String: Any] = [
            "id": deviceId,
            "name": name,
            "rssi": RSSI.intValue,
            "timestamp": Date().timeIntervalSince1970
        ]

        scannedDevices[deviceId] = deviceInfo
        eventSink?(deviceInfo)
        notifyFlutter(method: "onDeviceDiscovered", args: deviceInfo)
    }

    // MARK: - Location Delegate
    public func locationManager(_ manager: CLLocationManager, didChangeAuthorization status: CLAuthorizationStatus) {
        notifyFlutter(method: "onLocationAuthorizationChanged", args: ["status": status.rawValue])
    }

    // MARK: - Flutter Communication
    private func notifyFlutter(method: String, args: Any?) {
        DispatchQueue.main.async { [weak self] in
            self?.methodChannel?.invokeMethod(method, arguments: args)
        }
    }
}
