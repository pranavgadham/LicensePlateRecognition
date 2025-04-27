//
//  LicensePlateConfirmationViewController.swift
//  LicensePlateRecognition
//

import UIKit
import Vision
import CoreLocation
import MLKitTextRecognition
import MLKitVision

class LicensePlateConfirmationViewController: UIViewController {
    
    // MARK: - Properties
    private var capturedImage: UIImage
    private var recognizedText: String?
    private var location: CLLocation?
    private var plateRect: CGRect? // Keep plate rect for recognition only
    private let serverEndpoint = "http://172.20.10.3:4000/api/v1/numberplate/upload"
    
    // Add dismissal handler
    var dismissalHandler: (() -> Void)?
    
    // MARK: - UI Elements
    private lazy var imageView: UIImageView = {
        let view = UIImageView()
        view.translatesAutoresizingMaskIntoConstraints = false
        view.contentMode = .scaleAspectFit
        view.clipsToBounds = true
        view.layer.cornerRadius = 8
        return view
    }()
    
    private lazy var plateNumberLabel: UILabel = {
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.font = .systemFont(ofSize: 17, weight: .semibold)
        label.text = "License Plate Number"
        return label
    }()
    
    private lazy var plateNumberField: UITextField = {
        let field = UITextField()
        field.translatesAutoresizingMaskIntoConstraints = false
        field.borderStyle = .roundedRect
        field.font = .systemFont(ofSize: 17)
        return field
    }()
    
    private lazy var dateLabel: UILabel = {
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.font = .systemFont(ofSize: 17, weight: .semibold)
        label.text = "Date"
        return label
    }()
    
    private lazy var dateField: UITextField = {
        let field = UITextField()
        field.translatesAutoresizingMaskIntoConstraints = false
        field.borderStyle = .roundedRect
        field.font = .systemFont(ofSize: 17)
        let date = Date()
        let formatter = DateFormatter()
        formatter.dateFormat = "dd-MM-yyyy"
        field.text = formatter.string(from: date)
        return field
    }()
    
    private lazy var locationLabel: UILabel = {
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.font = .systemFont(ofSize: 17, weight: .semibold)
        label.text = "Location"
        return label
    }()
    
    private lazy var locationField: UITextField = {
        let field = UITextField()
        field.translatesAutoresizingMaskIntoConstraints = false
        field.borderStyle = .roundedRect
        field.font = .systemFont(ofSize: 17)
        field.text = "Bengaluru" // Default location, can be updated with actual location
        return field
    }()
    
    private lazy var saveButton: UIButton = {
        let button = UIButton(type: .system)
        button.translatesAutoresizingMaskIntoConstraints = false
        button.setTitle("Save", for: .normal)
        button.backgroundColor = .systemBlue
        button.setTitleColor(.white, for: .normal)
        button.layer.cornerRadius = 20
        button.addTarget(self, action: #selector(saveButtonTapped), for: .touchUpInside)
        return button
    }()
    
    private lazy var cancelButton: UIButton = {
        let button = UIButton(type: .system)
        button.translatesAutoresizingMaskIntoConstraints = false
        button.setTitle("Cancel", for: .normal)
        button.backgroundColor = .systemGray4
        button.setTitleColor(.black, for: .normal)
        button.layer.cornerRadius = 20
        button.addTarget(self, action: #selector(cancelButtonTapped), for: .touchUpInside)
        return button
    }()
    
    // Add loading indicator
    private lazy var loadingIndicator: UIActivityIndicatorView = {
        let indicator = UIActivityIndicatorView(style: .large)
        indicator.translatesAutoresizingMaskIntoConstraints = false
        indicator.hidesWhenStopped = true
        return indicator
    }()
    
    // MARK: - Initialization
    init(image: UIImage, recognizedText: String?, location: CLLocation?, plateRect: CGRect?) {
        self.capturedImage = image
        self.recognizedText = recognizedText
        self.location = location
        self.plateRect = plateRect
        super.init(nibName: nil, bundle: nil)
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    // MARK: - Lifecycle
    override func viewDidLoad() {
        super.viewDidLoad()
        setupUI()
        configureWithData()
        performTextRecognition()
    }
    
    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        
        // Call dismissal handler when view is about to disappear
        if isMovingFromParent || isBeingDismissed {
            dismissalHandler?()
        }
    }
    
    // MARK: - Public Methods
    
    func updateRecognizedText(_ text: String?) {
        if let text = text {
            plateNumberField.text = text
        }
    }
    
    // MARK: - Private Methods
    private func setupUI() {
        view.backgroundColor = .systemBackground
        
        view.addSubview(imageView)
        view.addSubview(plateNumberLabel)
        view.addSubview(plateNumberField)
        view.addSubview(dateLabel)
        view.addSubview(dateField)
        view.addSubview(locationLabel)
        view.addSubview(locationField)
        view.addSubview(saveButton)
        view.addSubview(cancelButton)
        view.addSubview(loadingIndicator)  // Add loading indicator
        
        NSLayoutConstraint.activate([
            imageView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 20),
            imageView.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
            imageView.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20),
            imageView.heightAnchor.constraint(equalTo: view.heightAnchor, multiplier: 0.3),
            
            plateNumberLabel.topAnchor.constraint(equalTo: imageView.bottomAnchor, constant: 20),
            plateNumberLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
            plateNumberLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20),
            
            plateNumberField.topAnchor.constraint(equalTo: plateNumberLabel.bottomAnchor, constant: 8),
            plateNumberField.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
            plateNumberField.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20),
            
            dateLabel.topAnchor.constraint(equalTo: plateNumberField.bottomAnchor, constant: 20),
            dateLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
            dateLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20),
            
            dateField.topAnchor.constraint(equalTo: dateLabel.bottomAnchor, constant: 8),
            dateField.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
            dateField.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20),
            
            locationLabel.topAnchor.constraint(equalTo: dateField.bottomAnchor, constant: 20),
            locationLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
            locationLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20),
            
            locationField.topAnchor.constraint(equalTo: locationLabel.bottomAnchor, constant: 8),
            locationField.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
            locationField.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20),
            
            saveButton.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -20),
            saveButton.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
            saveButton.widthAnchor.constraint(equalToConstant: 120),
            saveButton.heightAnchor.constraint(equalToConstant: 40),
            
            cancelButton.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -20),
            cancelButton.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20),
            cancelButton.widthAnchor.constraint(equalToConstant: 120),
            cancelButton.heightAnchor.constraint(equalToConstant: 40),
            
            loadingIndicator.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            loadingIndicator.centerYAnchor.constraint(equalTo: view.centerYAnchor)
        ])
    }
    
    private func configureWithData() {
        imageView.image = capturedImage
        plateNumberField.text = recognizedText
        
        if let location = location {
            // Reverse geocode location to get city name
            let geocoder = CLGeocoder()
            geocoder.reverseGeocodeLocation(location) { [weak self] placemarks, error in
                if let city = placemarks?.first?.locality {
                    DispatchQueue.main.async {
                        self?.locationField.text = city
                    }
                }
            }
        }
    }
    
    @objc private func saveButtonTapped() {
        guard let plateNumber = plateNumberField.text, !plateNumber.isEmpty else {
            showAlert(title: "Error", message: "Please enter a license plate number")
            return
        }
        
        // Remove dismissal handler call from here and let it be called after upload
        uploadPlateData()
    }
    
    @objc private func cancelButtonTapped() {
        // Call dismissal handler after dismiss animation completes
        dismiss(animated: true) { [weak self] in
            self?.dismissalHandler?()
        }
    }
    
    private func uploadPlateData() {
        guard let imageData = capturedImage.jpegData(compressionQuality: 0.8) else {
            print("Error: Failed to process image data")
            showAlert(title: "Error", message: "Failed to process image")
            return
        }
        
        // Create URL request
        guard let url = URL(string: serverEndpoint) else {
            print("Error: Invalid server URL")
            showAlert(title: "Error", message: "Invalid server URL")
            return
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        
        // Set longer timeout for free hosting
        request.timeoutInterval = 60 // 60 seconds timeout
        
        // Create form data
        let boundary = UUID().uuidString
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        
        var body = Data()
        
        // Format date in ISO8601 format with timezone
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "dd-MM-yyyy"
        let currentDate = Date()
        
        // Convert the date string to Date object if it exists, otherwise use current date
        let dateToUse: Date
        if let dateString = dateField.text,
           let parsedDate = dateFormatter.date(from: dateString) {
            // Create a new date with the parsed date's components but current time
            let calendar = Calendar.current
            let dateComponents = calendar.dateComponents([.year, .month, .day], from: parsedDate)
            let timeComponents = calendar.dateComponents([.hour, .minute, .second], from: currentDate)
            var components = DateComponents()
            components.year = dateComponents.year
            components.month = dateComponents.month
            components.day = dateComponents.day
            components.hour = timeComponents.hour
            components.minute = timeComponents.minute
            components.second = timeComponents.second
            dateToUse = calendar.date(from: components) ?? currentDate
        } else {
            dateToUse = currentDate
        }
        
        // Format date in ISO8601 format with timezone
        let isoDateFormatter = ISO8601DateFormatter()
        isoDateFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds, .withTimeZone]
        let isoDateString = isoDateFormatter.string(from: dateToUse)
        
        // Format location string
        let locationString: String
        if let location = location {
            locationString = "lat: \(location.coordinate.latitude) long: \(location.coordinate.longitude)"
        } else {
            locationString = locationField.text ?? "Unknown"
        }
        
        // Add regNumber field
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"regNumber\"\r\n\r\n".data(using: .utf8)!)
        body.append("\(plateNumberField.text ?? "")\r\n".data(using: .utf8)!)
        
        // Add date field with ISO8601 format
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"date\"\r\n\r\n".data(using: .utf8)!)
        body.append("\(isoDateString)\r\n".data(using: .utf8)!)
        
        // Add location field with formatted string
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"location\"\r\n\r\n".data(using: .utf8)!)
        body.append("\(locationString)\r\n".data(using: .utf8)!)
        
        // Add image data
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"numberplate\"; filename=\"plate.jpg\"\r\n".data(using: .utf8)!)
        body.append("Content-Type: image/jpeg\r\n\r\n".data(using: .utf8)!)
        body.append(imageData)
        body.append("\r\n".data(using: .utf8)!)
        
        // End of form data
        body.append("--\(boundary)--\r\n".data(using: .utf8)!)
        
        request.httpBody = body
        
        // Show loading indicator
        loadingIndicator.startAnimating()
        saveButton.isEnabled = false
        cancelButton.isEnabled = false
        
        // Create and start data task
        let task = URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
            DispatchQueue.main.async {
                // Hide loading indicator
                self?.loadingIndicator.stopAnimating()
                self?.saveButton.isEnabled = true
                self?.cancelButton.isEnabled = true
                
                if let error = error {
                    print("Network error: \(error.localizedDescription)")
                    self?.showAlert(title: "Error", message: "Network error: \(error.localizedDescription)")
                    return
                }
                
                guard let data = data else {
                    print("Error: No data received from server")
                    self?.showAlert(title: "Error", message: "No data received from server")
                    return
                }
                
                // Try to parse response
                do {
                    let json = try JSONSerialization.jsonObject(with: data, options: []) as? [String: Any]
                    
                    if let success = json?["success"] as? Bool,
                       let message = json?["message"] as? String {
                        
                        if success {
                            // Show success alert and dismiss after user taps OK
                            self?.showAlert(title: "Success", message: message) { [weak self] _ in
                                // Dismiss the view controller and call dismissal handler after alert is dismissed
                                self?.dismiss(animated: true) {
                                    self?.dismissalHandler?()
                                }
                            }
                        } else {
                            print("Upload failed: \(message)")
                            // Show error alert with server message
                            self?.showAlert(title: "Upload Failed", message: message)
                        }
                    } else {
                        print("Error: Invalid response format from server")
                        // Invalid response format
                        self?.showAlert(title: "Error", message: "Invalid response format from server")
                    }
                } catch {
                    print("Error parsing server response: \(error.localizedDescription)")
                    self?.showAlert(title: "Error", message: "Failed to parse server response. Please try again.")
                }
            }
        }
        
        task.resume()
    }
    
    private func showAlert(title: String, message: String, completion: ((UIAlertAction) -> Void)? = nil) {
        let alert = UIAlertController(title: title, message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "OK", style: .default, handler: completion))
        present(alert, animated: true)
    }
    
    // MARK: - Text Recognition
    private func performTextRecognition() {
        // Always display and process the full image
        imageView.image = capturedImage
        
        // Create text recognizer
        let textRecognizer = TextRecognizer.textRecognizer()
        
        // Create VisionImage from full image
        let visionImage = VisionImage(image: capturedImage)
        visionImage.orientation = capturedImage.imageOrientation
        
        // Process the full image
        textRecognizer.process(visionImage) { [weak self] result, error in
            guard let self = self else { return }
            
            if let error = error {
                print("Text recognition error: \(error.localizedDescription)")
                self.updateRecognizedText("Error recognizing text")
                return
            }
            
            guard let result = result else {
                print("Error: No text recognition result")
                self.updateRecognizedText("No text recognized")
                return
            }
            
            // Regular expression pattern for license plate
            // Pattern for Indian license plates: [A-Z]{2}\s?\d{1,2}\s?[A-Z]{1,3}\s?\d{4}
            let platePattern = try? NSRegularExpression(pattern: "[A-Z]{2}\\s?\\d{1,2}\\s?[A-Z]{1,3}\\s?\\d{4}", options: [])
            
            var detectedPlates: [String] = []
            
            // Check each text block for license plate pattern
            for block in result.blocks {
                let text = block.text
                
                if let matches = platePattern?.matches(in: text, options: [], range: NSRange(text.startIndex..., in: text)) {
                    for match in matches {
                        if let range = Range(match.range, in: text) {
                            let plate = String(text[range])
                            if !detectedPlates.contains(plate) {
                                detectedPlates.append(plate)
                            }
                        }
                    }
                }
            }
            
            // Update UI on main thread
            DispatchQueue.main.async {
                if detectedPlates.isEmpty {
                    self.updateRecognizedText("No valid license plate detected")
                } else {
                    // Use the first detected plate
                    self.updateRecognizedText(detectedPlates[0])
                }
            }
        }
    }
} 
