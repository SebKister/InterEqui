# InterEqui

InterEqui is a Flutter application designed specifically to facilitate interval training and gait logging during horseback riding. It offers an easy-to-use interface for creating customized training plans, provides vocal coaching while riding, and logs accelerometer data for post-ride gait analysis.

## Core Features

- **Training Plans:** Create, edit, and manage custom equestrian interval training plans (e.g., Walk, Trot, Canter intervals).
- **Import/Export Plans:** Share your training plans effortlessly. Export your favorite routines as JSON files and share them or import them on a different device.
- **Audio Coaching:** Integrated Text-to-Speech (TTS) automatically announces the start of new intervals, keeping your eyes on your horse, not your phone.
- **Background Execution:** Training sessions continue to run flawlessly even while the app is in the background or the screen is locked.
- **Gait Logging:** Uses the device's accelerometer to record movement data during intervals (with TensorFlow Lite integration), which can be exported as a gzipped CSV after the workout for analysis.

## Gait Classification Model

InterEqui includes a Jupyter Notebook (`notebooks/train_gait_classifier.ipynb`) used to train the on-device 1D Convolutional Neural Network (CNN) that processes the accelerometer data.

**Notebook Features:**
- **Data Loading & Preprocessing:** Reads the gzipped CSV files (`.csv.gz`) exported by the app, and normalizes 100Hz 3-axis accelerometer data.
- **Model Training:** Trains a TensorFlow CNN to classify three equestrian gaits (Walk, Trot, Canter).
- **On-Device Export:** Automatically quantizes and exports the trained model as a `.tflite` file (`gait_classifier.tflite`) for efficient mobile inference, along with the normalization parameters (`norm_params.json`).

*To train your own model:* export your dataset via the app, upload it to your preferred Jupyter environment (e.g., Google Colab), update the `DATA_DIR` path in the notebook, and run all cells.

## Getting Started

### Prerequisites

- Flutter SDK (>= 3.10.1)
- Dart SDK
- Android Studio / Xcode (for device deployment)

### Installation

1. Clone the repository and navigate to the project folder:
   ```bash
   cd InterEqui
   ```

2. Install dependencies:
   ```bash
   flutter pub get
   ```

3. Run the app on a connected device or emulator:
   ```bash
   flutter run
   ```

## Key Technologies

- **[Flutter Background Service](https://pub.dev/packages/flutter_background_service):** Ensures the interval timer and TTS continue to work uninterrupted when the app runs in the background.
- **[Flutter TTS](https://pub.dev/packages/flutter_tts):** Provides the audio cues during the training session.
- **[Sensors Plus](https://pub.dev/packages/sensors_plus):** Captures device accelerometer data for gait analysis.
- **[TFLite Flutter](https://pub.dev/packages/tflite_flutter):** Enables on-device machine learning capabilities for gait detection inference.

## Permissions Required
The application utilizes a foreground service to ensure uninterrupted timers and sensor data logging during your unlit background sessions. Ensure you grant notification permissions to allow background tracking.

## Note on Background Service Isolate Logs
If you are running the app in debug mode, you might see the following log from `flutter_background_service_android`:
> `flutter_background_service_android` threw an error: Exception: This class should only be used in the main isolate...

This is an expected and **harmless** message generated when Flutter auto-registers plugins in a background isolate. It does not crash your background service or affect functionality.
