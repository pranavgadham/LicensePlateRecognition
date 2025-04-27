//
//  LPRViewController.swift
//  LicensePlateRecognition
//
//  Created by Shawn Gee on 9/19/20.
//  Copyright © 2020 Swift Student. All rights reserved.
//

import UIKit
import AVFoundation
import Vision
import CoreLocation
import CoreML

class LPRViewController: UIViewController, CLLocationManagerDelegate {
    
    // MARK: - Public Properties
    
    var bufferSize: CGSize = .zero
    
    // MARK: - Private Properties
    
    @IBOutlet private var lprView: LPRView!
    
    private let captureSession = AVCaptureSession()
    private let videoDataOutput = AVCaptureVideoDataOutput()
    private let videoDataOutputQueue = DispatchQueue(label: "VideoDataOutput",
                                                     qos: .userInitiated,
                                                     attributes: [],
                                                     autoreleaseFrequency: .workItem)
    private let photoOutput = AVCapturePhotoOutput()
    private var requests = [VNRequest]()
    private let licensePlateController = LicensePlateController()
    
    // Operation Queues
    private let captureQueue = OperationQueue()
    
    // UI Elements
    private lazy var captureButton: UIButton = {
        let button = UIButton(type: .system)
        button.translatesAutoresizingMaskIntoConstraints = false
        button.setTitle("Capture", for: .normal)
        button.backgroundColor = .systemBlue
        button.setTitleColor(.white, for: .normal)
        button.layer.cornerRadius = 25
        button.addTarget(self, action: #selector(captureButtonTapped), for: .touchUpInside)
        return button
    }()
    
    // Location manager
    private let locationManager = CLLocationManager()
    private var currentLocation: CLLocation?
    
    // Store detected license plate rect
    private var detectedPlateRect: CGRect?
    
    // MARK: - View Lifecycle
    
    override func viewDidLoad() {
        super.viewDidLoad()
        setUp()
        setupLocationManager()
    }
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(true)
        captureSession.startRunning()
    }
    
    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        captureSession.stopRunning()
        
        // Remove notification observer when view disappears
        NotificationCenter.default.removeObserver(self, name: NSNotification.Name("PhotoCaptureError"), object: nil)
    }
    
    // MARK: - Private Methods
    
    private func setUp() {
        lprView.videoPlayerView.videoGravity = .resizeAspectFill
        setUpAVCapture()
        try? setUpVision()
        setupUI()
    }
    
    private func setupLocationManager() {
        locationManager.delegate = self
        locationManager.desiredAccuracy = kCLLocationAccuracyBest
        
        // Move location services check to background thread to prevent UI unresponsiveness
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }
            
            // Check for location services availability first
            if !CLLocationManager.locationServicesEnabled() {
                return
            }
            
            // Check authorization status before requesting location
            DispatchQueue.main.async {
                switch self.locationManager.authorizationStatus {
                case .notDetermined:
                    self.locationManager.requestWhenInUseAuthorization()
                case .authorizedWhenInUse, .authorizedAlways:
                    self.locationManager.startUpdatingLocation()
                case .restricted, .denied:
                    break
                @unknown default:
                    break
                }
            }
        }
    }
    
    private func setUpVision() throws {
        // Load ML model but don't request precision-recall curves which causes warnings
        let config = MLModelConfiguration()
        
        // Skip requesting parameters that might not be available
        config.computeUnits = .all
        
        let model = try LicensePlateDetector(configuration: config).model
        let visionModel = try VNCoreMLModel(for: model)
        
        let objectRecognition = VNCoreMLRequest(model: visionModel) { [weak self] request, error in
            guard let results = request.results as? [VNRecognizedObjectObservation] else { return }
            self?.processResults(results)
        }
        
        // Set other properties of the request
        objectRecognition.imageCropAndScaleOption = .scaleFill
        
        self.requests = [objectRecognition]
    }
    
    private func processResults(_ results: [VNRecognizedObjectObservation]) {
        // Process on a background thread
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }
            
            let rects = results.map {
                VNImageRectForNormalizedRect($0.boundingBox,
                                            Int(self.bufferSize.width),
                                            Int(self.bufferSize.height))
            }
            
            // Store the first detected plate rect (assuming it's the most prominent one)
            self.detectedPlateRect = rects.first
            
            self.licensePlateController.updateLicensePlates(withRects: rects)
            
            // perform drawing on main thread
            DispatchQueue.main.async {
                self.lprView.licensePlates = self.licensePlateController.licensePlates
            }
        }
    }
    
    // MARK: - CLLocationManagerDelegate
    
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        if let location = locations.last {
            currentLocation = location
        }
    }
    
    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        if let clError = error as? CLError {
            switch clError.code {
            case .denied:
                print("Location access denied: \(error.localizedDescription)")
                break
            case .network:
                print("Location network error: \(error.localizedDescription)")
                break
            case .locationUnknown:
                print("Location unknown error: \(error.localizedDescription)")
                break
            default:
                print("Location error: \(error.localizedDescription)")
                break
            }
        }
    }
    
    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        switch manager.authorizationStatus {
        case .authorizedWhenInUse, .authorizedAlways:
            locationManager.startUpdatingLocation()
        case .denied, .restricted:
            showAlert(title: "Location Access Required", 
                      message: "Location services are disabled for this app. To enable, please go to Settings > Privacy > Location Services.")
        case .notDetermined:
            break
        @unknown default:
            break
        }
    }
    
    private func setupUI() {
        view.addSubview(captureButton)
        view.bringSubviewToFront(captureButton)  // Ensure button is on top
        
        NSLayoutConstraint.activate([
            captureButton.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            captureButton.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -20),
            captureButton.widthAnchor.constraint(equalToConstant: 120),
            captureButton.heightAnchor.constraint(equalToConstant: 50)
        ])
        
        // Make button more visible
        captureButton.backgroundColor = .systemBlue.withAlphaComponent(0.8)
        captureButton.layer.shadowColor = UIColor.black.cgColor
        captureButton.layer.shadowOffset = CGSize(width: 0, height: 2)
        captureButton.layer.shadowRadius = 4
        captureButton.layer.shadowOpacity = 0.3
    }
    
    @objc private func captureButtonTapped() {
        // Check camera authorization status
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            break
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { granted in
                if granted {
                    DispatchQueue.main.async {
                        self.captureButtonTapped()
                    }
                } else {
                    DispatchQueue.main.async {
                        self.showAlert(title: "Camera Access Required", 
                                     message: "Please enable camera access in Settings to use this feature.")
                    }
                }
            }
            return
        case .denied, .restricted:
            showAlert(title: "Camera Access Required", 
                     message: "Please enable camera access in Settings to use this feature.")
            return
        @unknown default:
            return
        }

        // Ensure capture session is running before proceeding
        guard captureSession.isRunning else {
            DispatchQueue.main.async {
                self.showAlert(title: "Error", message: "Camera is not ready. Please try again.")
            }
            return
        }
        
        // Take a photo and process it
        let photoSettings = AVCapturePhotoSettings()
        
        // Configure photo settings for optimal text recognition
        photoSettings.previewPhotoFormat = [
            kCVPixelBufferPixelFormatTypeKey as String: Int(kCVPixelFormatType_32BGRA),
            kCVPixelBufferWidthKey as String: 640,
            kCVPixelBufferHeightKey as String: 480
        ]
        
        // Use high resolution capture with proper dimension checks
        if #available(iOS 16.0, *) {
            photoSettings.maxPhotoDimensions = CMVideoDimensions(width: 640, height: 480)
        } else {
            photoSettings.isHighResolutionPhotoEnabled = false
        }
        
        let captureOperation = CapturePhotoOperation()
        
        // Register for photo capture error notifications
        NotificationCenter.default.removeObserver(self, name: NSNotification.Name("PhotoCaptureError"), object: nil)
        NotificationCenter.default.addObserver(self, 
                                             selector: #selector(handlePhotoCaptureError(_:)), 
                                             name: NSNotification.Name("PhotoCaptureError"), 
                                             object: nil)
        
        // Configure operation queue
        captureQueue.maxConcurrentOperationCount = 1
        
        // Add completion block to capture operation
        captureOperation.completionBlock = { [weak self] in
            guard let self = self else { return }
            
            guard let capturedImage = captureOperation.image else {
                DispatchQueue.main.async {
                    self.showAlert(title: "Error", message: "Failed to process captured image")
                    // Ensure camera keeps running if there's an error
                    self.captureSession.startRunning()
                }
                return
            }
            
            // Navigate to confirmation screen with the detected plate rect
            DispatchQueue.main.async {
                self.captureSession.stopRunning()
                
                let confirmationVC = LicensePlateConfirmationViewController(
                    image: capturedImage,
                    recognizedText: nil,
                    location: self.currentLocation,
                    plateRect: self.detectedPlateRect  // Pass the detected rect
                )
                confirmationVC.modalPresentationStyle = .fullScreen
                
                confirmationVC.dismissalHandler = { [weak self] in
                    guard let self = self else { return }
                    self.captureSession.startRunning()
                }
                
                self.present(confirmationVC, animated: true) {
                    self.captureQueue.cancelAllOperations()
                }
            }
        }
        
        // Start photo capture
        captureQueue.addOperation(captureOperation)
        
        // Capture photo with delegate
        photoOutput.capturePhoto(with: photoSettings, delegate: captureOperation)
    }
    
    private func setUpAVCapture() {
        var deviceInput: AVCaptureDeviceInput!
        
        // Select a video device, make an input
        guard let videoDevice = AVCaptureDevice.DiscoverySession(
            deviceTypes: [.builtInWideAngleCamera],
            mediaType: .video,
            position: .back).devices.first else {
            print("Error: No video device found")
            return
        }
        
        do {
            deviceInput = try AVCaptureDeviceInput(device: videoDevice)
            
            // Configure device for better capture
            try videoDevice.lockForConfiguration()
            if videoDevice.isFocusModeSupported(.continuousAutoFocus) {
                videoDevice.focusMode = .continuousAutoFocus
            }
            if videoDevice.isExposureModeSupported(.continuousAutoExposure) {
                videoDevice.exposureMode = .continuousAutoExposure
            }
            videoDevice.unlockForConfiguration()
        } catch {
            print("Error configuring video device: \(error.localizedDescription)")
            return
        }
        
        captureSession.beginConfiguration()
        
        captureSession.sessionPreset = .vga640x480
        
        // Add a video input
        guard captureSession.canAddInput(deviceInput) else {
            captureSession.commitConfiguration()
            return
        }
        captureSession.addInput(deviceInput)
        
        // Add video output
        if captureSession.canAddOutput(videoDataOutput) {
            captureSession.addOutput(videoDataOutput)
            videoDataOutput.alwaysDiscardsLateVideoFrames = true
            videoDataOutput.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: Int(kCVPixelFormatType_420YpCbCr8BiPlanarFullRange)]
            videoDataOutput.setSampleBufferDelegate(self, queue: videoDataOutputQueue)
        } else {
            captureSession.commitConfiguration()
            return
        }
        
        let captureConnection = videoDataOutput.connection(with: .video)
        captureConnection?.isEnabled = true
        
        // Get buffer size
        do {
            try videoDevice.lockForConfiguration()
            let dimensions = CMVideoFormatDescriptionGetDimensions((videoDevice.activeFormat.formatDescription))
            bufferSize.width = CGFloat(dimensions.width)
            bufferSize.height = CGFloat(dimensions.height)
            videoDevice.unlockForConfiguration()
        } catch {
        }
        
        // Add photo output
        if captureSession.canAddOutput(photoOutput) {
            // Configure for VGA resolution to match video feed
            photoOutput.isHighResolutionCaptureEnabled = false
            photoOutput.maxPhotoQualityPrioritization = .speed
            
            captureSession.addOutput(photoOutput)
            
            // Ensure photo output connection matches video orientation
            if let photoConnection = photoOutput.connection(with: .video) {
                photoConnection.videoOrientation = .portrait
                photoConnection.isEnabled = true
            }
        }
        
        captureSession.commitConfiguration()
        
        lprView.bufferSize = bufferSize
        lprView.session = captureSession
    }
    
    @objc private func handlePhotoCaptureError(_ notification: Notification) {
        // Remove observer to prevent multiple notifications
        NotificationCenter.default.removeObserver(self, name: NSNotification.Name("PhotoCaptureError"), object: nil)
        
        // Extract error message from notification
        if let userInfo = notification.userInfo,
           let errorMessage = userInfo["error"] as? String {
            print("Photo capture error: \(errorMessage)")
            DispatchQueue.main.async {
                self.showAlert(title: "Camera Error", message: errorMessage)
            }
        }
    }
    
    private func showAlert(title: String, message: String) {
        let alert = UIAlertController(title: title, message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "OK", style: .default))
        present(alert, animated: true)
    }
}

// MARK: - Video Data Output Delegate

extension LPRViewController: AVCaptureVideoDataOutputSampleBufferDelegate {
    func captureOutput(_ output: AVCaptureOutput,
                       didOutput sampleBuffer: CMSampleBuffer,
                       from connection: AVCaptureConnection) {
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else {
            return
        }
        
        let imageRequestHandler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer,
                                                       orientation: .currentRearCameraOrientation,
                                                       options: [:])
        do {
            try imageRequestHandler.perform(self.requests)
        } catch {
        }
    }
    
    func captureOutput(_ captureOutput: AVCaptureOutput,
                       didDrop didDropSampleBuffer: CMSampleBuffer,
                       from connection: AVCaptureConnection) {
    }
}
