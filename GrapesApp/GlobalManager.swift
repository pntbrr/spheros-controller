//
//  GlobalManager.swift
//  GrapesApp
//
//  Created by Maëva on 03/12/2021.
//

import Foundation
import UIKit
import BlueSTSDK


protocol GlobalManagerDelegate {
    func spherosConnected()
}

class GlobalManager: NSObject {
    
    static let instance = GlobalManager()
    
    var delegate: GlobalManagerDelegate?
    
    let socketIO = SocketIOManager.instance
    
    var allSpherosConnected = false
    var currentStep = "idle"
    var grapeBolt:BoltToy?
    var shakeBolt:BoltToy?
    var isListening = false
    var winemakerIsDoing = false
    var lastTime:Double = 0.00
    
    let manager = BlueSTSDKManager.sharedInstance
    var features = [BlueSTSDKFeature]()

    
    override init() {
        super.init()
        
        socketIO.socket.on(clientEvent: .connect) { data, ack in
            if self.allSpherosConnected { self.socketIO.emit(event: "spherosConnected")}
        }
        
        socketIO.socket.on("step") { data, ack in
            if let s = data[0] as? String {
                self.currentStep = s
            }
        }
        
        socketIO.socket.on("grow", callback: { data, ack in
            self.grapesChanging(color: .green, duration: nil)
        })
        socketIO.socket.on("solar", callback: { data, ack in
            let duration = data.count > 0 ? data[0] as? Double : nil
            self.grapesChanging(color: .purple, duration: duration)
        })
        
        socketIO.socket.on("press") { data, ack in
            self.isListening = true
        }
        
        self.connectSpheros()
        
        manager.addDelegate(self)
        manager.discoveryStart(35*1000)
    }
    
    func connectSpheros(spherosConnected: (() -> ())? = nil) {
        // SB-313C - SB-A729
        SharedToyBox.instance.searchForBoltsNamed(["SB-A729", "SB-6C4C"]) { err in
            if err == nil {
                self.delegate?.spherosConnected()
                spherosConnected?()
                
                if(SharedToyBox.instance.bolts.count == 2) {
                    self.allSpherosConnected = true

                    SharedToyBox.instance.bolts.forEach { bolt in
                        bolt.setStabilization(state: SetStabilization.State.off)
                        
                        if let name = bolt.peripheral?.name {
                            switch name {
                                case "SB-A729":
                                    self.grapeBolt = bolt
                                    bolt.sensorControl.enable(sensors: SensorMask.init(arrayLiteral: .accelerometer,.gyro))
                                    bolt.sensorControl.interval = 1
                                    bolt.sensorControl.onDataReady = { data in
                                        DispatchQueue.main.async {
                                            self.onData(data: data)
                                        }
                                    }
                                    bolt.setFrontLed(color: .green)
                                    bolt.setBackLed(color: .green)
                                    break;
                                case "SB-6C4C":
                                    self.shakeBolt = bolt
                                    bolt.setFrontLed(color: .red)
                                    bolt.setBackLed(color: .red)
                                    break;
                                default:
                                    break;
                            }
                        }
                    }
                    self.socketIO.connect()
                } else {
                    print("Missed to connect to all spheros needed")
                }
            } else {
                print("Failed to connect : \(err)")
            }
        }
    }
    
    func grapesChanging(color: UIColor, duration: Double?) {
        var timing:Double = 60/64
        if let duration = duration {
            timing = duration/64 // = droneDuration/64
        }
        var count = 0
        
        for y in 0...7 {
            for x in 0...7 {
                //let sum = timing * Double(count)
                //print([count, sum])
                DispatchQueue.main.asyncAfter(deadline: .now() + timing * Double(count)) {
                    if let bolt = self.grapeBolt {
                        bolt.drawMatrix(pixel: Pixel(x: x, y: y), color: color)
                    }
                }
                count+=1
            }
        }
    }
    
    func onData(data: SensorControlData) {
        if self.currentStep == "press" {
            if let acceleration = data.accelerometer?.filteredAcceleration {

                if let z = acceleration.z,
                   let y = acceleration.y,
                   let x = acceleration.x {
                    
                    let absSum = abs(x)+abs(y)+abs(z)
                    
                    if (absSum >= 2) {
                        if(!winemakerIsDoing) {
                            winemakerIsDoing = true
                            self.socketIO.emit(event: "winemaker", data: 1)
                        }
                        lastTime = NSDate.timeIntervalSinceReferenceDate
                    }
                    
                    if(NSDate.timeIntervalSinceReferenceDate - lastTime > 0.5) {
                        if(winemakerIsDoing) {
                            winemakerIsDoing = false
                            self.socketIO.emit(event: "winemaker", data: 0)
                        }
                    }
                }
            }
        }
    }
}




extension GlobalManager: BlueSTSDKManagerDelegate {
    func manager(_ manager: BlueSTSDKManager, didChangeDiscovery: Bool) {
        
    }

    func manager(_ manager: BlueSTSDKManager, didDiscoverNode: BlueSTSDKNode) {
        print(didDiscoverNode.advertiseInfo.name ?? "")
        if let name = didDiscoverNode.advertiseInfo.name,
           name == "BCN-774" {
            didDiscoverNode.addStatusDelegate(self)
            didDiscoverNode.connect()
            manager.discoveryStop()
        }
    }
    
}

extension GlobalManager: BlueSTSDKNodeStateDelegate {
    func node(_ node: BlueSTSDKNode, didChange newState: BlueSTSDKNodeState, prevState: BlueSTSDKNodeState) {
        
        switch newState {
        case .connected:
            print("Connected!")
            self.features = node.getFeatures()
            print(self.features)
            // Accelero
            //self.features[2].add(self)
           
            self.features[4].add(self)
            self.features[4].enableNotification()
            // Accelero
            self.features[3].add(self)
            self.features[3].enableNotification()
            
            //self.features[12].add(self)
            //self.features[12].enableNotification()
            
        default: break
        }
    }
}


extension GlobalManager:BlueSTSDKFeatureDelegate {
    func didUpdate(_ feature: BlueSTSDKFeature, sample: BlueSTSDKFeatureSample) {
        DispatchQueue.main.async {
            var rotationRate: SIMD3 = [0.0,0.0,0.0]
            
            switch feature {
            case is BlueSTSDKFeatureGyroscope:
                break
            case is BlueSTSDKFeatureAudioADPCM:
                break
            case is BlueSTSDKFeatureAudioADPCMSync:
                break
            case is BlueSTSDKFeatureAcceleration:
                
                let normalizedValues = sample.data.map{ $0.floatValue/1000.0 }
                let axes = Axes(x: sample.data[0].floatValue, y: sample.data[1].floatValue, z: sample.data[2].floatValue)
                
//                print("\(axes)")
            default:
                return
            }
            
        }
        
    }
    
    
}

