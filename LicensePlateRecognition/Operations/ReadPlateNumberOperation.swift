import UIKit

class ReadPlateNumberOperation: ConcurrentOperation {
    
    let region: CGRect
    let completion: (String?) -> Void
    let capturePhotoOperation = CapturePhotoOperation()
    
    private var recognizeTextOperation: RecognizeTextOperation?
    
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
    
    init(region: CGRect, completion: @escaping (String?) -> Void) {
        self.region = region
        self.completion = completion
    }
    
    override func main() {
        // Set state to executing if not already done by superclass
        if !self.isExecuting && !self.isFinished {
            self.state = .executing
        }
        
        defer {
            finish()
            completion(recognizeTextOperation?.recognizedText)
        }
        
        OperationQueue.current?.addOperations([capturePhotoOperation], waitUntilFinished: true)
        
        guard let image = capturePhotoOperation.cgImage else { return }
        
        recognizeTextOperation = RecognizeTextOperation(cgImage: image, region: region)
        OperationQueue.current?.addOperations([recognizeTextOperation!], waitUntilFinished: true)
    }
}
