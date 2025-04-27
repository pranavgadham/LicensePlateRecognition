import Foundation
import UIKit

class UploadLicensePlateOperation: ConcurrentOperation {
    let plateData: LicensePlateData
    let imageData: Data
    var error: Error?
    
    // Server endpoint
    private let serverEndpoint = "http://172.20.10.3:4000/api/v1/numberplate/upload"
    private let requestTimeout: TimeInterval = 40.0  // 40 second timeout
    
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
    
    init(plateData: LicensePlateData, imageData: Data) {
        self.plateData = plateData
        self.imageData = imageData
    }
    
    override func main() {
        // Set state to executing if not already done by superclass
        if !self.isExecuting && !self.isFinished {
            self.state = .executing
        }
        
        print("Starting upload of license plate: \(plateData.plateNumber)")
        
        // Create the URL request
        guard let url = URL(string: serverEndpoint) else {
            self.error = NSError(domain: "UploadLicensePlateOperation", code: 1, userInfo: [NSLocalizedDescriptionKey: "Invalid server URL"])
            finish()
            return
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = requestTimeout
        
        // Create multipart form data
        let boundary = UUID().uuidString
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        
        var body = Data()
        
        // Add license plate number to form data
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"plateNumber\"\r\n\r\n".data(using: .utf8)!)
        body.append("\(plateData.plateNumber)\r\n".data(using: .utf8)!)
        
        // Add timestamp to form data
        let dateFormatter = ISO8601DateFormatter()
        let timestampString = dateFormatter.string(from: plateData.timestamp)
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"timestamp\"\r\n\r\n".data(using: .utf8)!)
        body.append("\(timestampString)\r\n".data(using: .utf8)!)
        
        // Add coordinates if available
        if let latitude = plateData.latitude, let longitude = plateData.longitude {
            body.append("--\(boundary)\r\n".data(using: .utf8)!)
            body.append("Content-Disposition: form-data; name=\"latitude\"\r\n\r\n".data(using: .utf8)!)
            body.append("\(latitude)\r\n".data(using: .utf8)!)
            
            body.append("--\(boundary)\r\n".data(using: .utf8)!)
            body.append("Content-Disposition: form-data; name=\"longitude\"\r\n\r\n".data(using: .utf8)!)
            body.append("\(longitude)\r\n".data(using: .utf8)!)
        }
        
        // Add image data to form data
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"image\"; filename=\"licensePlate.jpg\"\r\n".data(using: .utf8)!)
        body.append("Content-Type: image/jpeg\r\n\r\n".data(using: .utf8)!)
        body.append(imageData)
        body.append("\r\n".data(using: .utf8)!)
        
        // End the form data
        body.append("--\(boundary)--\r\n".data(using: .utf8)!)
        
        request.httpBody = body
        
        // Create the upload task
        let task = URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
            guard let self = self else { return }
            
            if let error = error {
                print("Upload error: \(error.localizedDescription)")
                self.error = error
                self.finish()
                return
            }
            
            // Check response status code
            if let httpResponse = response as? HTTPURLResponse {
                print("Upload response status: \(httpResponse.statusCode)")
                
                if httpResponse.statusCode < 200 || httpResponse.statusCode >= 300 {
                    // Error in server response
                    let errorMessage = data.flatMap { String(data: $0, encoding: .utf8) } ?? "Unknown server error"
                    self.error = NSError(domain: "UploadLicensePlateOperation", 
                                        code: httpResponse.statusCode, 
                                        userInfo: [NSLocalizedDescriptionKey: errorMessage])
                }
            }
            
            // Operation is complete
            self.finish()
        }
        
        // Start the upload task
        task.resume()
    }
}

// MARK: - Data Extension
extension Data {
    mutating func append(_ string: String) {
        if let data = string.data(using: .utf8) {
            append(data)
        }
    }
} 