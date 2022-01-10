//
//  GlobalManager.swift
//  GrapesApp
//
//  Created by Maëva on 03/12/2021.
//

import Foundation
import UIKit
import BlueSTSDK
import AVFoundation


protocol GlobalManagerDelegate {
    func spherosConnected()
}

class GlobalManager: NSObject {
    
    static let instance = GlobalManager()
    
    var delegate: GlobalManagerDelegate?
    
    let socketIO = SocketIOManager.instance
    
    
    let blueSTSDKmanager = BlueSTSDKManager.sharedInstance
    var blueSTSDKfeatures = [BlueSTSDKFeature]()
    var blueTileConnected = false
    
    var allSpherosConnected = false
    var currentStep = "idle"
    var mainBolt:BoltToy?
    
    let greenGrape:UIColor = UIColor(red: 150/255, green: 255/255, blue: 10/255, alpha: 1)
    let purpleGrape:UIColor = UIColor(red: 140/255, green: 0/255, blue: 205/255, alpha: 1)
    let wineColor:UIColor = UIColor(red: 60/255, green: 2/255, blue: 3/255, alpha: 1)
    var currentColor:UIColor?
    
    // Press part
    var isListening = false
    var winemakerIsDoing = false
    var lastTime:Double = 0.00
    var x = 0
    var y = 0
    var pressSoundEffect: AVAudioPlayer?
    
    override init() {
        super.init()
        
        self.currentColor = greenGrape
        
        self.blueSTSDKmanager.addDelegate(self)
        self.blueSTSDKmanager.discoveryStart()
        //self.manager.discoveryStart(35*1000)
        
        socketIO.socket.on(clientEvent: .connect) { data, ack in
            if self.allSpherosConnected { self.socketIO.emit(event: "spherosConnected")}
            
            if self.blueTileConnected { self.socketIO.emit(event: "bluetileConnected")}
            else {self.socketIO.emit(event: "bluetileDisconnected")}
        }
        
        socketIO.socket.on("step") { data, ack in
            if let s = data[0] as? String {
                self.currentStep = s
                self.onStep(step: s)
            }
        }
        
        socketIO.socket.on("start", callback: { data, ack in
            SharedToyBox.instance.bolts.forEach { bolt in
                bolt.setMainLed(color: self.greenGrape)
                bolt.setFrontLed(color: self.greenGrape)
                bolt.setBackLed(color: self.greenGrape)
            }
            self.currentColor = self.greenGrape
        })
        
        socketIO.socket.on("grow", callback: { data, ack in
            self.grapeRipens(color: self.purpleGrape, duration: 10)
        })
    
        socketIO.socket.on("solar", callback: { data, ack in
            let duration = data.count > 0 ? data[0] as? Int : nil
            self.grapesfillsUpSugar(color: self.wineColor, duration: duration ?? 10)
        })
        
        socketIO.socket.on("beforePressed", callback: { data, ack in
            self.mainBolt?.setFrontLed(color: self.wineColor)
            self.mainBolt?.setBackLed(color: self.wineColor)
            self.mainBolt?.setMainLed(color: self.wineColor)
            self.x = 0
            self.y = 0
        })
        socketIO.socket.on("pressed", callback: { data, ack in
            print(self.x, self.y)
            if self.x < 8 {
                if let mainBolt = self.mainBolt {
                    mainBolt.drawMatrix(pixel: Pixel(x: self.x, y: self.y), color: .black)
                    if (self.x == 7 && self.y == 7) {
                        self.mainBolt?.setFrontLed(color: .black)
                        self.mainBolt?.setBackLed(color: .black)
                    }
                }
                if self.y == 7 {
                    self.y = 0
                    self.x += 1
                } else {
                    self.y += 1
                }
            }
        })
        
        self.connectSpheros {
            self.socketIO.connect()
        }
        
        let path = Bundle.main.path(forResource: "press-2.mp3", ofType:nil)!
        let url = URL(fileURLWithPath: path)

        do {
            pressSoundEffect = try AVAudioPlayer(contentsOf: url)
            pressSoundEffect?.numberOfLoops = -1
            pressSoundEffect?.setVolume(0.0, fadeDuration: 0.0)
        } catch {
            print("couldn load audio effect")
        }
    }
    
    func onStep(step: String) {
        if (step == "press") {
            pressSoundEffect?.play()
        } else {
            pressSoundEffect?.stop()        }
    }
    
    func connectSpheros(spherosConnected: (() -> ())? = nil) {
        // SB-313C - SB-A729 - SB-6C4C
        SharedToyBox.instance.searchForBoltsNamed(["SB-A729", "SB-313C", "SB-6C4C"]) { err in
            if err == nil {
                if(SharedToyBox.instance.bolts.count == 3) {
                    
                    SharedToyBox.instance.bolts.forEach { bolt in
                        bolt.setStabilization(state: SetStabilization.State.off)
                        
                        bolt.setMainLed(color: .blue)
                        bolt.setFrontLed(color: .blue)
                        bolt.setBackLed(color: .blue)
                        
                        if let name = bolt.peripheral?.name {
                            switch name {
                            case "SB-A729":
                                self.mainBolt = bolt
                            
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
        let timing = 1 / 8
        let interpolationArray = self.colorInterpolation(color: color, duration: duration)
        let interpolationArray2 = self.colorInterpolation(color: color, duration: duration + 10)
        let percent = Double(interpolationArray2.count) / 100 * 75
            
        SharedToyBox.instance.bolts.forEach { bolt in

            if let name = bolt.peripheral?.name {
                switch name {
                case self.mainBolt?.peripheral?.name:
                    for t in 0...( interpolationArray.count - 1) {
                        DispatchQueue.main.asyncAfter(deadline: .now() + Double(timing * t)) {
                            bolt.setMainLed(color: interpolationArray[t])
                            bolt.setFrontLed(color: interpolationArray[t])
                            bolt.setBackLed(color: interpolationArray[t])
                        }
                    }
                    break;
                default:
                    for t in 0...( interpolationArray2.count - 1) {
                        if Double(t) <= round(percent) {
                            DispatchQueue.main.asyncAfter(deadline: .now() + Double(timing * t)) {
                                bolt.setMainLed(color: interpolationArray2[t])
                                bolt.setFrontLed(color: interpolationArray2[t])
                                bolt.setBackLed(color: interpolationArray2[t])
                            }
                        }
                    }
                    break;
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
        
        if let bolt = self.mainBolt {
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
        if ["get on", "press", "shake"].contains(self.currentStep) {
            if let acceleration = data.accelerometer?.filteredAcceleration {
                
                if let z = acceleration.z,
                   let y = acceleration.y,
                   let x = acceleration.x {
                    let absX = abs(x)
                    let absY = abs(y)
                    let absZ = abs(z)
                    let absSum = absX + absY + absZ
                    
                    if (self.currentStep == "press" && absSum >= 1.8) {
                        // presse et eau
                        if(!winemakerIsDoing) {
                            pressSoundEffect?.setVolume(1.0, fadeDuration: 1.0)
                            winemakerIsDoing = true
                            self.socketIO.emit(event: "pressing", data: 1)
                        }
                        lastTime = NSDate.timeIntervalSinceReferenceDate
                    
                        
                    } else if (self.currentStep == "shake" && absSum >= 2) {
                        self.socketIO.emit(event: "shaking", data: absSum)
                    } else if (self.currentStep == "get on" && absSum >= 2) {
                        self.socketIO.emit(event: "get on", data: absSum)
                    }
                     
                    if(NSDate.timeIntervalSinceReferenceDate - lastTime > 0.5) {
                        if(winemakerIsDoing) {
                            pressSoundEffect?.setVolume(0.0, fadeDuration: 1.0)
                            winemakerIsDoing = false
                            self.socketIO.emit(event: "pressing", data: 0)
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
        print(didDiscoverNode.advertiseInfo.name ?? "untitled")
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
            print("BLUESTSDK Connected!")
            self.blueTileConnected = true
            self.socketIO.emit(event: "bluetileConnected")
            self.blueSTSDKmanager.discoveryStop()
            
            self.blueSTSDKfeatures = node.getFeatures()
            print(self.blueSTSDKfeatures)
            // Accelero
            //self.features[2].add(self)
            self.blueSTSDKfeatures[4].add(self)
            self.blueSTSDKfeatures[4].enableNotification()
            // Accelero
            self.blueSTSDKfeatures[3].add(self)
            self.blueSTSDKfeatures[3].enableNotification()
            
            //self.features[12].add(self)
            //self.features[12].enableNotification()
            
        case .disconnecting, .unreachable:
            print("BLUESTSDK Disconnected!")
            self.blueTileConnected = false
            self.socketIO.emit(event: "bluetileDisconnected")
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                self.blueSTSDKmanager.discoveryStart()
                print(self.blueSTSDKmanager.isDiscovering)
            }
            break;
        default: break
        }
    }
}


extension GlobalManager:BlueSTSDKFeatureDelegate {
    func didUpdate(_ feature: BlueSTSDKFeature, sample: BlueSTSDKFeatureSample) {
        DispatchQueue.main.async {
            //var rotationRate: SIMD3 = [0.0,0.0,0.0]
            
            switch feature {
            case is BlueSTSDKFeatureGyroscope:
                break
            case is BlueSTSDKFeatureAudioADPCM:
                break
            case is BlueSTSDKFeatureAudioADPCMSync:
                break
            case is BlueSTSDKFeatureAcceleration:
                
                //let normalizedValues = sample.data.map{ $0.floatValue/1000.0 }
                let axes = Axes(x: sample.data[0].floatValue, y: sample.data[1].floatValue, z: sample.data[2].floatValue)
                if self.currentStep == "pour water" {
                    self.socketIO.emit(event: "pouring", data: axes.z)
                    print("\(axes.z)")
                }
            default:
                return
            }
            
        }
        
    }
    
    
}

