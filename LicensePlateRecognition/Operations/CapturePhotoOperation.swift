//
//  CapturePhotoOperation.swift
//  LicensePlateRecognition
//
//  Created by Shawn Gee on 9/20/20.
//  Copyright © 2020 Swift Student. All rights reserved.
//

import AVFoundation
import UIKit

class CapturePhotoOperation: ConcurrentOperation, AVCapturePhotoCaptureDelegate {
    var cgImage: CGImage?
    var image: UIImage?
    private var captureStarted = false
    private var imageProcessed = false
    private var hasCalledCompletion = false  // Add flag to track completion
    
    // Add state enum to match Objective-C implementation
    enum State {
        case ready
        case executing
        case finished
    }
    
    // Add state property
    private var _state = State.ready
    @objc dynamic var state: SSConcurrentOperationState {
        get {
            switch _state {
            case .ready: return .ready
            case .executing: return .executing
            case .finished: return .finished
            }
        }
        set {
            switch newValue {
            case .ready: _state = .ready
            case .executing: _state = .executing
            case .finished: _state = .finished
            }
        }
    }
    
    override func main() {
        // Set state to executing if not already done by superclass
        if !self.isExecuting && !self.isFinished {
            self.state = .executing
        }
        
        // If photoOutput.capturePhoto() is never called, we need to ensure the operation completes
        DispatchQueue.main.asyncAfter(deadline: .now() + 10.0) { [weak self] in
            guard let self = self, !self.isFinished else { return }
            
            if !self.captureStarted {
                NotificationCenter.default.post(name: NSNotification.Name("PhotoCaptureError"), 
                                              object: nil, 
                                              userInfo: ["error": "Camera capture timed out. Please try again."])
                self.finish()
            }
        }
    }
    
    override func finish() {
        if !isFinished {
            // Call completion block before finishing the operation
            if !hasCalledCompletion, let completionBlock = completionBlock {
                hasCalledCompletion = true  // Set flag to prevent double execution
                
                // Ensure we're on the main queue for UI updates
                if Thread.isMainThread {
                    completionBlock()
                } else {
                    DispatchQueue.main.async {
                        completionBlock()
                    }
                }
            }
            
            super.finish()
        }
    }
    
    // Called when capture process begins
    func photoOutput(_ output: AVCapturePhotoOutput, willBeginCaptureFor resolvedSettings: AVCaptureResolvedPhotoSettings) {
        captureStarted = true
    }
    
    // Main processing method for the captured photo
    func photoOutput(_ output: AVCapturePhotoOutput,
                     didFinishProcessingPhoto photo: AVCapturePhoto,
                     error: Error?) {
        
        // Check for camera permission errors or hardware issues
        guard error == nil else {
            NotificationCenter.default.post(name: NSNotification.Name("PhotoCaptureError"), 
                                          object: nil, 
                                          userInfo: ["error": "Camera error: \(error!.localizedDescription)"])
            finish()
            return
        }
        
        // Check if we have valid image data
        guard let imageData = photo.fileDataRepresentation() else {
            NotificationCenter.default.post(name: NSNotification.Name("PhotoCaptureError"), 
                                          object: nil, 
                                          userInfo: ["error": "Failed to process image data"])
            finish()
            return
        }
        
        // Try a direct conversion to UIImage first, which is often more reliable
        if let directImage = UIImage(data: imageData) {
            self.image = directImage
            
            // If we have a UIImage but need a CGImage too
            if let cgImg = directImage.cgImage {
                self.cgImage = cgImg
                imageProcessed = true
                return
            }
        }
        
        // Fallback to CIImage path if direct conversion failed
        // Try to create CIImage from data
        guard let ciImage = CIImage(data: imageData) else {
            NotificationCenter.default.post(name: NSNotification.Name("PhotoCaptureError"), 
                                          object: nil, 
                                          userInfo: ["error": "Failed to process image format"])
            finish()
            return
        }
        
        // Create CGImage from CIImage
        let context = CIContext()
        guard let cgImage = context.createCGImage(ciImage, from: ciImage.extent) else {
            NotificationCenter.default.post(name: NSNotification.Name("PhotoCaptureError"), 
                                          object: nil, 
                                          userInfo: ["error": "Failed to create image format"])
            finish()
            return
        }
        
        self.cgImage = cgImage
        self.image = UIImage(cgImage: cgImage)
        imageProcessed = true
    }
    
    // Called when the entire capture sequence is completed
    func photoOutput(_ output: AVCapturePhotoOutput, didFinishCaptureFor resolvedSettings: AVCaptureResolvedPhotoSettings, error: Error?) {
        // This is the final delegate method called, so we finish the operation here
        if let error = error {
            NotificationCenter.default.post(name: NSNotification.Name("PhotoCaptureError"), 
                                          object: nil, 
                                          userInfo: ["error": "Camera capture failed: \(error.localizedDescription)"])
        }
        
        // If we don't have an image at this point, report an error
        if !imageProcessed || self.cgImage == nil || self.image == nil {
            NotificationCenter.default.post(name: NSNotification.Name("PhotoCaptureError"), 
                                          object: nil, 
                                          userInfo: ["error": "Failed to capture image. Please try again."])
        }
        
        // Always finish the operation
        finish()
    }
}
