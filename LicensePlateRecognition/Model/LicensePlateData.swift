import Foundation

struct LicensePlateData {
    let plateNumber: String
    let timestamp: Date
    
    // Add location if available
    var latitude: Double?
    var longitude: Double?
} 