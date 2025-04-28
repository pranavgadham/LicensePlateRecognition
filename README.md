# License Plate Recognition (iOS)

An iOS application for detecting and recognizing license plates in real-time using Apple's CoreML and Vision frameworks.

## 📱 Features

- Real-time license plate detection using a custom-trained CoreML object detection model.
- Optical Character Recognition (OCR) on captured license plates via Vision framework's `VNRecognizeTextRequest`.
- Thread-safe model management using Dispatch Queues.
- Supports both landscape and portrait orientations.

![Demo GIF](path/to/demo.gif)

## 🛠 Technology Stack

- Swift
- CoreML (for object detection)
- Vision (for OCR)
- AVFoundation (for real-time camera capture)
- CreateML (for model training)
- Xcode 13+ (recommended)

## 📦 Project Structure

- `LicensePlateRecognition/` – Main app source code.
- `LicensePlateRecognitionTests/` – Unit tests.
- `LicensePlateRecognition.xcodeproj` – Xcode project.
- `LicensePlateRecognition.xcworkspace` – Xcode workspace (for CocoaPods).

## 🔧 Installation

1. Clone the repository:
   ```bash
   git clone https://github.com/pranavgadham/LicensePlateRecognition.git
   cd LicensePlateRecognition
   ```

2. Install dependencies (if using CocoaPods):
   ```bash
   pod install
   ```

3. Open the `.xcworkspace` file:
   ```bash
   open LicensePlateRecognition.xcworkspace
   ```

4. Build and run the project on a physical device (camera usage is required).

## 📈 Future Improvements

- Improve accuracy with a larger, more diverse training dataset.
- Add local database storage for recognized plate numbers.
- Implement whitelist/blacklist verification of detected plates.
- Enhance UI/UX for easier plate tracking and management.
