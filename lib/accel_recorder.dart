import 'dart:async';
import 'dart:io';
import 'package:sensors_plus/sensors_plus.dart';
import 'dart:collection';
import 'package:path_provider/path_provider.dart';

class _AccelSample {
  final int timestampMs;
  final String line;
  _AccelSample(this.timestampMs, this.line);
}

class AccelRecorder {
  static const int _sampleRateMs = 10; // ~100 Hz

  StreamSubscription<AccelerometerEvent>? _subscription;
  IOSink? _sink;
  File? _tempFile;
  String? _currentLabel;
  bool _isRecording = false;
  int _sampleCount = 0;

  Duration _ignoreLast = Duration.zero;
  final Queue<_AccelSample> _buffer = Queue<_AccelSample>();

  bool get isRecording => _isRecording;
  int get sampleCount => _sampleCount;

  /// Opens a temporary CSV file and begins streaming samples to it.
  Future<void> start({Duration ignoreLast = Duration.zero}) async {
    if (_isRecording) return;
    _isRecording = true;
    _sampleCount = 0;
    _currentLabel = null;
    _ignoreLast = ignoreLast;
    _buffer.clear();

    final dir = await getTemporaryDirectory();
    final ts = DateTime.now().millisecondsSinceEpoch;
    _tempFile = File('${dir.path}/accel_$ts.csv');
    _sink = _tempFile!.openWrite();
    _sink!.write('timestamp_ms,accel_x,accel_y,accel_z,label\n');

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
    final line =
        '$timestampMs,'
        '${event.x.toStringAsFixed(4)},'
        '${event.y.toStringAsFixed(4)},'
        '${event.z.toStringAsFixed(4)},'
        '$label\n';

    if (_ignoreLast > Duration.zero) {
      _buffer.addLast(_AccelSample(timestampMs, line));
      final cutoff = timestampMs - _ignoreLast.inMilliseconds;
      while (_buffer.isNotEmpty && _buffer.first.timestampMs < cutoff) {
        _sink?.write(_buffer.removeFirst().line);
        _sampleCount++;
      }
    } else {
      _sink?.write(line);
      _sampleCount++;
    }
  }

  /// Stops recording and writes a compressed CSV to app documents directory.
  /// Returns the File, or null if nothing was recorded.
  Future<File?> stop() async {
    _subscription?.cancel();
    _subscription = null;
    _isRecording = false;
    _currentLabel = null;
    _buffer.clear();

    if (_sink != null) {
      await _sink!.flush();
      await _sink!.close();
      _sink = null;
    }

    final tempFile = _tempFile;
    _tempFile = null;

    if (_sampleCount == 0) {
      await tempFile?.delete();
      return null;
    }

    final dir = await getApplicationDocumentsDirectory();
    final timestamp = DateTime.now()
        .toIso8601String()
        .replaceAll(':', '-')
        .replaceAll('.', '-');
    final compressed = gzip.encode(await tempFile!.readAsBytes());
    await tempFile.delete();
    final file = File('${dir.path}/gait_data_$timestamp.csv.gz');
    await file.writeAsBytes(compressed);
    return file;
  }

  void dispose() {
    _subscription?.cancel();
    _subscription = null;
    // Fire-and-forget: dispose() is synchronous; any buffered bytes are
    // flushed by the underlying IOSink as it closes.
    _sink?.close();
    _sink = null;
  }
}
