import Foundation
import NetworkExtension
import Network

//manages network accessory connections

class NetworkDeviceManager {
    private var networkSession: NEHotspotConfigurationManager
    private var tcpConnection: NWConnection?
    private var hasReceivedFirstPing = false

    
    
    init() {
        self.networkSession = NEHotspotConfigurationManager()
    }
    
    func joinAccessorySR5(accessory: ASAccessory, completion: @escaping (Error?) -> Void) {
        self.networkSession.joinAccessoryHotspotWithoutSecurity(accessory) { [weak self] error in
            if let error = error {
                print("Failed to join accessory hotspot: \(error)")
                completion(error)
            } else {
                print("Successfully joined accessory hotspot")
                self?.setupNetworkListeners()
                completion(nil)
            }
        }
    }
    
    private func setupNetworkListeners() {
        // Set up UDP listener
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
            case .cancelled:
                print("UDP listener cancelled")
            default:
                break
            }
        }
        
        udpListener.newConnectionHandler = { [weak self] newConnection in
            newConnection.start(queue: .global())
            self?.receivePackets(on: newConnection)
        }
        
        udpListener.start(queue: .global())
    }
    
    private func receivePackets(on connection: NWConnection) {
        connection.receiveMessage { [weak self] (data, context, isComplete, error) in
            if let error = error {
                print("Error receiving packet: \(error)")
                return
            }
            
            guard let data = data, !data.isEmpty else {
                print("Received empty packet")
                return
            }
            
            print("Received packet of size: \(data.count) bytes")
            
            if let message = String(data: data, encoding: .utf8) {
                print("Received message: \(message)")
                self?.handleReceivedMessage(message)
            }
            
            // Continue receiving packets
            self?.receivePackets(on: connection)
        }
    }
    
    private func handleReceivedMessage(_ message: String) {
        if message == "P" {
            print("Received ping, sending pong")
            let response = "p"
            
            if let responseData = response.data(using: .utf8) {
                // Send pong response
                // Note: This would need to be sent through the appropriate connection
            }
        } else if message == "!" {
            print("Data output mode enabled")
        } else if message.contains("HR") && message.contains("-") {
            print("HRx has identified itself, making TCP connection request")
            setupTCPConnection()
        } else {
            print("Received EID: \(message)")
            self.notifyListeners("recievedEID", data: accessory)
        }
    }
    
    private func setupTCPConnection() {
        let tcpConnection = NWConnection(host: "192.168.1.1", port: 15001, using: .tcp)
        self.tcpConnection = tcpConnection
        
        tcpConnection.stateUpdateHandler = { [weak self] state in
            guard let self = self else { return }
            
            switch state {
            case .ready:
                print("TCP connection is ready")
                self.receiveTCPPackets(on: tcpConnection)
            case .failed(let error):
                print("TCP connection failed: \(error)")
                self.hasReceivedFirstPing = false
                DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                    self.setupTCPConnection()
                }
            case .cancelled:
                print("TCP connection cancelled")
                self.hasReceivedFirstPing = false
            default:
                break
            }
        }
        
        tcpConnection.start(queue: .global())
    }
    
    private func receiveTCPPackets(on connection: NWConnection) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] (data, context, isComplete, error) in
            guard let self = self else { return }
            
            if let error = error {
                print("Error receiving TCP packet: \(error)")
                return
            }
            
            guard let data = data, !data.isEmpty else {
                print("Received empty TCP packet")
                return
            }
            
            print("Received TCP packet of size: \(data.count) bytes")
            
            if let message = String(data: data, encoding: .utf8) {
                print("Received TCP message: \(message)")
                // Handle TCP message processing
            }
            
            self.receiveTCPPackets(on: connection)
        }
    }
    
    func cleanup() {
        tcpConnection?.cancel()
        tcpConnection = nil
    }
} 