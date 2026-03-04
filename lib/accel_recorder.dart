import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:sensors_plus/sensors_plus.dart';
import 'package:path_provider/path_provider.dart';

/// Top-level function suitable for use with [compute].
/// Joins [lines] into a CSV string and returns gzip-compressed bytes.
List<int> _compressCsvLines(List<String> lines) {
  final csvContent = lines.join('\n');
  return gzip.encode(utf8.encode(csvContent));
}

class AccelRecorder {
  static const int _sampleRateMs = 10; // ~100 Hz

  StreamSubscription<AccelerometerEvent>? _subscription;
  IOSink? _sink;
  File? _tempFile;
  String? _currentLabel;
  bool _isRecording = false;
  int _sampleCount = 0;

  bool get isRecording => _isRecording;
  int get sampleCount => _sampleCount;

  /// Opens a temporary CSV file and begins streaming samples to it.
  Future<void> start() async {
    if (_isRecording) return;
    _isRecording = true;
    _sampleCount = 0;
    _currentLabel = null;

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
    _sink?.write(
      '$timestampMs,'
      '${event.x.toStringAsFixed(4)},'
      '${event.y.toStringAsFixed(4)},'
      '${event.z.toStringAsFixed(4)},'
      '$label\n',
    );
    _sampleCount++;
  }

  /// Stops recording and writes a compressed CSV to app documents directory.
  /// Returns the File, or null if nothing was recorded.
  Future<File?> stop() async {
    _subscription?.cancel();
    _subscription = null;
    _isRecording = false;
    _currentLabel = null;

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
<<<<<<< copilot/sub-pr-4
    final compressed = gzip.encode(await tempFile!.readAsBytes());
    await tempFile.delete();
=======
    final linesToCompress = List<String>.from(_csvLines);
    _csvLines.clear();
    final compressed = await compute(_compressCsvLines, linesToCompress);
>>>>>>> claude/elegant-sammet
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
