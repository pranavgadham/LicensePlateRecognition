//
//  RecognizeTextOperation.swift
//  LicensePlateRecognition
//

import AVFoundation
import Vision
import CoreImage

class RecognizeTextOperation: Operation {
    let cgImage: CGImage
    let region: CGRect
    var recognizedText: String?
    
    // MARK: - Operation State
    private var _executing = false {
        willSet { willChangeValue(forKey: "isExecuting") }
        didSet { didChangeValue(forKey: "isExecuting") }
    }
    
    private var _finished = false {
        willSet { willChangeValue(forKey: "isFinished") }
        didSet { didChangeValue(forKey: "isFinished") }
    }
    
    override var isExecuting: Bool { return _executing }
    override var isFinished: Bool { return _finished }
    override var isAsynchronous: Bool { return true }
    
    private let processingQueue = DispatchQueue(label: "TextRecognitionQueue", qos: .userInitiated)
    
    // License plate patterns
    private let patterns = [
        // Standard Indian format: 2 letters + 2 digits + 4 letters/digits (e.g., MH12AB1234)
        "^[A-Z]{2}\\s*\\d{1,2}\\s*[A-Z]{1,3}\\s*\\d{4}$",
        // Generic format with spaces
        "[A-Z]{2}\\s*[0-9]{1,2}\\s*[A-Z]{1,3}\\s*[0-9]{4}",
        // Format without spaces
        "[A-Z]{2}[0-9]{1,2}[A-Z]{1,3}[0-9]{4}"
    ]
    
    init(cgImage: CGImage, region: CGRect) {
        self.cgImage = cgImage
        self.region = region
        super.init()
    }
    
    override func start() {
        guard !isCancelled else {
            finish()
            return
        }
        
        _executing = true
        print("Starting text recognition operation")
        
        processingQueue.async { [weak self] in
            guard let self = self else { return }
            
            print("Processing image for text recognition")
            
            // Create request handler
            let requestHandler = VNImageRequestHandler(
                cgImage: self.cgImage,
                orientation: .up,
                options: [:]
            )
            
            // Create text recognition request
            let request = VNRecognizeTextRequest { [weak self] request, error in
                guard let self = self else { return }
                
                if let error = error {
                    print("Text recognition error: \(error)")
                    self.finish()
                    return
                }
                
                guard let observations = request.results as? [VNRecognizedTextObservation] else {
                    print("No text observations found")
                    self.finish()
                    return
                }
                
                // Process all text candidates
                var allCandidates = [String]()
                for observation in observations {
                    // Get multiple candidates for each observation
                    let candidates = observation.topCandidates(10).compactMap { $0.string }
                    allCandidates.append(contentsOf: candidates)
                }
                
                print("Found \(allCandidates.count) text candidates")
                
                // Process candidates to find license plates
                let plates = self.findLicensePlates(in: allCandidates)
                
                if let bestPlate = plates.first {
                    print("Found license plate: \(bestPlate)")
                    self.recognizedText = bestPlate
                } else {
                    print("No valid license plate found")
                }
                
                self.finish()
            }
            
            // Configure the request
            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = false
            request.regionOfInterest = self.region
            request.recognitionLanguages = ["en-US"]
            request.minimumTextHeight = 0.1
            
            do {
                try requestHandler.perform([request])
            } catch {
                print("Failed to perform recognition: \(error)")
                self.finish()
            }
        }
    }
    
    private func findLicensePlates(in candidates: [String]) -> [String] {
        var validPlates = [String]()
        
        for candidate in candidates {
            // Clean the text: remove spaces and unwanted characters
            let cleanText = candidate.replacingOccurrences(of: " ", with: "")
                                   .trimmingCharacters(in: .whitespacesAndNewlines)
                                   .uppercased()
            
            // Check against all patterns
            for pattern in patterns {
                if let regex = try? NSRegularExpression(pattern: pattern) {
                    let range = NSRange(cleanText.startIndex..., in: cleanText)
                    if regex.firstMatch(in: cleanText, range: range) != nil {
                        print("Found matching plate: \(cleanText)")
                        validPlates.append(cleanText)
                        break
                    }
                }
            }
        }
        
        return validPlates
    }
    
    private func finish() {
        DispatchQueue.main.async {
            self._executing = false
            self._finished = true
            print("Text recognition operation completed with result: \(self.recognizedText ?? "none")")
        }
    }
} 