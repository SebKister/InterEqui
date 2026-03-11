import 'dart:async';
import 'dart:io';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'gait_models.dart';
import 'gait_service.dart';
import 'models.dart';
import 'history_screen.dart';

class GaitDetectorScreen extends StatefulWidget {
  const GaitDetectorScreen({super.key});

  @override
  State<GaitDetectorScreen> createState() => _GaitDetectorScreenState();
}

class _GaitDetectorScreenState extends State<GaitDetectorScreen> {
  final GaitService _gaitService = GaitService();
  final FlutterTts _tts = FlutterTts();
  StreamSubscription<GaitReading>? _readingSubscription;

  bool _isRecording = false;
  bool? _modelAvailable; // null = still loading
  GaitReading? _latestReading;
  GaitType? _lastAnnouncedGait;
  final List<GaitReading> _recentReadings = [];
  static const int _maxRecentReadings = 30;
  DateTime? _recordingStart;

  Timer? _elapsedTimer;
  Duration _elapsed = Duration.zero;

  @override
  void initState() {
    super.initState();
    _checkModel();
  }

  Future<void> _checkModel() async {
    await _gaitService.initialize();
    if (mounted) {
      setState(() => _modelAvailable = _gaitService.isModelLoaded);
    }
  }

  Future<void> _startRecording() async {
    if (_isRecording) return;

    await _gaitService.start();
    _recordingStart = DateTime.now();
    setState(() {
      _isRecording = true;
      _latestReading = null;
      _recentReadings.clear();
      _elapsed = Duration.zero;
      _lastAnnouncedGait = null;
    });

    _readingSubscription = _gaitService.gaitStream.listen((reading) {
      if (mounted) {
        if (reading.gait != _lastAnnouncedGait &&
            reading.gait != GaitType.unknown) {
          _lastAnnouncedGait = reading.gait;
          _tts.speak(gaitLabel(reading.gait));
        }
        setState(() {
          _latestReading = reading;
          _recentReadings.add(reading);
          if (_recentReadings.length > _maxRecentReadings) {
            _recentReadings.removeAt(0);
          }
        });
      }
    });

    _elapsedTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted && _recordingStart != null) {
        setState(() {
          _elapsed = DateTime.now().difference(_recordingStart!);
        });
      }
    });
  }

  void _stopRecording() {
    final session = _gaitService.stop();
    _readingSubscription?.cancel();
    _readingSubscription = null;
    _elapsedTimer?.cancel();
    _elapsedTimer = null;

    final record = WorkoutRecord(
      id: session.id,
      title: 'Gait Session',
      timestamp: session.startTime,
      duration: session.totalDuration,
      type: 'gait',
      planJson: json.encode(session.toJson()),
    );
    HistoryScreen.saveWorkoutRecord(record);

    Navigator.pushReplacement(
      context,
      MaterialPageRoute(
        builder: (context) => GaitSessionSummaryScreen(session: session),
      ),
    );
  }

  Future<bool> _confirmStop() async {
    if (!_isRecording) return true;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Stop Recording?'),
        content: const Text('Stop the gait detection session?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Continue'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Stop', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      _stopRecording();
    }
    return false; // we handle navigation in _stopRecording
  }

  String _formatElapsed(Duration d) {
    final h = d.inHours;
    final m = d.inMinutes % 60;
    final s = d.inSeconds % 60;
    if (h > 0) {
      return '${h.toString().padLeft(2, '0')}:${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
    }
    return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }

  @override
  void dispose() {
    _readingSubscription?.cancel();
    _elapsedTimer?.cancel();
    _tts.stop();
    if (_gaitService.isRunning) {
      _gaitService.stop();
    }
    _gaitService.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: !_isRecording,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _confirmStop();
      },
      child: Scaffold(
        appBar: AppBar(title: const Text('Gait Detector')),
        body: _isRecording ? _buildRecordingView() : _buildStartView(),
      ),
    );
  }

  Widget _buildStartView() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.sensors,
            size: 80,
            color: Theme.of(context).colorScheme.primary,
          ),
          const SizedBox(height: 24),
          Text(
            'Gait Detector',
            style: Theme.of(context).textTheme.headlineMedium,
          ),
          const SizedBox(height: 16),
          if (_modelAvailable == null)
            const Padding(
              padding: EdgeInsets.all(32),
              child: CircularProgressIndicator(),
            )
          else if (_modelAvailable == false)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 32),
              child: Column(
                children: [
                  const Icon(
                    Icons.model_training,
                    size: 48,
                    color: Colors.grey,
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'No model available yet',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Record training data during workouts, then run '
                    'the training notebook to generate a model.\n\n'
                    'Place gait_classifier.tflite and norm_params.json '
                    'in assets/models/ and rebuild.',
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            )
          else ...[
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 32),
              child: Text(
                'Place your phone in your pocket or on your belt, '
                'then tap Start to begin detecting the horse\'s gait.',
                textAlign: TextAlign.center,
              ),
            ),
            const SizedBox(height: 40),
            FilledButton.icon(
              onPressed: _startRecording,
              icon: const Icon(Icons.play_arrow),
              label: const Text('Start'),
              style: FilledButton.styleFrom(
                padding: const EdgeInsets.symmetric(
                  horizontal: 32,
                  vertical: 16,
                ),
                textStyle: const TextStyle(fontSize: 18),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildRecordingView() {
    final reading = _latestReading;
    final gait = reading?.gait ?? GaitType.unknown;
    final color = gaitColor(gait);

    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(gaitIcon(gait), size: 80, color: color),
          const SizedBox(height: 16),
          Text(
            gaitLabel(gait),
            style: Theme.of(context).textTheme.displayMedium?.copyWith(
              color: color,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 12),
          if (reading != null) ...[
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 48),
              child: LinearProgressIndicator(
                value: reading.confidence,
                color: color,
                backgroundColor: color.withValues(alpha: 0.2),
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Confidence: ${(reading.confidence * 100).toStringAsFixed(0)}%',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
          const SizedBox(height: 24),
          if (_recentReadings.isNotEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: SizedBox(
                  height: 24,
                  child: Row(
                    children: _recentReadings
                        .map(
                          (r) => Expanded(
                            child: Container(color: gaitColor(r.gait)),
                          ),
                        )
                        .toList(),
                  ),
                ),
              ),
            ),
          const SizedBox(height: 24),
          Text(
            _formatElapsed(_elapsed),
            style: Theme.of(context).textTheme.headlineLarge,
          ),
          const SizedBox(height: 40),
          FilledButton.icon(
            onPressed: _stopRecording,
            icon: const Icon(Icons.stop),
            label: const Text('Stop'),
            style: FilledButton.styleFrom(
              backgroundColor: Colors.red,
              padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
              textStyle: const TextStyle(fontSize: 18),
            ),
          ),
        ],
      ),
    );
  }
}

class GaitSessionSummaryScreen extends StatefulWidget {
  final GaitSession session;
  const GaitSessionSummaryScreen({super.key, required this.session});

  @override
  State<GaitSessionSummaryScreen> createState() => _GaitSessionSummaryScreenState();
}

class _GaitSessionSummaryScreenState extends State<GaitSessionSummaryScreen> {
  bool _sessionExported = false;

  String _formatDuration(Duration d) {
    final m = d.inMinutes;
    final s = d.inSeconds % 60;
    return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }

  String _formatTimestamp(Duration offset) {
    final m = offset.inMinutes;
    final s = offset.inSeconds % 60;
    return '+${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }

  Future<void> _exportSession(BuildContext context) async {
    _sessionExported = true;
    final totalMs = widget.session.totalDuration.inMilliseconds;

    // Header
    final date = widget.session.startTime;
    final dateStr =
        '${date.day.toString().padLeft(2, '0')}/'
        '${date.month.toString().padLeft(2, '0')}/'
        '${date.year} '
        '${date.hour.toString().padLeft(2, '0')}:'
        '${date.minute.toString().padLeft(2, '0')}';
    final buf = StringBuffer()
      ..writeln('Gait Session — $dateStr')
      ..writeln('Duration: ${_formatDuration(widget.session.totalDuration)}')
      ..writeln();

    // Gait breakdown
    final sorted =
        widget.session.gaitDurations.entries
            .where((e) => e.value.inMilliseconds > 0)
            .toList()
          ..sort((a, b) => b.value.compareTo(a.value));

    buf.writeln('Gait Breakdown:');
    for (final e in sorted) {
      final pct = totalMs > 0
          ? (e.value.inMilliseconds / totalMs * 100).toStringAsFixed(1)
          : '0.0';
      buf.writeln(
        '  ${gaitLabel(e.key).padRight(10)}'
        '${_formatDuration(e.value)}  ($pct%)',
      );
    }
    buf.writeln();

    // Transitions
    if (widget.session.transitions.isNotEmpty) {
      buf.writeln('Transitions (${widget.session.transitions.length}):');
      for (final t in widget.session.transitions) {
        final offset = t.timestamp.difference(widget.session.startTime);
        buf.writeln(
          '  ${_formatTimestamp(offset)}  '
          '${gaitLabel(t.fromGait)} → ${gaitLabel(t.toGait)}',
        );
      }
    }

    // Write file and share
    final dir = await getApplicationDocumentsDirectory();
    final ts = widget.session.startTime
        .toIso8601String()
        .replaceAll(':', '-')
        .replaceAll('.', '-');
    final file = File('${dir.path}/gait_session_$ts.txt');
    await file.writeAsString(buf.toString());
    await Share.shareXFiles([
      XFile(file.path),
    ], subject: 'Gait Session $dateStr');
  }

  @override
  Widget build(BuildContext context) {
    final totalMs = widget.session.totalDuration.inMilliseconds;

    // Filter to gaits that actually have duration
    final gaitEntries =
        widget.session.gaitDurations.entries
            .where((e) => e.value.inMilliseconds > 0)
            .toList()
          ..sort((a, b) => b.value.compareTo(a.value));

    return Scaffold(
      appBar: AppBar(
        title: const Text('Session Summary'),
        actions: [
          IconButton(
            icon: const Icon(Icons.share),
            tooltip: 'Export session',
            onPressed: () => _exportSession(context),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Total duration
          Center(
            child: Text(
              'Total: ${_formatDuration(widget.session.totalDuration)}',
              style: Theme.of(context).textTheme.headlineSmall,
            ),
          ),
          const SizedBox(height: 16),

          // Stacked gait bar
          if (totalMs > 0 && gaitEntries.isNotEmpty)
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: SizedBox(
                height: 40,
                child: Row(
                  children: gaitEntries.map((e) {
                    final fraction = e.value.inMilliseconds / totalMs;
                    return Expanded(
                      flex: (fraction * 1000).round().clamp(1, 1000),
                      child: Container(
                        color: gaitColor(e.key),
                        alignment: Alignment.center,
                        child: fraction > 0.1
                            ? Text(
                                gaitLabel(e.key),
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 12,
                                  fontWeight: FontWeight.bold,
                                ),
                              )
                            : null,
                      ),
                    );
                  }).toList(),
                ),
              ),
            ),
          const SizedBox(height: 16),

          // Gait duration breakdown
          ...gaitEntries.map((e) {
            final pct = totalMs > 0
                ? (e.value.inMilliseconds / totalMs * 100).toStringAsFixed(0)
                : '0';
            return ListTile(
              leading: Icon(gaitIcon(e.key), color: gaitColor(e.key)),
              title: Text(gaitLabel(e.key)),
              trailing: Text(
                '${_formatDuration(e.value)}  ($pct%)',
                style: TextStyle(
                  color: gaitColor(e.key),
                  fontWeight: FontWeight.bold,
                ),
              ),
            );
          }),

          if (widget.session.transitions.isNotEmpty) ...[
            const Divider(height: 32),
            Text('Transitions', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            ...widget.session.transitions.map((t) {
              final offset = t.timestamp.difference(widget.session.startTime);
              return ListTile(
                dense: true,
                leading: Text(
                  _formatTimestamp(offset),
                  style: Theme.of(
                    context,
                  ).textTheme.bodyMedium?.copyWith(fontFamily: 'monospace'),
                ),
                title: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      gaitLabel(t.fromGait),
                      style: TextStyle(color: gaitColor(t.fromGait)),
                    ),
                    const Padding(
                      padding: EdgeInsets.symmetric(horizontal: 8),
                      child: Icon(Icons.arrow_forward, size: 16),
                    ),
                    Text(
                      gaitLabel(t.toGait),
                      style: TextStyle(color: gaitColor(t.toGait)),
                    ),
                  ],
                ),
              );
            }),
          ],

          const SizedBox(height: 24),
          Center(
            child: FilledButton(
              onPressed: () async {
                if (!_sessionExported) {
                  final confirm = await showDialog<bool>(
                    context: context,
                    builder: (context) => AlertDialog(
                      title: const Text('Discard session data?'),
                      content: const Text(
                        'You haven\'t exported the session data yet. The session will still be saved to your history, but if you want to export the text summary, you should do it now.\n\nAre you sure you want to close this screen?',
                      ),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.pop(context, false),
                          child: const Text('Cancel'),
                        ),
                        TextButton(
                          onPressed: () => Navigator.pop(context, true),
                          child: const Text('Close', style: TextStyle(color: Colors.red)),
                        ),
                      ],
                    ),
                  );
                  if (confirm != true) return;
                }
                if (mounted) Navigator.pop(context);
              },
              child: const Text('Done'),
            ),
          ),
          const SizedBox(height: 16),
        ],
      ),
    );
  }
}
