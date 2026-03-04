import 'dart:convert';
import 'dart:math';
import 'package:flutter/services.dart';
import 'package:tflite_flutter/tflite_flutter.dart';

/// Loads a TFLite gait-classification model and runs inference on
/// fixed-size windows of raw accelerometer data.
class GaitClassifier {
  static const String _modelAsset = 'assets/models/gait_classifier.tflite';
  static const String _paramsAsset = 'assets/models/norm_params.json';

  static const int windowSize = 200; // 2 s at 100 Hz
  static const int numChannels = 4; // x, y, z, magnitude

  static const List<String> labels = ['walk', 'trot', 'canter'];

  Interpreter? _interpreter;
  List<double> _means = [];
  List<double> _stds = [];
  bool _ready = false;

  bool get isReady => _ready;

  /// Attempts to load the model and normalisation params from Flutter assets.
  /// Returns `true` on success, `false` if the files aren't bundled yet.
  Future<bool> initialize() async {
    if (_ready) return true;
    try {
      _interpreter = await Interpreter.fromAsset(_modelAsset);

      final paramStr = await rootBundle.loadString(_paramsAsset);
      final params = json.decode(paramStr) as Map<String, dynamic>;
      _means = List<double>.from(params['means'] as List);
      _stds = List<double>.from(params['stds'] as List);

      _ready = true;
      return true;
    } catch (_) {
      _ready = false;
      return false;
    }
  }

  /// Classify a window of raw accelerometer samples.
  ///
  /// [window] must contain exactly [windowSize] entries, each being `[x, y, z]`.
  /// Returns the predicted label and its softmax confidence, or `null` when the
  /// model hasn't been loaded.
  ({String label, double confidence})? classify(List<List<double>> window) {
    if (!_ready || _interpreter == null) return null;
    if (window.length != windowSize) return null;

    // Z-score normalise each axis, then add magnitude as 4th channel.
    final input = List.generate(windowSize, (t) {
      final nx = (window[t][0] - _means[0]) / _stds[0];
      final ny = (window[t][1] - _means[1]) / _stds[1];
      final nz = (window[t][2] - _means[2]) / _stds[2];
      final mag = sqrt(nx * nx + ny * ny + nz * nz);
      return [nx, ny, nz, mag];
    });

    // Input shape:  [1, windowSize, numChannels]
    // Output shape: [1, labels.length]
    final output = [List<double>.filled(labels.length, 0.0)];
    _interpreter!.run([input], output);

    final probs = output[0];
    int bestIdx = 0;
    for (int i = 1; i < probs.length; i++) {
      if (probs[i] > probs[bestIdx]) bestIdx = i;
    }

    return (label: labels[bestIdx], confidence: probs[bestIdx]);
  }

  void dispose() {
    _interpreter?.close();
    _interpreter = null;
    _ready = false;
  }
}
