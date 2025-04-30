import Foundation
import CoreBluetooth
import AccessorySetupKit
import SwiftUI
import NetworkExtension
import Capacitor


@available(iOS 18.0, *)
class DeviceManager: NSObject, CBCentralManagerDelegate {
    typealias Callback = (_ success: Bool, _ message: String) -> Void
    typealias StateReceiver = (_ enabled: Bool) -> Void
    typealias ScanResultCallback = (_ device: Device, _ advertisementData: [String: Any], _ rssi: NSNumber) -> Void
    typealias AccResultCallback = (_ device: Device, _ service_id: CBUUID, _ companyIdentifier: ASBluetoothCompanyIdentifier, _ rssi: NSNumber) -> Void

    private var centralManager: CBCentralManager!
    private var viewController: UIViewController?
    private var displayStrings: [String: String]!
    private var callbackMap = [String: Callback]()
    private var scanResultCallback: ScanResultCallback?
    private var accResultCallback: AccResultCallback?
    private var stateReceiver: StateReceiver?
    private var timeoutMap = [String: DispatchWorkItem]()
    private var stopScanWorkItem: DispatchWorkItem?
    private var alertController: UIAlertController?
    private var discoveredDevices = [String: Device]()
    private var deviceNameFilter: String?
    private var deviceNamePrefixFilter: String?
    private var shouldShowDeviceList = false
    private var allowDuplicates = false

    
    
    private var session = ASAccessorySession()
    private var networkSession = NEHotspotConfigurationManager()


    init(_ viewController: UIViewController?, _ displayStrings: [String: String], _ callback: @escaping Callback) {
        super.init()
        self.viewController = viewController
        self.displayStrings = displayStrings
        self.callbackMap["initialize"] = callback
        self.session.activate(on: DispatchQueue.main, eventHandler: handleSessionEvent(event:))
        self.centralManager = CBCentralManager(delegate: self, queue: DispatchQueue.main)
        
        
    }

    func setDisplayStrings(_ displayStrings: [String: String]) {
        self.displayStrings = displayStrings
    }

    // initialize
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        let initializeKey = "initialize"
        switch central.state {
        case .poweredOn:
            self.resolve(initializeKey, "BLE powered on")
            self.emitState(enabled: true)
        case .poweredOff:
            self.stopScan()
            self.resolve(initializeKey, "BLE powered off")
            self.emitState(enabled: false)
        case .resetting:
            self.emitState(enabled: false)
        case .unauthorized:
            self.reject(initializeKey, "BLE permission denied")
            self.emitState(enabled: false)
        case .unsupported:
            self.reject(initializeKey, "BLE unsupported")
            self.emitState(enabled: false)
        case .unknown:
            self.emitState(enabled: false)
        default: break
        }
    }

    func isEnabled() -> Bool {
        return self.centralManager.state == CBManagerState.poweredOn
    }

    func registerStateReceiver( _ stateReceiver: @escaping StateReceiver) {
        self.stateReceiver = stateReceiver
    }

    func unregisterStateReceiver() {
        self.stateReceiver = nil
    }

    func emitState(enabled: Bool) {
        guard let stateReceiver = self.stateReceiver else { return }
        stateReceiver(enabled)
    }

    
    
    @available(iOS 18.0, *)
    func startAccessorySearch(items: [ASPickerDisplayItem], _ AccResultCallback: @escaping AccResultCallback) {
        self.accResultCallback = AccResultCallback

        var displayItems: [ASPickerDisplayItem] = items
        print("Starting accessory search")
           
        print("Display items: \(displayItems)")
        session.showPicker(for: displayItems) { error in
            if let error {
                print("Failed to show picker due to: \(error.localizedDescription)")
            }
        }
    }


    @available(iOS 18.0, *)
    private func handleSessionEvent(event: ASAccessoryEvent) {
        switch event.eventType {
        case .activated:
            // Use previously-discovered accessories in session.accessories, if necessary.
            print("Activated event")
            let accessories = session.accessories
            print(accessories)
        case .accessoryAdded:
            // Handle addition of an accessory by person using the app.
            print("Accessory added: \(event.eventType)")
            guard let accessory = event.accessory else { return }
            print(accessory)
            print (accessory.bluetoothIdentifier)
            print (accessory.bluetoothTransportBridgingIdentifier)
            print (accessory.state)
            
            if let peripheralUUID = accessory.bluetoothIdentifier {
                print("getting peripheral version")
                print (peripheralUUID)
                           let peripheral = self.centralManager.retrievePeripherals(withIdentifiers: [peripheralUUID]).first
                print (peripheral)
                if (peripheral == nil) {return}
                
                let device: Device = Device(peripheral!)
                print (device)
                let RSSI = peripheral?.readRSSI()
                print(RSSI)
                if DeviceManager.AccResultCallback.self != nil {
                    self.accResultCallback!(device,      accessory.descriptor.bluetoothServiceUUID!,
                                            accessory.descriptor.bluetoothCompanyIdentifier, 12313)
                } else {
                    print("no callback for accessory added")
                    //In this context, "NetworkExtension" really means "NEHotspotConfigurationManager". Also, just so this is the clear, the big benefit of this flow for a WiFi accessory is that it means your app will be able to automatically reconnect to it's paired accessory without any additional user interaction. That's a huge improvement to NEHotspotConfigurationManager.
                    
                    ///joinAccessoryHotspotWithoutSecurity
                    ///joinAccessoryHotspot
                    
                }
            } else if let ssid = accessory.ssid {
                print("attempting to join accessory hotspot")
                // Create a `NEHotspotConfiguration` with this SSID to configure.
                //let configuration = NEHotspotConfiguration(ssid: sside)
                //print ("configuration: \(configuration)")
                //self.hotspotConfigManager.apply(configuration)

                //configuration.apply()

                let restul = self.networkSession.joinAccessoryHotspotWithoutSecurity(accessory) { error in
                print ("completed i guess  \(error)")
                    if let error = error {
                        print("Failed to join accessory hotspot: \(error)")
                    } else { 
                        print("Successfully joined accessory hotspot")
                        print("joined accessory hotspot")
                // Register to receive UDP broadcast on port 15000
                let udpListener: NWListener
                do {
                    let parameters = NWParameters.udp
                    parameters.allowLocalEndpointReuse = true
                    parameters.requiredInterfaceType = .wifi
                    udpListener = try NWListener(using: parameters, on: 15000)
                } catch {
                    print("Failed to create UDP listener: \(error)")
                    return
                }
                
                udpListener.stateUpdateHandler = { newState in
                    switch newState {
                    case .ready:
                        print("UDP listener is ready on port 15000")
                    case .failed(let error):
                        print("UDP listener failed with error: \(error)")
                        // Attempt to restart the listener
                  
                    case .cancelled:
                        print("UDP listener cancelled")
                    default:
                        break
                    }
                }
                
                udpListener.newConnectionHandler = { newConnection in
                    newConnection.start(queue: .global())
                    self.receivePackets(on: newConnection)
                }
                
                udpListener.start(queue: .global())
                
                // Set up TCP connection
                let tcpConnection = NWConnection(host: "192.168.1.1", port: 15001, using: .tcp)
                tcpConnection.stateUpdateHandler = { state in
                    switch state {
                    case .ready:
                        print("TCP connection is ready")
                        // Send "!" to enable data output mode
                        if let data = "!".data(using: .utf8) {
                            tcpConnection.send(content: data, completion: .contentProcessed { error in
                                if let error = error {
                                    print("Failed to send data output mode command: \(error)")
                                } else {
                                    print("Data output mode enabled")
                                }
                            })
                        }
                    case .failed(let error):
                        print("TCP connection failed: \(error)")
                        // Attempt to reconnect
                        tcpConnection.restart()
                    case .cancelled:
                        print("TCP connection cancelled")
                    default:
                        break
                    }
                }
                
                tcpConnection.start(queue: .global())
                    }
                }
                print("joined accessory with result: \(restul)" )
                

            }
        case .accessoryRemoved, .accessoryChanged:
            // Handle removal or change of previously-added accessory, if necessary.
            print("Accessory removed or changed: \(event.eventType)")
            guard let accessory = event.accessory else { return }
            print(accessory)
            
        case .invalidated:
            // The session is now invalid and you can't use it further.
            print("Session invalidated: \(event.eventType)")
        case .migrationComplete:
            // Handle migration. TEST
            print("Migration complete: \(event.eventType)")
        case .pickerDidPresent:
            // Update state for picker appearing, if necessary.
            print ("picker did present")
        case .pickerDidDismiss:
            // Update state for picker disappearing, if necessary.
            print ("picker did dismiss")
        case .unknown:
            // Handle unknown event type, if appropriate.
            print("Received unknown event type: \(event.eventType)")
        @unknown default:
            // Reserve this space for yet-to-be-defined event types.
            print("Received unhandled event type: \(event.eventType)")
        }
    }
    
    
    func stateDidChange(to state: NWConnection.State) {
        switch state {
        case .ready:
            print("Connection is ready")
        case .waiting(let error):
            print("Connection is waiting with error: \(error)")
        case .failed(let error):
            print("Connection failed with error: \(error)")
        case .setup:
            print("Connection is being set up")
        case .preparing:
            print("Connection is preparing")
        case .cancelled:
            print("Connection was cancelled")
        @unknown default:
            print("Unknown connection state")
        }
    }

    func receivePackets(on connection: NWConnection) {
        connection.receiveMessage { (data, context, isComplete, error) in
            if let error = error {
                print("Error receiving packet: \(error)")
                return
            }
            
            guard let data = data, !data.isEmpty else {
                print("Received empty packet")
                return
            }
            
            print("Received packet of size: \(data.count) bytes")
            
            // Process the received data
            if let message = String(data: data, encoding: .utf8) {
                print("Received message: \(message)")
                
                // Handle ping/pong mechanism
                if message == "P" {
                    print("Received ping, sending pong")
                    let response = "p"
                    if let responseData = response.data(using: .utf8) {
                        connection.send(content: responseData, completion: .contentProcessed { error in
                            if let error = error {
                                print("Error sending pong: \(error)")
                            } else {
                                print("Pong sent successfully")
                            }
                        })
                    }
                } else if message == "!" {
                    print("Data output mode enabled")
                } else {
                    // This is likely an EID
                    print("Received EID: \(message)")
                }
            }
            
            // Continue receiving packets
            self.receivePackets(on: connection)
        }
    }

    func startScanning(
        _ serviceUUIDs: [CBUUID],
        _ name: String?,
        _ namePrefix: String?,
        _ allowDuplicates: Bool,
        _ shouldShowDeviceList: Bool,
        _ scanDuration: Double?,
        _ callback: @escaping Callback,
        _ scanResultCallback: @escaping ScanResultCallback
    ) {
        self.callbackMap["startScanning"] = callback
        self.scanResultCallback = scanResultCallback

        if self.centralManager.isScanning == false {
            self.discoveredDevices = [String: Device]()
            self.shouldShowDeviceList = shouldShowDeviceList
            self.allowDuplicates = allowDuplicates
            self.deviceNameFilter = name
            self.deviceNamePrefixFilter = namePrefix

            if shouldShowDeviceList {
                self.showDeviceList()
            }

            if scanDuration != nil {
                self.stopScanWorkItem = DispatchWorkItem {
                    self.stopScan()
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + scanDuration!, execute: self.stopScanWorkItem!)
            }
            self.centralManager.scanForPeripherals(
                withServices: serviceUUIDs,
                options: [CBCentralManagerScanOptionAllowDuplicatesKey: allowDuplicates]
            )

            if shouldShowDeviceList == false {
                self.resolve("startScanning", "Scan started.")
            }
        } else {
            self.stopScan()
            self.reject("startScanning", "Already scanning. Stopping now.")
        }
    }

    func stopScan() {
        log("Stop scanning.")
        self.centralManager.stopScan()
        self.stopScanWorkItem?.cancel()
        self.stopScanWorkItem = nil
        DispatchQueue.main.async { [weak self] in
            if self?.discoveredDevices.count == 0 {
                self?.alertController?.title = self?.displayStrings["noDeviceFound"]
            } else {
                self?.alertController?.title = self?.displayStrings["availableDevices"]
            }
        }
    }

    // didDiscover
    func centralManager(
        _ central: CBCentralManager,
        didDiscover peripheral: CBPeripheral,
        advertisementData: [String: Any],
        rssi RSSI: NSNumber
    ) {

        guard peripheral.state != CBPeripheralState.connected else {
            log("found connected device", peripheral.name ?? "Unknown")
            // make sure we do not touch connected devices
            return
        }

        let isNew = self.discoveredDevices[peripheral.identifier.uuidString] == nil
        guard isNew || self.allowDuplicates else { return }

        guard self.passesNameFilter(peripheralName: peripheral.name) else { return }
        guard self.passesNamePrefixFilter(peripheralName: peripheral.name) else { return }

        let device: Device
        if self.allowDuplicates, let knownDevice = discoveredDevices.first(where: { $0.key == peripheral.identifier.uuidString })?.value {
            device = knownDevice
        } else {
            device = Device(peripheral)
            self.discoveredDevices[device.getId()] = device
        }
        log("New device found: ", device.getName() ?? "Unknown")

        if shouldShowDeviceList {
            DispatchQueue.main.async { [weak self] in
                self?.alertController?.addAction(UIAlertAction(title: device.getName() ?? "Unknown", style: UIAlertAction.Style.default, handler: { (_) -> Void in
                    log("Selected device")
                    self?.stopScan()
                    self?.resolve("startScanning", device.getId())
                }))
            }
        } else {
            if self.scanResultCallback != nil {
                self.scanResultCallback!(device, advertisementData, RSSI)
            }
        }
    }

    func showDeviceList() {
        DispatchQueue.main.async { [weak self] in
            self?.alertController = UIAlertController(title: self?.displayStrings["scanning"], message: nil, preferredStyle: UIAlertController.Style.alert)
            self?.alertController?.addAction(UIAlertAction(title: self?.displayStrings["cancel"], style: UIAlertAction.Style.cancel, handler: { (_) -> Void in
                log("Cancelled request device.")
                self?.stopScan()
                self?.reject("startScanning", "requestDevice cancelled.")
            }))
            self?.viewController?.present((self?.alertController)!, animated: true, completion: nil)
        }
    }

    func getDevices(
        _ deviceUUIDs: [UUID]
    ) -> [CBPeripheral] {
        return self.centralManager.retrievePeripherals(withIdentifiers: deviceUUIDs)
    }

    func getConnectedDevices(
        _ serviceUUIDs: [CBUUID]
    ) -> [CBPeripheral] {
        return self.centralManager.retrieveConnectedPeripherals(withServices: serviceUUIDs)
    }

    func connect(
        _ device: Device,
        _ connectionTimeout: Double,
        _ callback: @escaping Callback
    ) {
        let key = "connect|\(device.getId())"
        self.callbackMap[key] = callback
        log("Connecting to peripheral", device.getPeripheral())
        self.centralManager.connect(device.getPeripheral(), options: nil)
        self.setConnectionTimeout(key, "Connection timeout.", device, connectionTimeout)
    }

    // didConnect
    func centralManager(
        _ central: CBCentralManager,
        didConnect peripheral: CBPeripheral
    ) {
        log("Connected to device", peripheral)
        let key = "connect|\(peripheral.identifier.uuidString)"
        peripheral.discoverServices(nil)
        self.resolve(key, "Successfully connected.")
        // will wait for services in plugin call
    }

    // didFailToConnect
    func centralManager(
        _ central: CBCentralManager,
        didFailToConnect peripheral: CBPeripheral,
        error: Error?
    ) {
        let key = "connect|\(peripheral.identifier.uuidString)"
        if error != nil {
            self.reject(key, error!.localizedDescription)
            return
        }
        self.reject(key, "Failed to connect.")
    }

    func setOnDisconnected(
        _ device: Device,
        _ callback: @escaping Callback
    ) {
        let key = "onDisconnected|\(device.getId())"
        self.callbackMap[key] = callback
    }

    func disconnect(
        _ device: Device,
        _ timeout: Double,
        _ callback: @escaping Callback
    ) {
        let key = "disconnect|\(device.getId())"
        self.callbackMap[key] = callback
        if device.isConnected() == false {
            self.resolve(key, "Disconnected.")
            return
        }
        log("Disconnecting from peripheral", device.getPeripheral())
        self.centralManager.cancelPeripheralConnection(device.getPeripheral())
        self.setTimeout(key, "Disconnection timeout.", timeout)
    }

    // didDisconnectPeripheral
    func centralManager(
        _ central: CBCentralManager,
        didDisconnectPeripheral peripheral: CBPeripheral,
        error: Error?
    ) {
        let key = "disconnect|\(peripheral.identifier.uuidString)"
        let keyOnDisconnected = "onDisconnected|\(peripheral.identifier.uuidString)"
        self.resolve(keyOnDisconnected, "Disconnected.")
        if error != nil {
            log(error!.localizedDescription)
            self.reject(key, error!.localizedDescription)
            return
        }
        self.resolve(key, "Successfully disconnected.")
    }

    func getDevice(_ deviceId: String) -> Device? {
        return self.discoveredDevices[deviceId]
    }

    private func passesNameFilter(peripheralName: String?) -> Bool {
        guard let nameFilter = self.deviceNameFilter else { return true }
        guard let name = peripheralName else { return false }
        return name == nameFilter
    }

    private func passesNamePrefixFilter(peripheralName: String?) -> Bool {
        guard let prefix = self.deviceNamePrefixFilter else { return true }
        guard let name = peripheralName else { return false }
        return name.hasPrefix(prefix)
    }

    private func resolve(_ key: String, _ value: String) {
        let callback = self.callbackMap[key]
        if callback != nil {
            log("Resolve", key, value)
            callback!(true, value)
            self.callbackMap[key] = nil
            self.timeoutMap[key]?.cancel()
            self.timeoutMap[key] = nil
        }
    }

    private func reject(_ key: String, _ value: String) {
        let callback = self.callbackMap[key]
        if callback != nil {
            log("Reject", key, value)
            callback!(false, value)
            self.callbackMap[key] = nil
            self.timeoutMap[key]?.cancel()
            self.timeoutMap[key] = nil
        }
    }

    private func setTimeout(
        _ key: String,
        _ message: String,
        _ timeout: Double
    ) {
        let workItem = DispatchWorkItem {
            self.reject(key, message)
        }
        self.timeoutMap[key] = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + timeout, execute: workItem)
    }

    private func setConnectionTimeout(
        _ key: String,
        _ message: String,
        _ device: Device,
        _ connectionTimeout: Double
    ) {
        let workItem = DispatchWorkItem {
            // do not call onDisconnnected, which is triggered by cancelPeripheralConnection
            let key = "onDisconnected|\(device.getId())"
            self.callbackMap[key] = nil
            self.centralManager.cancelPeripheralConnection(device.getPeripheral())
            self.reject(key, message)
        }
        self.timeoutMap[key] = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + connectionTimeout, execute: workItem)
    }
}
