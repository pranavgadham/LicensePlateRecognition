//
//  RecognizeTextOperation.swift
//  LicensePlateRecognition
//
//  Created by Shawn Gee on 9/20/20.
//  Copyright © 2020 Swift Student. All rights reserved.
//

import AVFoundation
import Vision
import CoreImage

class RecognizeTextOperation: ConcurrentOperation {
    let cgImage: CGImage
    let region: CGRect
    var recognizedText: String?
    
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
    
    private var accurateRequest: VNRecognizeTextRequest!
    private var fastRequest: VNRecognizeTextRequest!
    private let processingQueue = DispatchQueue(label: "TextRecognitionQueue", qos: .userInitiated)
    
    // License plate patterns for different regions
    // Standard Indian format: 2 letters + 2 digits + 4 letters/digits (e.g., MH12AB1234)
    private let indianPlatePattern = "^[A-Z]{2}\\s*[0-9]{1,2}\\s*[A-Z]{1,3}\\s*[0-9]{1,4}$"
    // Generic alphanumeric pattern for other formats
    private let genericPlatePattern = "^[A-Z0-9]{5,10}$"
    
    // Character sets for filtering and correction
    private let allowedCharacters = "ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789"
    private let commonConfusions = [
        "0": "O", "O": "0",
        "1": "I", "I": "1",
        "8": "B", "B": "8",
        "5": "S", "S": "5",
        "2": "Z", "Z": "2"
    ]
    
    // Minimum height for text to be considered
    private let minHeight: CGFloat = 0.15
    
    init(cgImage: CGImage, region: CGRect) {
        self.cgImage = cgImage
        self.region = region
    }
    
    override func main() {
        // Set state to executing if not already done by superclass
        if !self.isExecuting && !self.isFinished {
            self.state = .executing
        }
        
        // Create both fast and accurate recognition requests
        setupTextRecognitionRequests()
        
        // Process the image with different techniques
        processingQueue.async { [weak self] in
            guard let self = self else { return }
            
            // Try multiple approaches and take the best result
            let results = self.performMultipleRecognitionAttempts()
            
            // Process and select the best result
            if let bestResult = self.selectBestResult(from: results) {
                self.recognizedText = bestResult
            }
            
            // Ensure we finish the operation
            self.finish()
        }
    }
    
    private func setupTextRecognitionRequests() {
        // Fast recognition request - for quick initial results
        fastRequest = VNRecognizeTextRequest { [weak self] request, error in
            // Handled in performRecognition method
        }
        fastRequest.recognitionLevel = .fast
        fastRequest.usesLanguageCorrection = false
        fastRequest.regionOfInterest = region
        fastRequest.recognitionLanguages = ["en-US"]
        
        // Accurate recognition request - for more precise results
        accurateRequest = VNRecognizeTextRequest { [weak self] request, error in
            // Handled in performRecognition method
        }
        accurateRequest.recognitionLevel = .accurate
        accurateRequest.usesLanguageCorrection = false
        accurateRequest.regionOfInterest = region
        accurateRequest.recognitionLanguages = ["en-US"]
        accurateRequest.customWords = ["MH", "DL", "KA", "TN", "AP", "TS", "GJ", "RJ", "UP", "MP"] // Common Indian state codes
    }
    
    private func performMultipleRecognitionAttempts() -> [String] {
        var allResults = [String]()
        
        // 1. Try with original image using fast recognition
        if let results = performRecognition(with: fastRequest, on: cgImage) {
            allResults.append(contentsOf: results)
        }
        
        // 2. Try with original image using accurate recognition
        if let results = performRecognition(with: accurateRequest, on: cgImage) {
            allResults.append(contentsOf: results)
        }
        
        // 3. Try with preprocessed images
        if let enhancedImage = preprocessImage(cgImage) {
            if let results = performRecognition(with: accurateRequest, on: enhancedImage) {
                allResults.append(contentsOf: results)
            }
        }
        
        // 4. If scanning the full image and no results found, try a more aggressive approach
        if region.width == 1 && region.height == 1 && allResults.isEmpty {
            // Apply additional preprocessing for full image scanning
            if let highContrastImage = applyHighContrastFilters(cgImage) {
                if let results = performRecognition(with: accurateRequest, on: highContrastImage) {
                    allResults.append(contentsOf: results)
                }
            }
        }
        
        return allResults
    }
    
    private func preprocessImage(_ inputImage: CGImage) -> CGImage? {
        // Create CIImage from CGImage
        let ciImage = CIImage(cgImage: inputImage)
        let context = CIContext()
        
        // Apply a series of filters to enhance text visibility
        guard let enhancedImage = applyEnhancementFilters(to: ciImage) else {
            return nil
        }
        
        // Convert back to CGImage
        guard let outputCGImage = context.createCGImage(enhancedImage, from: enhancedImage.extent) else {
            return nil
        }
        
        return outputCGImage
    }
    
    private func applyEnhancementFilters(to image: CIImage) -> CIImage? {
        // 1. Increase contrast
        guard let contrastFilter = CIFilter(name: "CIColorControls") else { return nil }
        contrastFilter.setValue(image, forKey: kCIInputImageKey)
        contrastFilter.setValue(1.5, forKey: kCIInputContrastKey) // Increase contrast
        contrastFilter.setValue(0.0, forKey: kCIInputBrightnessKey) // Neutral brightness
        contrastFilter.setValue(1.0, forKey: kCIInputSaturationKey) // Neutral saturation
        
        guard let contrastImage = contrastFilter.outputImage else { return nil }
        
        // 2. Apply unsharp mask to sharpen edges
        guard let sharpenFilter = CIFilter(name: "CIUnsharpMask") else { return nil }
        sharpenFilter.setValue(contrastImage, forKey: kCIInputImageKey)
        sharpenFilter.setValue(2.0, forKey: kCIInputRadiusKey) // Radius
        sharpenFilter.setValue(1.5, forKey: kCIInputIntensityKey) // Intensity
        
        return sharpenFilter.outputImage
    }
    
    private func performRecognition(with request: VNRecognizeTextRequest, on image: CGImage) -> [String]? {
        let requestHandler = VNImageRequestHandler(cgImage: image,
                                                   orientation: .currentRearCameraOrientation,
                                                   options: [:])
        do {
            try requestHandler.perform([request])
            
            guard let results = request.results as? [VNRecognizedTextObservation] else {
                return nil
            }
            
            // Get all candidates, not just top ones
            var allCandidates = [String]()
            
            for observation in results {
                // Get multiple candidates for each observation
                let candidates = observation.topCandidates(10).compactMap { $0.string }
                
                // Filter by height if needed
                if let firstCandidate = observation.topCandidates(1).first,
                   let box = try? firstCandidate.boundingBox(for: firstCandidate.string.startIndex..<firstCandidate.string.endIndex) {
                    
                    let height = box.topLeft.y - box.bottomLeft.y
                    if height > minHeight {
                        allCandidates.append(contentsOf: candidates)
                    }
                }
            }
            
            // Process each candidate
            return allCandidates.compactMap { processCandidate($0) }
            
        } catch {
            print("Error recognizing text: \(error)")
            return nil
        }
    }
    
    private func processCandidate(_ candidate: String) -> String {
        // 1. Remove spaces and special characters
        let filteredText = candidate.filter { allowedCharacters.contains($0) }
        
        // 2. Apply common character corrections
        let correctedText = applyCharacterCorrections(filteredText)
        
        return correctedText
    }
    
    private func applyCharacterCorrections(_ text: String) -> String {
        var result = text
        
        // Apply character corrections based on context
        // For example, if we detect a pattern like "MH01AB", ensure "0" is not confused with "O"
        if let regex = try? NSRegularExpression(pattern: "([A-Z]{2})([0O][1-9])", options: []) {
            let range = NSRange(location: 0, length: result.utf16.count)
            if let match = regex.firstMatch(in: result, options: [], range: range) {
                if let stateCodeRange = Range(match.range(at: 1), in: result),
                   let numberRange = Range(match.range(at: 2), in: result) {
                    let stateCode = String(result[stateCodeRange])
                    var number = String(result[numberRange])
                    
                    // Ensure the first character of the number is "0" not "O"
                    if number.hasPrefix("O") {
                        number = "0" + number.dropFirst()
                    }
                    
                    let replacement = stateCode + number
                    result = result.replacingOccurrences(of: String(result[stateCodeRange]) + String(result[numberRange]), 
                                                        with: replacement)
                }
            }
        }
        
        return result
    }
    
    private func selectBestResult(from results: [String]) -> String? {
        // Remove duplicates
        let uniqueResults = Array(Set(results))
        if uniqueResults.isEmpty {
            return nil
        }
        
        // Filter by known license plate patterns
        let indianMatches = uniqueResults.filter { matchesPattern(text: $0, pattern: indianPlatePattern) }
        if !indianMatches.isEmpty {
            // Return the longest match if multiple are found
            return indianMatches.max(by: { $0.count < $1.count })
        }
        
        // Try with generic plate patterns
        let genericMatches = uniqueResults.filter { matchesPattern(text: $0, pattern: genericPlatePattern) }
        if !genericMatches.isEmpty {
            return genericMatches.max(by: { $0.count < $1.count })
        }
        
        // If searching full image and no pattern matches, look for any alphanumeric sequence 
        // of appropriate length that could be a license plate
        if region.width == 1 && region.height == 1 {
            // Filter to strings that are likely to be license plates (5-10 alphanumeric chars)
            let validLengthCandidates = uniqueResults.filter { 
                let filtered = $0.filter { $0.isLetter || $0.isNumber }
                return filtered.count >= 5 && filtered.count <= 10 
            }
            
            if !validLengthCandidates.isEmpty {
                // Sort by length and return most promising candidate
                let byLength = validLengthCandidates.sorted { $0.count > $1.count }
                // Prefer strings with a mix of letters and numbers, which is common for license plates
                for candidate in byLength {
                    let hasLetters = candidate.contains { $0.isLetter }
                    let hasNumbers = candidate.contains { $0.isNumber }
                    if hasLetters && hasNumbers {
                        return candidate
                    }
                }
                return byLength.first
            }
        }
        
        // Fallback: return the longest result if nothing else matched
        return uniqueResults.max(by: { $0.count < $1.count })
    }
    
    // Additional preprocessing method for full image scans
    private func applyHighContrastFilters(_ inputImage: CGImage) -> CGImage? {
        // Create CIImage from CGImage
        let ciImage = CIImage(cgImage: inputImage)
        let context = CIContext()
        
        // Apply high contrast filter
        guard let contrastFilter = CIFilter(name: "CIColorControls") else { return nil }
        contrastFilter.setValue(ciImage, forKey: kCIInputImageKey)
        contrastFilter.setValue(2.0, forKey: kCIInputContrastKey) // Very high contrast
        contrastFilter.setValue(0.1, forKey: kCIInputBrightnessKey) // Slightly brighter
        contrastFilter.setValue(0.0, forKey: kCIInputSaturationKey) // No saturation (black and white)
        
        guard let contrastImage = contrastFilter.outputImage else { return nil }
        
        // Convert back to CGImage
        guard let outputCGImage = context.createCGImage(contrastImage, from: contrastImage.extent) else {
            return nil
        }
        
        return outputCGImage
    }
    
    // Helper method to match text against regex pattern
    private func matchesPattern(text: String, pattern: String) -> Bool {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else { 
            return false 
        }
        let range = NSRange(location: 0, length: text.utf16.count)
        return regex.firstMatch(in: text, options: [], range: range) != nil
    }
}
