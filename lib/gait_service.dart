import 'dart:async';
import 'dart:isolate';
import 'dart:math';
import 'dart:typed_data';
import 'package:sensors_plus/sensors_plus.dart';
import 'package:fftea/fftea.dart';
import 'gait_models.dart';

// Must be top-level for Isolate.run
Map<String, dynamic> _classifyGaitIsolate(Map<String, dynamic> params) {
  final buffer = params['buffer'] as Float64List;
  final sampleRate = params['sampleRate'] as int;
  final bufferSize = buffer.length;

  // Apply Hanning window
  final window = Window.hanning(bufferSize);
  final windowed = window.applyWindowReal(buffer);

  // Compute FFT
  final fft = FFT(bufferSize);
  final freq = fft.realFft(windowed);
  final magnitudes = freq.discardConjugates().magnitudes();

  // Compute RMS of the original signal
  double sumSq = 0;
  for (final v in buffer) {
    sumSq += v * v;
  }
  final rms = sqrt(sumSq / bufferSize);

  // Find dominant frequency in equine gait range (0.5-4.0 Hz)
  final freqResolution = sampleRate / bufferSize;
  final minBin = (0.5 / freqResolution).ceil();
  final maxBin = (4.0 / freqResolution).floor().clamp(0, magnitudes.length - 1);

  int peakIndex = minBin;
  double peakMagnitude = 0;
  for (int i = minBin; i <= maxBin; i++) {
    if (magnitudes[i] > peakMagnitude) {
      peakMagnitude = magnitudes[i];
      peakIndex = i;
    }
  }

  final dominantFreq = peakIndex * freqResolution;

  // Classify based on frequency + amplitude
  String gaitName;
  double confidence;

  if (rms < 0.3) {
    gaitName = 'halt';
    confidence = 0.9;
  } else if (dominantFreq >= 0.8 && dominantFreq <= 1.6 && rms < 1.5) {
    gaitName = 'walk';
    confidence = _freqConfidence(dominantFreq, 1.2, 0.4);
  } else if (dominantFreq >= 1.2 && dominantFreq <= 2.0 && rms >= 1.0 && rms < 3.5) {
    gaitName = 'trot';
    confidence = _freqConfidence(dominantFreq, 1.55, 0.4);
  } else if (dominantFreq >= 1.4 && dominantFreq <= 2.8 && rms >= 2.0) {
    gaitName = 'canter';
    confidence = _freqConfidence(dominantFreq, 2.0, 0.6);
  } else {
    gaitName = 'unknown';
    confidence = 0.3;
  }

  return {
    'gait': gaitName,
    'confidence': confidence,
    'dominantFrequency': dominantFreq,
    'amplitude': rms,
  };
}

double _freqConfidence(double freq, double center, double bandwidth) {
  final distance = (freq - center).abs();
  return (1.0 - (distance / bandwidth)).clamp(0.3, 1.0);
}

class GaitService {
  static const int kSampleRate = 100;
  static const int kBufferSize = 256; // power of 2 for FFT
  static const int kOverlapSamples = 128; // 50% overlap
  static const double kHaltThreshold = 0.3;
  static const int kDebounceCount = 2;

  StreamSubscription<AccelerometerEvent>? _accelSubscription;
  final List<double> _accelBuffer = [];

  GaitType _currentGait = GaitType.unknown;
  GaitType _candidateGait = GaitType.unknown;
  int _candidateCount = 0;
  bool _processing = false;
  int _generation = 0; // incremented on stop/dispose to discard stale results
  bool _disposed = false;

  DateTime? _sessionStart;
  final List<GaitTransition> _transitions = [];
  final Map<GaitType, Duration> _gaitDurations = {};
  DateTime? _lastGaitChangeTime;

  final _gaitController = StreamController<GaitReading>.broadcast();
  final _transitionController = StreamController<GaitTransition>.broadcast();

  Stream<GaitReading> get gaitStream => _gaitController.stream;
  Stream<GaitTransition> get transitionStream => _transitionController.stream;
  GaitType get currentGait => _currentGait;
  bool get isRunning => _accelSubscription != null;

  void start() {
    if (_accelSubscription != null) return;

    _sessionStart = DateTime.now();
    _lastGaitChangeTime = _sessionStart;
    _currentGait = GaitType.unknown;
    _candidateGait = GaitType.unknown;
    _candidateCount = 0;
    _transitions.clear();
    _gaitDurations.clear();
    _accelBuffer.clear();
    _processing = false;

    _accelSubscription = accelerometerEventStream(
      samplingPeriod: const Duration(milliseconds: 10), // ~100 Hz
    ).listen(_onAccelData);
  }

  void _onAccelData(AccelerometerEvent event) {
    // Orientation-agnostic: use vector magnitude minus gravity
    final magnitude = sqrt(
      event.x * event.x + event.y * event.y + event.z * event.z,
    ) - 9.81;
    _accelBuffer.add(magnitude);

    // Prevent unbounded growth if processing lags behind sensor rate.
    // Keep only the most recent samples needed for windowed processing.
    final int maxBufferLength = kBufferSize + kOverlapSamples;
    if (_accelBuffer.length > maxBufferLength) {
      final int excess = _accelBuffer.length - maxBufferLength;
      _accelBuffer.removeRange(0, excess);
    }
    if (_accelBuffer.length >= kBufferSize && !_processing) {
      _processBuffer();
    }
  }

  Future<void> _processBuffer() async {
    _processing = true;
    final gen = _generation;
    final bufferCopy = Float64List.fromList(
      _accelBuffer.sublist(0, kBufferSize),
    );
    // Slide window
    _accelBuffer.removeRange(0, kOverlapSamples);

    try {
      final result = await Isolate.run(
        () => _classifyGaitIsolate({
          'buffer': bufferCopy,
          'sampleRate': kSampleRate,
        }),
      );
      // Discard result if stop() or dispose() was called while awaiting
      if (_generation == gen && !_disposed) {
        _applyClassification(result);
      }
    } catch (_) {
      // Isolate failed, skip this window
    } finally {
      _processing = false;
    }
  }

  void _applyClassification(Map<String, dynamic> result) {
    final detectedGait = GaitType.values.byName(result['gait']);
    final reading = GaitReading(
      timestamp: DateTime.now(),
      gait: detectedGait,
      confidence: result['confidence'],
      dominantFrequency: result['dominantFrequency'],
      amplitude: result['amplitude'],
    );

    _gaitController.add(reading);

    // Debounce: require consecutive matching classifications
    if (detectedGait == _candidateGait) {
      _candidateCount++;
    } else {
      _candidateGait = detectedGait;
      _candidateCount = 1;
    }

    if (_candidateCount >= kDebounceCount && _candidateGait != _currentGait) {
      final now = DateTime.now();
      if (_lastGaitChangeTime != null) {
        final elapsed = now.difference(_lastGaitChangeTime!);
        _gaitDurations[_currentGait] =
          (_gaitDurations[_currentGait] ?? Duration.zero) + elapsed;
      }

      final transition = GaitTransition(
        timestamp: now,
        fromGait: _currentGait,
        toGait: _candidateGait,
      );
      _transitions.add(transition);
      _transitionController.add(transition);

      _currentGait = _candidateGait;
      _lastGaitChangeTime = now;
    }
  }

  GaitSession stop() {
    _generation++;
    _accelSubscription?.cancel();
    _accelSubscription = null;

    final endTime = DateTime.now();

    // Record duration of the final gait segment
    if (_lastGaitChangeTime != null) {
      final elapsed = endTime.difference(_lastGaitChangeTime!);
      _gaitDurations[_currentGait] =
        (_gaitDurations[_currentGait] ?? Duration.zero) + elapsed;
    }

    return GaitSession(
      id: DateTime.now().toString(),
      startTime: _sessionStart ?? endTime,
      endTime: endTime,
      transitions: List.from(_transitions),
      gaitDurations: Map.from(_gaitDurations),
    );
  }

  void dispose() {
    _disposed = true;
    _generation++;
    _accelSubscription?.cancel();
    _gaitController.close();
    _transitionController.close();
  }
}
