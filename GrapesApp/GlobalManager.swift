//
//  GlobalManager.swift
//  GrapesApp
//
//  Created by Maëva on 03/12/2021.
//

import Foundation
import UIKit
import BlueSTSDK

class GlobalManager: NSObject {
    
    static let instance = GlobalManager()
    
    var socketIO = SocketIOManager.instance
    
    var spherosConnected = false
    var isListening = false
    var winemakerIsDoing = false
    var lastTime:Double = 0.00
    
    // ST micro
    
    // ST me
    let manager = BlueSTSDKManager.sharedInstance
    var features = [BlueSTSDKFeature]()
    
    
    override init() {
        super.init()
        socketIO.connect()
        
        socketIO.socket.on("grow", callback: { data, ack in
            self.grapesChanging(color: .green, duration: nil)
        })
        socketIO.socket.on("solar", callback: { data, ack in
            let duration = data.count > 0 ? data[0] as? Double : nil
            self.grapesChanging(color: .purple, duration: duration)
        })
        
        
        manager.addDelegate(self)
        manager.discoveryStart(35*1000)
        
        
    }
    
    func connectSpheros(spherosConnected: @escaping (() -> ())) {
        // SB-313C - SB-A729
        SharedToyBox.instance.searchForBoltsNamed(["SB-A729", "SB-313C"]) { err in
            if err == nil {
                spherosConnected()
                self.spherosConnected = true
                print(SharedToyBox.instance.bolts.count)
                if(SharedToyBox.instance.bolts.count == 2) {    //
                    print("in")
                    for (index, bolt) in SharedToyBox.instance.bolts.enumerated() {
                        switch index {
                            case 0:
                            bolt.sensorControl.enable(sensors: SensorMask.init(arrayLiteral: .accelerometer,.gyro))
                            bolt.sensorControl.interval = 1
                            bolt.setStabilization(state: SetStabilization.State.off)
                            bolt.sensorControl.onDataReady = { data in
                                DispatchQueue.main.async {
                                    self.onData(data: data)
                                }
                            }
                                break;
                            case 1:
                            bolt.setFrontLed(color: .red)
                            bolt.setBackLed(color: .red)
                                break;
                            case 2:
                            bolt.setFrontLed(color: .blue)
                            bolt.setBackLed(color: .blue)
                                break;
                            default:
                                break;
                        }
                    }
                } else {
                    print("Missed to connect to 2 spheros")
                }
            }
        }
    }
    
    func grapesChanging(color: UIColor, duration: Double?) {
        var timing:Double = 60/64
        print(["timing", timing])
        if let duration = duration {
            timing = duration/64 // = droneDuration/64
        }
        var count = 0
        
        for y in 0...7 {
            for x in 0...7 {
                let sum = timing * Double(count)
                //print([count, sum])
                DispatchQueue.main.asyncAfter(deadline: .now() + timing * Double(count)) {
                    if let bolt = SharedToyBox.instance.bolt {
                        bolt.drawMatrix(pixel: Pixel(x: x, y: y), color: color)
                    }
                }
                count+=1
            }
        }
    }
    
    func onData(data: SensorControlData) {
        if self.isListening {
            print("listening")
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

