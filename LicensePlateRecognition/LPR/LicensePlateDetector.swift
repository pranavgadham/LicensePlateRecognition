import TensorFlowLite
import UIKit
import CoreGraphics

class LicensePlateDetector {

    private var interpreter: Interpreter?
    
    // Model constants
    private let inputWidth = 300
    private let inputHeight = 300
    private let inputChannels = 3
    private let batchSize = 1
    
    // Output tensor indices
    private let outputBoxesIndex = 0
    private let outputScoresIndex = 1
    private let outputClassesIndex = 2
    private let outputCountIndex = 3
    
    // Detection parameters
    private let scoreThreshold: Float = 0.5
    
    init() {
        // Load the TFLite model
        guard let modelPath = Bundle.main.path(forResource: "detect_plate", ofType: "tflite") else {
            print("Failed to load model")
            return
        }
        
        do {
            interpreter = try Interpreter(modelPath: modelPath)
            try interpreter?.allocateTensors()
        } catch {
            print("Failed to create interpreter: \(error)")
        }
    }
    
    func detect(image: UIImage) -> [CGRect] {
        // Preprocess image to match model input requirements
        guard let inputData = preprocessImage(image) else { return [] }
        
        // Run inference
        do {
            try interpreter?.copy(inputData, toInputAt: 0)
            try interpreter?.invoke()
            
            // Get output tensors
            guard let outputBoxes = try interpreter?.output(at: outputBoxesIndex),
                  let outputScores = try interpreter?.output(at: outputScoresIndex),
                  let outputClasses = try interpreter?.output(at: outputClassesIndex),
                  let outputCount = try interpreter?.output(at: outputCountIndex) else {
                return []
            }
            
            return processDetections(boxes: outputBoxes, scores: outputScores, 
                                     classes: outputClasses, count: outputCount, 
                                     imageSize: image.size)
        } catch {
            print("Failed to run inference: \(error)")
            return []
        }
    }
    
    private func preprocessImage(_ image: UIImage) -> Data? {
        guard let cgImage = image.cgImage else { return nil }
        
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue)
        guard let context = CGContext(data: nil, width: inputWidth, height: inputHeight,
                                     bitsPerComponent: 8, bytesPerRow: inputWidth * inputChannels,
                                     space: colorSpace, bitmapInfo: bitmapInfo.rawValue) else {
            return nil
        }
        
        // Draw image to resize and convert to RGB format
        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: inputWidth, height: inputHeight))
        
        guard let imageData = context.data else { return nil }
        
        // Prepare input tensor data (1x300x300x3 uint8 tensor)
        let byteCount = batchSize * inputHeight * inputWidth * inputChannels
        var inputData = Data(count: byteCount)
        
        inputData.withUnsafeMutableBytes { inputBytes in
            guard let inputBaseAddress = inputBytes.baseAddress else { return }
            let inputPointer = inputBaseAddress.assumingMemoryBound(to: UInt8.self)
            
            // Copy image data to input tensor
            let imageBaseAddress = imageData.assumingMemoryBound(to: UInt8.self)
            for i in 0..<(inputHeight * inputWidth) {
                // RGBA to RGB conversion
                let imageOffset = i * 4 // 4 bytes per pixel (RGBA)
                let inputOffset = i * 3 // 3 bytes per pixel (RGB)
                
                // Copy RGB values (skip alpha)
                inputPointer[inputOffset] = imageBaseAddress[imageOffset]
                inputPointer[inputOffset + 1] = imageBaseAddress[imageOffset + 1]
                inputPointer[inputOffset + 2] = imageBaseAddress[imageOffset + 2]
            }
        }
        
        return inputData
    }
    
    private func processDetections(boxes: Tensor, scores: Tensor, classes: Tensor, count: Tensor, imageSize: CGSize) -> [CGRect] {
        // Get detection count
        let detectionCount = count.data.withUnsafeBytes { pointer in
            return min(Int(pointer.load(as: Float.self)), 10) // Limit to 10 detections
        }
        
        var licensePlateBoxes: [CGRect] = []
        
        // Process each detection
        for i in 0..<detectionCount {
            // Get score for this detection
            let scoreOffset = i * MemoryLayout<Float>.size
            let score = scores.data.withUnsafeBytes { pointer in
                return pointer.load(fromByteOffset: scoreOffset, as: Float.self)
            }
            
            // Get class for this detection
            let classOffset = i * MemoryLayout<Float>.size
            let classId = classes.data.withUnsafeBytes { pointer in
                return pointer.load(fromByteOffset: classOffset, as: Float.self)
            }
            
            // Only consider license plate detections (class 1) with high confidence
            if score >= scoreThreshold && Int(classId) == 1 {
                // Get bounding box coordinates [y1, x1, y2, x2] (normalized 0-1)
                let boxOffset = i * 4 * MemoryLayout<Float>.size
                
                let y1 = boxes.data.withUnsafeBytes { pointer in
                    return pointer.load(fromByteOffset: boxOffset, as: Float.self)
                }
                let x1 = boxes.data.withUnsafeBytes { pointer in
                    return pointer.load(fromByteOffset: boxOffset + MemoryLayout<Float>.size, as: Float.self)
                }
                let y2 = boxes.data.withUnsafeBytes { pointer in
                    return pointer.load(fromByteOffset: boxOffset + 2 * MemoryLayout<Float>.size, as: Float.self)
                }
                let x2 = boxes.data.withUnsafeBytes { pointer in
                    return pointer.load(fromByteOffset: boxOffset + 3 * MemoryLayout<Float>.size, as: Float.self)
                }
                
                // Convert normalized coordinates to image coordinates
                let rect = CGRect(
                    x: CGFloat(x1) * imageSize.width,
                    y: CGFloat(y1) * imageSize.height,
                    width: (CGFloat(x2) - CGFloat(x1)) * imageSize.width,
                    height: (CGFloat(y2) - CGFloat(y1)) * imageSize.height
                )
                
                licensePlateBoxes.append(rect)
            }
        }
        
        return licensePlateBoxes
    }
}