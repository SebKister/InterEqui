import 'dart:async';
import 'dart:io';
import 'package:sensors_plus/sensors_plus.dart';
import 'package:path_provider/path_provider.dart';

class AccelRecorder {
  static const int _sampleRateMs = 10; // ~100 Hz

  StreamSubscription<AccelerometerEvent>? _subscription;
  final List<String> _csvLines = [];
  String? _currentLabel;
  bool _isRecording = false;
  int _sampleCount = 0;

  bool get isRecording => _isRecording;
  int get sampleCount => _sampleCount;

  void start() {
    if (_isRecording) return;
    _isRecording = true;
    _csvLines.clear();
    _csvLines.add('timestamp_ms,accel_x,accel_y,accel_z,label');
    _sampleCount = 0;

    _subscription = accelerometerEventStream(
      samplingPeriod: const Duration(milliseconds: _sampleRateMs),
    ).listen(_onData);
  }

  void setLabel(String? label) {
    _currentLabel = label;
  }

  void _onData(AccelerometerEvent event) {
    final label = _currentLabel;
    if (label == null) return;

    final timestampMs = DateTime.now().millisecondsSinceEpoch;
    _csvLines.add(
      '$timestampMs,'
      '${event.x.toStringAsFixed(4)},'
      '${event.y.toStringAsFixed(4)},'
      '${event.z.toStringAsFixed(4)},'
      '$label',
    );
    _sampleCount++;
  }

  /// Stops recording and writes CSV to app documents directory.
  /// Returns the File, or null if nothing was recorded.
  Future<File?> stop() async {
    _subscription?.cancel();
    _subscription = null;
    _isRecording = false;
    _currentLabel = null;

    if (_sampleCount == 0) return null;

    final dir = await getApplicationDocumentsDirectory();
    final timestamp = DateTime.now()
        .toIso8601String()
        .replaceAll(':', '-')
        .replaceAll('.', '-');
    final file = File('${dir.path}/gait_data_$timestamp.csv');
    await file.writeAsString(_csvLines.join('\n'));
    _csvLines.clear();
    return file;
  }

  void dispose() {
    _subscription?.cancel();
    _subscription = null;
  }
}
