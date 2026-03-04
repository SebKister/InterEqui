import 'dart:async';
import 'package:flutter/material.dart';
import 'gait_models.dart';
import 'gait_service.dart';

class GaitDetectorScreen extends StatefulWidget {
  const GaitDetectorScreen({super.key});

  @override
  State<GaitDetectorScreen> createState() => _GaitDetectorScreenState();
}

class _GaitDetectorScreenState extends State<GaitDetectorScreen> {
  final GaitService _gaitService = GaitService();
  StreamSubscription<GaitReading>? _readingSubscription;

  bool _isRecording = false;
  bool? _modelAvailable; // null = still loading
  GaitReading? _latestReading;
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
    });

    _readingSubscription = _gaitService.gaitStream.listen((reading) {
      if (mounted) {
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
                  const Icon(Icons.model_training, size: 48, color: Colors.grey),
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
                        .map((r) => Expanded(
                              child: Container(color: gaitColor(r.gait)),
                            ))
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
              padding: const EdgeInsets.symmetric(
                horizontal: 32,
                vertical: 16,
              ),
              textStyle: const TextStyle(fontSize: 18),
            ),
          ),
        ],
      ),
    );
  }
}

class GaitSessionSummaryScreen extends StatelessWidget {
  final GaitSession session;
  const GaitSessionSummaryScreen({super.key, required this.session});

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

  @override
  Widget build(BuildContext context) {
    final totalMs = session.totalDuration.inMilliseconds;

    // Filter to gaits that actually have duration
    final gaitEntries = session.gaitDurations.entries
        .where((e) => e.value.inMilliseconds > 0)
        .toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    return Scaffold(
      appBar: AppBar(title: const Text('Session Summary')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Total duration
          Center(
            child: Text(
              'Total: ${_formatDuration(session.totalDuration)}',
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

          if (session.transitions.isNotEmpty) ...[
            const Divider(height: 32),
            Text(
              'Transitions',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            ...session.transitions.map((t) {
              final offset = t.timestamp.difference(session.startTime);
              return ListTile(
                dense: true,
                leading: Text(
                  _formatTimestamp(offset),
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    fontFamily: 'monospace',
                  ),
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
              onPressed: () => Navigator.pop(context),
              child: const Text('Done'),
            ),
          ),
          const SizedBox(height: 16),
        ],
      ),
    );
  }
}
