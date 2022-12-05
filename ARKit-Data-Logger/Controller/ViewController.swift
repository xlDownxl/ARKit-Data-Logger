//
//  ViewController.swift
//  ARKit-Data-Logger
//
//  Created by kimpyojin on 04/06/2019.
//  Copyright © 2019 Pyojin Kim. All rights reserved.
//

import UIKit
import SceneKit
import ARKit
import os.log
import Accelerate
import Kronos
import CoreMotion
import Foundation

class ViewController: UIViewController, ARSCNViewDelegate, ARSessionDelegate {
    
    // cellphone screen UI outlet objects
    @IBOutlet weak var startStopButton: UIButton!
    @IBOutlet weak var statusLabel: UILabel!
    
    @IBOutlet var sceneView: ARSCNView!
    
    @IBOutlet weak var numberOfFeatureLabel: UILabel!
    @IBOutlet weak var trackingStatusLabel: UILabel!
    @IBOutlet weak var worldMappingStatusLabel: UILabel!
    @IBOutlet weak var updateRateLabel: UILabel!
    
    // constants for collecting data
    let numTextFiles = 3
    let ARKIT_CAMERA_POSE = 0
    let ACCELEROMETER = 1
    let GYRO = 2
    var isRecording: Bool = false
    let customQueue: DispatchQueue = DispatchQueue(label: "Processing")
    let imuQueue: OperationQueue = OperationQueue()
    let motionManager = CMMotionManager();
    let startString = String(DateFormatter.localizedString(from: Date(), dateStyle: .medium, timeStyle: .short));
    var log_K=true;
  
    
    var documentURL: NSURL {
        let documentURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0] as NSURL
        let documentURLCur = documentURL.appendingPathComponent(startString, isDirectory: true)
        if !FileManager.default.fileExists(atPath: documentURLCur!.path) {
            do {
                try FileManager.default.createDirectory(at: documentURLCur!, withIntermediateDirectories: true, attributes: nil)
            } catch {
                print(error.localizedDescription)
            }
        }
        return documentURLCur as! NSURL
    }
    
    var depthMapURL: NSURL {
        let depthMapURL = documentURL.appendingPathComponent("DepthMap", isDirectory: true)
        if !FileManager.default.fileExists(atPath: depthMapURL!.path) {
            do {
                try FileManager.default.createDirectory(at: depthMapURL!, withIntermediateDirectories: true, attributes: nil)
            } catch {
                print(error.localizedDescription)
            }
        }
        
        return depthMapURL! as NSURL
    }
    
    var gravURL: NSURL {
        let gravURL = documentURL.appendingPathComponent("Grav", isDirectory: true)
        if !FileManager.default.fileExists(atPath: gravURL!.path) {
            do {
                try FileManager.default.createDirectory(at: gravURL!, withIntermediateDirectories: true, attributes: nil)
            } catch {
                print(error.localizedDescription)
            }
        }
        
        return gravURL! as NSURL
    }
    
    var capturedImageURL: NSURL {
        let capturedImageURL = documentURL.appendingPathComponent("CapturedImage", isDirectory: true)
        if !FileManager.default.fileExists(atPath: capturedImageURL!.path) {
            do {
                try FileManager.default.createDirectory(at: capturedImageURL!, withIntermediateDirectories: true, attributes: nil)
            } catch {
                print(error.localizedDescription)
            }
        }
        return capturedImageURL! as NSURL
    }
    
    var dateFormat: DateFormatter {
        let format = DateFormatter()
        format.dateFormat = "yyyyMMddHHmmssSSS"
        return format
    }
    // variables for measuring time in iOS clock
    var recordingTimer: Timer = Timer()
    var secondCounter: Int64 = 0 {
        didSet {
            statusLabel.text = interfaceIntTime(second: secondCounter)
        }
    }
    var previousTimestamp: Double = 0
    
    let mulSecondToNanoSecond: Double = 1000000000
    
    //init offset and synchronization variable
    var offset = 0.0;
    
    var gyroStack = [[Double]]();
    var accelStack = [[Double]]();
    //let accelFile = "accel.bin"
    
    
    
    // text file input & output
    var fileHandlers = [FileHandle]()
    var fileURLs = [URL]()
    var fileNames: [String] = ["ARKit_camera_pose.txt", "accelerometer.txt","gyro.txt"]
    
    var binfileURLAccel = URL(string: "");
    
    override func viewDidLoad() {
        super.viewDidLoad()
        if ((motionManager.isAccelerometerAvailable) != nil) {
//            motionManager.accelerometerUpdateInterval = 0.1
            motionManager.startDeviceMotionUpdates(to: .main) { (motion, error) in
            }
        }
        
        binfileURLAccel = documentURL.appendingPathComponent("accel.bin");
        
        // set debug option
        self.sceneView.debugOptions = [ARSCNDebugOptions.showFeaturePoints, ARSCNDebugOptions.showWorldOrigin]
        
        //set status to time synchronization
        self.statusLabel.text = "Time Sync"
        
        Clock.sync (from:"fi.pool.ntp.org",samples:5,completion: { date, offset in
            if(offset==nil){
                print("sync failed");
                exit(0)
            }else{
                var uptime = ProcessInfo.processInfo.systemUptime;
                self.offset = date!.timeIntervalSince1970 - uptime
                self.statusLabel.text = "Ready"
                print("completed synchronization with offset:",offset)
                AudioServicesPlaySystemSound(1003);
                var timer = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in
                    Clock.sync (from:"fi.pool.ntp.org",samples: 2, completion: { date, offset in
                        var uptime = ProcessInfo.processInfo.systemUptime;
                        self!.offset = date!.timeIntervalSince1970 - uptime;
                        print("resynhronization with offset:",offset)
                    } );
                }
            }
            
        } );
        
        // set the view's delegate
        sceneView.delegate = self
        sceneView.showsStatistics = true
        sceneView.session.delegate = self
    }
    
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        
        // Create a session configuration
        let configuration = ARWorldTrackingConfiguration()
        if type(of: configuration).supportsFrameSemantics(.sceneDepth) {
            configuration.frameSemantics = [.sceneDepth, .smoothedSceneDepth]
        }
        // Run the view's session
        sceneView.session.run(configuration)
    }
    
    
    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        
        // Pause the view's session
        sceneView.session.pause()
    }
    
    
    // when the Start/Stop button is pressed
    @IBAction func startStopButtonPressed(_ sender: UIButton) {
        if (self.isRecording == false) {
            
            self.motionManager.startGyroUpdates(to: imuQueue) { (motion, error) in
                let timestamp =  (motion?.timestamp ?? 0)! + self.offset; //* self.mulSecondToNanoSecond
                let gyroString = String(format: "%.6f %.6f %.6f %.6f \n",
                                        timestamp,motion!.rotationRate.x, motion!.rotationRate.y, motion!.rotationRate.z)
                if let GyroDataToWrite = gyroString.data(using: .utf8) {
                    do{
                        if (self.isRecording){
                            try self.fileHandlers[self.GYRO].write(GyroDataToWrite)
                }}
                    catch {
                        os_log("error")
                    }
                } else {
                    os_log("Failed to write data record", log: OSLog.default, type: .fault)
                }
                
            }
            self.motionManager.startAccelerometerUpdates(to: imuQueue) { (motion, error) in
                let timestamp =  (motion?.timestamp ?? 0)! + self.offset; //* self.mulSecondToNanoSecond
                let accString = String(format: "%.6f %.6f %.6f %.6f \n",
                                        timestamp, motion!.acceleration.x, motion!.acceleration.y, motion!.acceleration.z)
                if let AccDataToWrite = accString.data(using: .utf8) {
                    do{
                        if (self.isRecording){
                            try self.fileHandlers[self.ACCELEROMETER].write(AccDataToWrite)
                        }}
                    catch {
                        os_log("error")
                    }
                } else {
                    os_log("Failed to write data record", log: OSLog.default, type: .fault)
                }
            }
            
            // start ARKit data recording
            customQueue.async {
                if (self.createFiles()) {
                    DispatchQueue.main.async {
                        // reset timer
                        self.secondCounter = 0
                        self.recordingTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true, block: { (Timer) -> Void in
                            self.secondCounter += 1
                        })
                        
                        // update UI
                        self.startStopButton.setTitle("Stop", for: .normal)
                        
                        // make sure the screen won't lock
                        UIApplication.shared.isIdleTimerDisabled = true
                    }
                    self.isRecording = true
                } else {
                    self.errorMsg(msg: "Failed to create the file")
                    return
                }
            }
        } else {
            self.isRecording = false;
            // stop recording and share the recorded text file
            if (recordingTimer.isValid) {
                recordingTimer.invalidate()
            }
            self.motionManager.stopGyroUpdates();
            self.motionManager.stopAccelerometerUpdates();
            
            customQueue.async {
             
                // close the file handlers
                if (self.fileHandlers.count == self.numTextFiles) {
                    
                    let handlerPose = self.fileHandlers[self.ARKIT_CAMERA_POSE]
                    handlerPose.closeFile()
                    let handlerAcc = self.fileHandlers[self.ACCELEROMETER]
                    handlerAcc.closeFile()
                    let handlerGyro = self.fileHandlers[self.GYRO]
                    handlerGyro.closeFile()
                    
                    DispatchQueue.main.async {
                        let activityVC = UIActivityViewController(activityItems: self.fileURLs, applicationActivities: nil)
                        self.present(activityVC, animated: true, completion: nil)
                    }
                }
            }
            
            // initialize UI on the screen
            self.numberOfFeatureLabel.text = ""
            self.trackingStatusLabel.text = ""
            self.worldMappingStatusLabel.text = ""
            self.updateRateLabel.text = ""
            
            self.startStopButton.setTitle("Start", for: .normal)
            self.statusLabel.text = "Ready"
            
            // resume screen lock
            UIApplication.shared.isIdleTimerDisabled = false
        }
    }
    
    
    
    
    // define if ARSession is didUpdate (callback function)
    func session(_ session: ARSession, didUpdate frame: ARFrame) {
        
        // obtain current transformation 4x4 matrix
        let timestamp =  frame.timestamp + self.offset; //* self.mulSecondToNanoSecond
        
//        print(timestamp);
        let updateRate = 1 / Double(timestamp - previousTimestamp)
        //let updateRate = self.mulSecondToNanoSecond / Double(timestamp - previousTimestamp)
        previousTimestamp = timestamp
        
        let imageFrame = frame.capturedImage
        let imageResolution = frame.camera.imageResolution
        

        if(self.log_K){
            self.log_K=false;
            let K = frame.camera.intrinsics
            
            let filename = documentURL.appendingPathComponent("intrinsics.txt")
            let K_string = [String(K[0,0]),String(K[1,0]),String(K[2,0]),String(K[0,1]),String(K[1,1]),String(K[2,1]),String(K[0,2]),String(K[1,2]),String(K[2,2])].joined(separator: " ")
            do {
                try K_string.write(to: filename!, atomically: true, encoding: String.Encoding.utf8)
            } catch {
                // failed to write file – bad permissions, bad filename, missing permissions, or more likely it can't be converted to the encoding
            }
        }
        
        let ARKitWorldMappingStatus = frame.worldMappingStatus.rawValue
        let ARKitTrackingState = frame.camera.trackingState
        let T_gc = frame.camera.transform
        
        let r_11 = T_gc.columns.0.x
        let r_12 = T_gc.columns.1.x
        let r_13 = T_gc.columns.2.x
        
        let r_21 = T_gc.columns.0.y
        let r_22 = T_gc.columns.1.y
        let r_23 = T_gc.columns.2.y
        
        let r_31 = T_gc.columns.0.z
        let r_32 = T_gc.columns.1.z
        let r_33 = T_gc.columns.2.z
        
        let t_x = T_gc.columns.3.x
        let t_y = T_gc.columns.3.y
        let t_z = T_gc.columns.3.z
        
        // dispatch queue to display UI
        DispatchQueue.main.async {
            
            self.trackingStatusLabel.text = "\(ARKitTrackingState)"
            self.updateRateLabel.text = String(format:"%.3f Hz", updateRate)
            
            var worldMappingStatus = ""
            switch ARKitWorldMappingStatus {
            case 0:
                worldMappingStatus = "notAvailable"
            case 1:
                worldMappingStatus = "limited"
            case 2:
                worldMappingStatus = "extending"
            case 3:
                worldMappingStatus = "mapped"
            default:
                worldMappingStatus = "switch default?"
            }
            self.worldMappingStatusLabel.text = "\(worldMappingStatus)"
        }
        
        // custom queue to save ARKit processing data
        DispatchQueue.global(qos: .userInteractive).async {[self] in
        
            if ((self.fileHandlers.count == self.numTextFiles) && self.isRecording) {
                
                var gravVector = [Double]()
            
                gravVector.append((self.motionManager.deviceMotion?.gravity.x)!)
                gravVector.append((self.motionManager.deviceMotion?.gravity.y)!)
                gravVector.append((self.motionManager.deviceMotion?.gravity.z)!)
                
                /*var accelVec = [Double]()
                accelVec.append(self.motionManager.accelerometerData?.acceleration.x ?? 0);
                accelVec.append(self.motionManager.accelerometerData?.acceleration.y ?? 0);
                accelVec.append(self.motionManager.accelerometerData?.acceleration.z ?? 0);
                var gyroVec = [Double]()
                gyroVec.append(self.motionManager.gyroData?.rotationRate.x ?? 0);
                gyroVec.append(self.motionManager.gyroData?.rotationRate.y ?? 0);
                gyroVec.append(self.motionManager.gyroData?.rotationRate.z ?? 0);
                
                
                accelStack.append(accelVec);
                gyroStack.append(accelVec);*/
                
                
//                binfileURLAccel
//                print(accelVec);
//                print(gyroVec);
              
               
                
                let gravFile = "grav_\(timestamp).bin"
                let binfileURLGrav = self.gravURL.appendingPathComponent(gravFile)

                let wData = Data(bytes: &gravVector, count: gravVector.count * MemoryLayout<Double>.stride)
                try! wData.write(to: binfileURLGrav!)
                
            if let depth = frame.depthMap {
              
                let depthWidth = CVPixelBufferGetWidth(depth)
                let depthHeight = CVPixelBufferGetHeight(depth)
               
                CVPixelBufferLockBaseAddress(depth, CVPixelBufferLockFlags.readOnly)
                let floatBuffer = unsafeBitCast(CVPixelBufferGetBaseAddress(depth), to: UnsafeMutablePointer<Float>.self)
                
                var depthArray = [Float32]()
                for x in 0...((depthHeight)*(depthWidth)){
                    depthArray.append(floatBuffer[x])
                }
                CVPixelBufferUnlockBaseAddress(depth, CVPixelBufferLockFlags.readOnly)
                
                //test
                let binFile = "depth_\(timestamp).bin"
                let binfileURLImage = self.depthMapURL.appendingPathComponent(binFile)

                let wData = Data(bytes: &depthArray, count: depthArray.count * MemoryLayout<Float>.stride)
                try! wData.write(to: binfileURLImage!)

              }

            let capturedImage = frame.capturedImageAsDepthMapScale

            let filenameImage = "capturedImage_\(timestamp).jpg"
                let fileURLImage = self.capturedImageURL.appendingPathComponent(filenameImage)

            if let image = capturedImage?.jpegData(compressionQuality: 0.9) {
                try? image.write(to: fileURLImage!)
            }
                
                // 1) record ARKit 6-DoF camera pose
                let ARKitPoseData = String(format: "%.6f %.6f %.6f %.6f %.6f %.6f %.6f %.6f %.6f %.6f %.6f %.6f %.6f \n",
                                           timestamp,
                                           r_11, r_12, r_13, t_x,
                                           r_21, r_22, r_23, t_y,
                                           r_31, r_32, r_33, t_z)
                if let ARKitPoseDataToWrite = ARKitPoseData.data(using: .utf8) {
                    do{
                        if (self.isRecording){
                            try self.fileHandlers[self.ARKIT_CAMERA_POSE].write(ARKitPoseDataToWrite)
                        }
                        }
                    catch {
                        // Couldn't create audio player object, log the error
                        print("error")
                    }
                } else {
                    os_log("Failed to write data record", log: OSLog.default, type: .fault)
                }
                
              
            }
        }
    }
    
    
    // some useful functions
    private func errorMsg(msg: String) {
        DispatchQueue.main.async {
            let fileAlert = UIAlertController(title: "ARKit-Data-Logger", message: msg, preferredStyle: .alert)
            fileAlert.addAction(UIAlertAction(title: "OK", style: .cancel, handler: nil))
            self.present(fileAlert, animated: true, completion: nil)
        }
    }
    
    
    private func createFiles() -> Bool {
        
        // initialize file handlers
        self.fileHandlers.removeAll()
        self.fileURLs.removeAll()
        
        // create ARKit result text files
        let startHeader = ""
        for i in 0...(self.numTextFiles - 1) {
            var url =  documentURL as URL
            url.appendPathComponent(fileNames[i])
            self.fileURLs.append(url)
            
            // delete previous text files
            if (FileManager.default.fileExists(atPath: url.path)) {
                do {
                    try FileManager.default.removeItem(at: url)
                } catch {
                    os_log("cannot remove previous file", log:.default, type:.error)
                    return false
                }
            }
            
            // create new text files
            if (!FileManager.default.createFile(atPath: url.path, contents: startHeader.data(using: String.Encoding.utf8), attributes: nil)) {
                self.errorMsg(msg: "cannot create file \(self.fileNames[i])")
                return false
            }
            
            // assign new file handlers
            let fileHandle: FileHandle? = FileHandle(forWritingAtPath: url.path)
            if let handle = fileHandle {
                self.fileHandlers.append(handle)
            } else {
                return false
            }
        }
        
        // write current recording time information
        let timeHeader = "# Created at \(timeToString()) in Helsinki Hood \n"
        for i in 0...(self.numTextFiles - 1) {
            if let timeHeaderToWrite = timeHeader.data(using: .utf8) {
                self.fileHandlers[i].write(timeHeaderToWrite)
            } else {
                os_log("Failed to write data record", log: OSLog.default, type: .fault)
                return false
            }
        }
        
        // return true if everything is alright
        return true
    }
    
    
    private func IBAPixelBufferGetPlanarBuffer(pixelBuffer: CVPixelBuffer, planeIndex: size_t) -> vImage_Buffer {
        
        // assumes that pixel buffer base address is already locked
        let baseAddress = CVPixelBufferGetBaseAddressOfPlane(pixelBuffer, planeIndex)
        let bytesPerRow = CVPixelBufferGetBytesPerRowOfPlane(pixelBuffer, planeIndex)
        let width = CVPixelBufferGetWidthOfPlane(pixelBuffer, planeIndex)
        let height = CVPixelBufferGetHeightOfPlane(pixelBuffer, planeIndex)
        
        return vImage_Buffer(data: baseAddress, height: vImagePixelCount(height), width: vImagePixelCount(width), rowBytes: bytesPerRow)
    }
    
    
    private func IBASampleScaledCapturedPixelBuffer(imageFrame: CVPixelBuffer, scale: Double) -> (vImage_Buffer, vImage_Buffer) {
        
        // calculate scaled size for buffers
        let baseWidth = Double(CVPixelBufferGetWidth(imageFrame))
        let baseHeight = Double(CVPixelBufferGetHeight(imageFrame))
        
        let scaledWidth = vImagePixelCount(ceil(baseWidth * scale))
        let scaledHeight = vImagePixelCount(ceil(baseHeight * scale))
        
        
        // lock the source pixel buffer
        CVPixelBufferLockBaseAddress(imageFrame, CVPixelBufferLockFlags.readOnly)
        
        // allocate buffer for scaled Luma & retrieve address of source Luma and scale it
        var scaledLumaBuffer = vImage_Buffer()
        var sourceLumaBuffer = self.IBAPixelBufferGetPlanarBuffer(pixelBuffer: imageFrame, planeIndex: 0)
        vImageBuffer_Init(&scaledLumaBuffer, scaledHeight, scaledWidth, 8, vImage_Flags(kvImagePrintDiagnosticsToConsole))
        vImageScale_Planar8(&sourceLumaBuffer, &scaledLumaBuffer, nil, vImage_Flags(kvImagePrintDiagnosticsToConsole))
        
        // allocate buffer for scaled CbCr & retrieve address of source CbCr and scale it
        var scaledCbcrBuffer = vImage_Buffer()
        var sourceCbcrBuffer = self.IBAPixelBufferGetPlanarBuffer(pixelBuffer: imageFrame, planeIndex: 1)
        vImageBuffer_Init(&scaledCbcrBuffer, scaledHeight, scaledWidth, 8, vImage_Flags(kvImagePrintDiagnosticsToConsole))
        vImageScale_CbCr8(&sourceCbcrBuffer, &scaledCbcrBuffer, nil, vImage_Flags(kvImagePrintDiagnosticsToConsole))
        
        // unlock source buffer now
        CVPixelBufferUnlockBaseAddress(imageFrame, CVPixelBufferLockFlags.readOnly)
        
        
        // return the scaled Luma and CbCr buffer
        return (scaledLumaBuffer, scaledCbcrBuffer)
    }
}
