import 'dart:async';
import 'package:sensors_plus/sensors_plus.dart';
import 'gait_models.dart';
import 'gait_classifier.dart';

/// Streams real-time gait classifications by feeding accelerometer data
/// through a TFLite model in a sliding window.
///
/// If the model files haven't been bundled yet (the user hasn't trained a
/// model), the service starts silently and emits no readings.
class GaitService {
  static const int _sampleRate = 100;
  static const int _stride = 100; // classify every 1 s
  static const int _debounceCount = 2;

  final GaitClassifier _classifier = GaitClassifier();

  StreamSubscription<AccelerometerEvent>? _accelSubscription;
  final List<List<double>> _buffer = [];
  int _samplesSinceLastClassify = 0;

  GaitType _currentGait = GaitType.unknown;
  GaitType _candidateGait = GaitType.unknown;
  int _candidateCount = 0;

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
  bool get isModelLoaded => _classifier.isReady;

  /// Loads the TFLite model from assets. Safe to call more than once.
  Future<void> initialize() async {
    if (!_classifier.isReady) {
      await _classifier.initialize();
    }
  }

  /// Starts the accelerometer and begins classifying.
  ///
  /// Calls [initialize] automatically if the model hasn't been loaded yet.
  Future<void> start() async {
    if (_accelSubscription != null) return;

    await initialize();

    _sessionStart = DateTime.now();
    _lastGaitChangeTime = _sessionStart;
    _currentGait = GaitType.unknown;
    _candidateGait = GaitType.unknown;
    _candidateCount = 0;
    _transitions.clear();
    _gaitDurations.clear();
    _buffer.clear();
    _samplesSinceLastClassify = 0;

    _accelSubscription = accelerometerEventStream(
      samplingPeriod: const Duration(milliseconds: 1000 ~/ _sampleRate),
    ).listen(_onAccelData);
  }

  void _onAccelData(AccelerometerEvent event) {
    _buffer.add([event.x, event.y, event.z]);
    _samplesSinceLastClassify++;

    // Keep buffer bounded to avoid unbounded memory growth.
    final maxLen = GaitClassifier.windowSize * 2;
    if (_buffer.length > maxLen) {
      _buffer.removeRange(0, _buffer.length - maxLen);
    }

    if (_buffer.length >= GaitClassifier.windowSize &&
        _samplesSinceLastClassify >= _stride) {
      _samplesSinceLastClassify = 0;
      _classify();
    }
  }

  void _classify() {
    if (!_classifier.isReady) return;

    final window = _buffer.sublist(
      _buffer.length - GaitClassifier.windowSize,
    );
    final result = _classifier.classify(window);
    if (result == null) return;

    final gaitType = _labelToGaitType(result.label);
    final reading = GaitReading(
      timestamp: DateTime.now(),
      gait: gaitType,
      confidence: result.confidence,
    );

    _gaitController.add(reading);

    // Debounce: require consecutive matching classifications before
    // committing a gait transition.
    if (gaitType == _candidateGait) {
      _candidateCount++;
    } else {
      _candidateGait = gaitType;
      _candidateCount = 1;
    }

    if (_candidateCount >= _debounceCount && _candidateGait != _currentGait) {
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

  static GaitType _labelToGaitType(String label) {
    switch (label) {
      case 'walk':
        return GaitType.walk;
      case 'trot':
        return GaitType.trot;
      case 'canter':
        return GaitType.canter;
      default:
        return GaitType.unknown;
    }
  }

  GaitSession stop() {
    _accelSubscription?.cancel();
    _accelSubscription = null;

    final endTime = DateTime.now();

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
    _accelSubscription?.cancel();
    _gaitController.close();
    _transitionController.close();
    _classifier.dispose();
  }
}
