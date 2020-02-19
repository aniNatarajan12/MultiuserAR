//
//  ViewController.swift
//  Multiuser
//
//  Created by Anirudh Natarajan on 2/14/20.
//  Copyright © 2020 Anirudh Natarajan. All rights reserved.
//

import UIKit
import ARKit
import RealityKit
import MultipeerSession

class ViewController: UIViewController {
    
    @IBOutlet var arView: ARView!
    
    var multipeerSession: MultipeerSession?
    var sessionIDObservation: NSKeyValueObservation?
    var first = true
    
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        
        setupAR()
        arView.session.delegate = self
        
        let tap = UITapGestureRecognizer(target: self, action: #selector(self.handleTap(recognizer:)))
        arView.addGestureRecognizer(tap)
        
        setupMultipeer()
    }
    
    func setupAR() {
        arView.automaticallyConfigureSession = false
        
        let config = ARWorldTrackingConfiguration()
        config.planeDetection = [.horizontal, .vertical]
        config.environmentTexturing = .automatic
        
        config.isCollaborationEnabled = true
        
        arView.session.run(config)
    }
    
    func setupMultipeer() {
        sessionIDObservation = observe(\.arView.session.identifier, options: [.new], changeHandler: { (object, change) in
            print("SessionID changed to: \(change.newValue!)")
            
            guard let multipeerSession = self.multipeerSession else { return }
            self.sendARSessionIDTo(peers: multipeerSession.connectedPeers)
        })
        
        multipeerSession = MultipeerSession(serviceName: "multiuser-ar", receivedDataHandler: self.recievedData, peerJoinedHandler: self.peerJoined, peerLeftHandler: self.peerLeft, peerDiscoveredHandler: self.peerDiscovered)
    }
    
    @objc func handleTap(recognizer: UITapGestureRecognizer) {
        let anchor = ARAnchor(name: "Laser", transform: arView.cameraTransform.matrix)
        arView.session.add(anchor: anchor)
    }
    
    func placeObject(named entityName: String, for anchor: ARAnchor, material: SimpleMaterial) {
        let laserEntity = try! ModelEntity.load(named: entityName)
        let subEntity: Entity = laserEntity.children[0].children[0].children[0]
        
        var laserModelComp: ModelComponent = (subEntity.components[ModelComponent])!

        laserModelComp.materials[0] = material
        laserEntity.children[0].children[0].children[0].components.set(laserModelComp)
        
        let anchorEntity = AnchorEntity(anchor: anchor)
        anchorEntity.addChild(laserEntity)
        arView.scene.addAnchor(anchorEntity)
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.55) {
            self.arView.scene.removeAnchor(anchorEntity)
        }
    }
}

extension ViewController: ARSessionDelegate {
    func session(_ session: ARSession, didAdd anchors: [ARAnchor]) {
        for anchor in anchors {
            
            if let participantAnchor = anchor as? ARParticipantAnchor {
                if first {
                    first = false
                    let alert = UIAlertController(title: "Connected!", message: "You have successfully connected with another user.", preferredStyle: .alert)
                    alert.addAction(UIAlertAction(title: "Cool", style: .default, handler: nil))
                    self.present(alert, animated: true)
                }
                print("connected")
                
                let anchorEntity = AnchorEntity(anchor: participantAnchor)
                
                let mesh = MeshResource.generateSphere(radius: 0.03)
                let userColor = (participantAnchor.sessionIdentifier?.toRandomColor())!
                print(userColor)
                print("HIIIIIIII")
                let material = SimpleMaterial(color: userColor, isMetallic: false)
                let coloredSphere = ModelEntity(mesh: mesh, materials: [material])
                
                anchorEntity.addChild(coloredSphere)
                arView.scene.addAnchor(anchorEntity)
                
            }
            
            if let anchorName = anchor.name, anchorName=="Laser" {
                print(1)
                if let participantAnchor = anchor as? ARParticipantAnchor {
                    print(2)
                    placeObject(named: anchorName, for: anchor, material: SimpleMaterial(color: (participantAnchor.sessionIdentifier?.toRandomColor())!, isMetallic: false))
                }
                else {
                    print(3)
                    placeObject(named: anchorName, for: anchor, material: SimpleMaterial(color: UIColor.white, isMetallic: false))
                }
            }
        }
    }
}

//MARK: Multiuser Extensions

extension UUID {
    func toRandomColor() -> UIColor {
        var firstFourUUIDBytesAsUInt32: UInt32 = 0
        let data = withUnsafePointer(to: self) {
            return Data(bytes: $0, count: MemoryLayout.size(ofValue: self))
        }
        _ = withUnsafeMutableBytes(of: &firstFourUUIDBytesAsUInt32, { data.copyBytes(to: $0) })

        let colors: [UIColor] = [.red, .green, .blue, .yellow, .magenta, .cyan, .purple,
        .orange, .brown, .lightGray, .gray, .darkGray, .black, .white]
        
        let randomNumber = Int(firstFourUUIDBytesAsUInt32) % colors.count
        return colors[randomNumber]
    }
}


extension ViewController {
    private func sendARSessionIDTo(peers: [PeerID]) {
        guard let multipeerSession = multipeerSession else { return }
        let idString = arView.session.identifier.uuidString
        let command = "SessionID:" + idString
        if let commandData = command.data(using: .utf8) {
            multipeerSession.sendToPeers(commandData, reliably: true, peers: peers)
        }
    }
    
    func recievedData(_ data: Data, from peer: PeerID) {
        guard let multipeerSession = multipeerSession else { return }
        
        if let collaborationData = try? NSKeyedUnarchiver.unarchivedObject(ofClass: ARSession.CollaborationData.self, from: data) {
            arView.session.update(with: collaborationData)
            return
        }
        
        let sessionIDCommandString = "SessionID:"
        if let commandString = String(data: data, encoding: .utf8), commandString.starts(with: sessionIDCommandString) {
            let newSessionID = String(commandString[commandString.index(commandString.startIndex, offsetBy: sessionIDCommandString.count)...])
            
            if let oldSessionID = multipeerSession.peerSessionIDs[peer] {
                removeAllAnchorsOriginatingFromARSessionWithID(oldSessionID)
            }
            
            multipeerSession.peerSessionIDs[peer] = newSessionID
        }
    }
    
    func peerDiscovered(_ peer: PeerID) -> Bool {
        guard let multipeerSession = multipeerSession else { return false }
        
        if multipeerSession.connectedPeers.count > 4 {
            print("A fifth player wants to join but the game is limited to four players.")
            return false
        } else {
            return true
        }
    }
    
    func peerJoined(_ peer: PeerID) {
        print("A player wants to join the game. Hold the devices next to each other.")
        sendARSessionIDTo(peers: [peer])
    }
    
    func peerLeft(_ peer: PeerID) {
        guard let multipeerSession = multipeerSession else { return }
        
        print("A player has left the game")
        
        if let sessionID = multipeerSession.peerSessionIDs[peer] {
            removeAllAnchorsOriginatingFromARSessionWithID(sessionID)
            multipeerSession.peerSessionIDs.removeValue(forKey: peer)
        }
    }
    
    private func removeAllAnchorsOriginatingFromARSessionWithID(_ identifier: String) {
        guard let frame = arView.session.currentFrame else { return }
        
        for anchor in frame.anchors {
            guard let anchorSessionID = anchor.sessionIdentifier else { continue }
            if anchorSessionID.uuidString == identifier {
                arView.session.remove(anchor: anchor)
            }
        }
    }
    
    func session(_ session: ARSession, didOutputCollaborationData data: ARSession.CollaborationData) {
        guard let multipeerSession = multipeerSession else { return }
        
        if !multipeerSession.connectedPeers.isEmpty {
            guard let encodedData = try? NSKeyedArchiver.archivedData(withRootObject: data, requiringSecureCoding: true)
            else { fatalError("Unexpected failed to encode collaboration data.") }
            
            let dataIsCritical = data.priority == .critical
            multipeerSession.sendToAllPeers(encodedData, reliably: dataIsCritical)
        } else {
            print("Deferred sending collaboration to later because there are no peers.")
        }
    }
    
}
