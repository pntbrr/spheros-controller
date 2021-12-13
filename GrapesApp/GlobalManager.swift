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
    
    let greenGrape:UIColor = UIColor(red: 150/255, green: 255/255, blue: 10/255, alpha: 1)
    let purpleGrape:UIColor = UIColor(red: 175/255, green: 0/255, blue: 255/255, alpha: 1)
    let wineColor:UIColor = UIColor(red: 60/255, green: 2/255, blue: 3/255, alpha: 1)
    var currentColor:UIColor?
    
    var isListening = false
    var winemakerIsDoing = false
    var lastTime:Double = 0.00
    
    let manager = BlueSTSDKManager.sharedInstance
    var features = [BlueSTSDKFeature]()

    
    override init() {
        super.init()
        
        self.currentColor = greenGrape
        
        socketIO.socket.on(clientEvent: .connect) { data, ack in
            if self.allSpherosConnected { self.socketIO.emit(event: "spherosConnected")}
        }
        
        socketIO.socket.on("step") { data, ack in
            if let s = data[0] as? String {
                self.currentStep = s
            }
        }
        
        socketIO.socket.on("grow", callback: { data, ack in
            self.grapeRipens(color: self.purpleGrape, duration: 2)
        })
    
        socketIO.socket.on("solar", callback: { data, ack in
            let duration = data.count > 0 ? data[0] as? Int : nil
            self.grapesfillsUpSugar(color: self.wineColor, duration: duration ?? 10)
        })
        
        socketIO.socket.on("press") { data, ack in
            self.isListening = true
        }
        
        self.connectSpheros {
            self.socketIO.connect()
        }
        
        //self.manager.addDelegate(self)
        //self.manager.discoveryStart(35*1000)
    }
    
    func connectSpheros(spherosConnected: (() -> ())? = nil) {
        // SB-313C - SB-A729 - SB-6C4C
        SharedToyBox.instance.searchForBoltsNamed(["SB-A729"]) { err in
            if err == nil {
                if(SharedToyBox.instance.bolts.count == 1) {
                    SharedToyBox.instance.bolts.forEach { bolt in
                        bolt.setStabilization(state: SetStabilization.State.off)
                        if let name = bolt.peripheral?.name {
                            switch name {
                            case "SB-A729":
                                self.grapeBolt = bolt
                            
                                if let color = self.currentColor {
                                    bolt.setMainLed(color: color)
                                    bolt.setFrontLed(color: color)
                                    bolt.setBackLed(color: color)
                                }

                                bolt.sensorControl.disable()
                                // Forçage pour éviter le glitch
                                bolt.sensorControl.enable(sensors: SensorMask.init(arrayLiteral: .accelerometer))
                                bolt.sensorControl.disable()
                                DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                                    bolt.sensorControl.enable(sensors: SensorMask.init(arrayLiteral: .accelerometer))
                                }
                                bolt.sensorControl.interval = 1
                                bolt.sensorControl.onDataReady = { data in
                                    DispatchQueue.main.async {
                                        self.onData(data: data)
                                    }
                                }
                                break;
                                //case "SB-313C":
                                //    self.shakeBolt = bolt
                                //    bolt.setFrontLed(color: .red)
                                //    bolt.setBackLed(color: .red)
                                //    break;
                                default:
                                    break;
                            }
                        }
                    }
                    
                    self.delegate?.spherosConnected()
                    spherosConnected?()
                    self.allSpherosConnected = true
                } else {
                    print("Missed to connect to all spheros needed")
                }
            } else {
                print("Failed to connect : \(err)")
            }
        }
    }
    
    func grapeRipens(color: UIColor, duration: Int) {
        let timing = 1 / 10
        var time:Double = 0.00
        let interpolationArray = self.colorInterpolation(color: color, duration: duration)

        for t in 0...(interpolationArray.count - 1) {
            
            DispatchQueue.main.asyncAfter(deadline: .now() + Double(timing * t)) {
                if t == 0 {
                    print("pepito")
                    time = NSDate.timeIntervalSinceReferenceDate
                }
                if let bolt = self.grapeBolt {
                    bolt.setMainLed(color: interpolationArray[t])
                    bolt.setFrontLed(color: interpolationArray[t])
                    bolt.setBackLed(color: interpolationArray[t])
                }
                
                if t == interpolationArray.count - 1 {
                    print("finito")
                    print(NSDate.timeIntervalSinceReferenceDate - time)
                }
            }
        }
        
        self.currentColor = color
    }
    
    func grapesfillsUpSugar(color: UIColor, duration: Int) {
        let timing = Double(duration)/64 // = droneDuration/64
        let ms = Int((timing.truncatingRemainder(dividingBy: 1.0)) * 1000)
        var count:Double = 0
        
        print(duration)
        print(ms)
        
        if let bolt = self.grapeBolt {
            bolt.setFrontLed(color: color)
            bolt.setBackLed(color: color)
            DispatchQueue.main.async {
                for y in 0...7 {
                    for x in 0...7 {
                            bolt.drawMatrix(pixel: Pixel(x: x, y: y), color: color)
                            count+=1
                            usleep(useconds_t((ms - 36) * 1000))
                    }
                }
            }
        }
        self.currentColor = color
    }
    
    func onData(data: SensorControlData) {
        if ["press", "shake"].contains(self.currentStep) {
            if let acceleration = data.accelerometer?.filteredAcceleration {
                
                if let z = acceleration.z,
                   let y = acceleration.y,
                   let x = acceleration.x {
                    
                    let absSum = abs(x)+abs(y)+abs(z)
                    
                    if (self.currentStep == "press" && absSum >= 1.8) {
                        if(!winemakerIsDoing) {
                            winemakerIsDoing = true
                            self.socketIO.emit(event: "winemaker", data: 1)
                        }
                        lastTime = NSDate.timeIntervalSinceReferenceDate
                    } else if (self.currentStep == "shake" && absSum >= 2) {
                        self.socketIO.emit(event: "shake", data: absSum)
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
    
    func colorInterpolation(color: UIColor, duration:Int = 1) -> [UIColor] {
        // pour 1s 30 x 33ms
        let steps = 10 * duration
        var interpolationArray:[UIColor] = []
        
        if let cColor = self.currentColor {
            let color1 = cColor.rgbValues()
            let color2 = color.rgbValues()
            
            let pasR = (color2.r - color1.r) / CGFloat(steps)
            let pasG = (color2.g - color1.g) / CGFloat(steps)
            let pasB = (color2.b - color1.b) / CGFloat(steps)
            
            var currentR = color1.r
            var currentG = color1.g
            var currentB = color1.b
            
            for _ in 0...(steps-1) {
       
                currentR += pasR
                currentG += pasG
                currentB += pasB
                                                    
                let color:UIColor = UIColor(red: currentR, green: currentG, blue: currentB, alpha: 1)
                                    
                interpolationArray.append(color)
            }
        }
        return interpolationArray
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
                if self.currentStep == "pour water" {
                    self.socketIO.emit(event: "pouring", data: axes.z)
                }
                print("\(axes.z)")
            default:
                return
            }
            
        }
        
    }
    
    
}

