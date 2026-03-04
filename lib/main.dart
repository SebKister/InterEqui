import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:share_plus/share_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'package:file_picker/file_picker.dart';
import 'models.dart';
import 'background_service.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'gait_models.dart';
import 'gait_service.dart';
import 'gait_screen.dart';
import 'accel_recorder.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initializeService();
  runApp(const IntervallerApp());
}

class IntervallerApp extends StatelessWidget {
  const IntervallerApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'InterEqui',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepOrange),
        useMaterial3: true,
      ),
      home: const PlanListScreen(),
    );
  }
}

class PlanListScreen extends StatefulWidget {
  const PlanListScreen({super.key});

  @override
  State<PlanListScreen> createState() => _PlanListScreenState();
}

class _PlanListScreenState extends State<PlanListScreen> {
  List<TrainingPlan> _plans = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadPlans();
  }

  Future<void> _loadPlans() async {
    final prefs = await SharedPreferences.getInstance();
    final String? plansJson = prefs.getString('training_plans');
    if (plansJson != null) {
      final List<dynamic> decoded = json.decode(plansJson);
      setState(() {
        _plans = decoded.map((item) => TrainingPlan.fromJson(item)).toList();
        _isLoading = false;
      });
    } else {
      setState(() {
        _plans = [
          TrainingPlan(
            id: '1',
            name: 'HIIT Basic',
            intervals: [
              TrainingInterval(
                name: 'Warm up',
                duration: const Duration(seconds: 10),
              ),
              TrainingInterval(
                name: 'Sprint',
                duration: const Duration(seconds: 20),
              ),
              TrainingInterval(
                name: 'Rest',
                duration: const Duration(seconds: 10),
              ),
              TrainingInterval(
                name: 'Sprint',
                duration: const Duration(seconds: 20),
              ),
              TrainingInterval(
                name: 'Cool down',
                duration: const Duration(seconds: 10),
              ),
            ],
          ),
        ];
        _isLoading = false;
      });
      _savePlans();
    }
  }

  Future<void> _savePlans() async {
    final prefs = await SharedPreferences.getInstance();
    final String encoded = json.encode(_plans.map((p) => p.toJson()).toList());
    await prefs.setString('training_plans', encoded);
  }

  void _addPlan() async {
    final newPlan = await Navigator.push<TrainingPlan>(
      context,
      MaterialPageRoute(builder: (context) => const PlanEditorScreen()),
    );
    if (newPlan != null) {
      setState(() {
        _plans.add(newPlan);
      });
      _savePlans();
    }
  }

  void _editPlan(int index) async {
    final updated = await Navigator.push<TrainingPlan>(
      context,
      MaterialPageRoute(
        builder: (context) => PlanEditorScreen(plan: _plans[index]),
      ),
    );
    if (updated != null) {
      setState(() {
        _plans[index] = updated;
      });
      _savePlans();
    }
  }

  Future<void> _exportPlan(TrainingPlan plan) async {
    final dir = await getApplicationDocumentsDirectory();
    final safeName = plan.name.replaceAll(RegExp(r'[^\w\s-]'), '').replaceAll(' ', '_');
    final baseName = safeName.isNotEmpty
        ? safeName
        : 'plan_${DateTime.now().millisecondsSinceEpoch}';
    final file = File('${dir.path}/$baseName.json');
    final jsonStr = const JsonEncoder.withIndent('  ').convert(plan.toJson());
    await file.writeAsString(jsonStr);
    await Share.shareXFiles(
      [XFile(file.path)],
      subject: plan.name,
    );
  }

  Future<void> _importPlan() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.any,
    );
    if (result == null || result.files.isEmpty) return;

    final filePath = result.files.single.path;
    if (filePath == null) return;

    try {
      final content = await File(filePath).readAsString();
      final decoded = json.decode(content);
      final plan = TrainingPlan.fromJson(decoded);
      // Give it a fresh id to avoid collisions
      final imported = TrainingPlan(
        id: DateTime.now().microsecondsSinceEpoch.toString(),
        name: plan.name,
        intervals: plan.intervals,
      );
      setState(() {
        _plans.add(imported);
      });
      _savePlans();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Imported "${imported.name}"')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Failed to import plan. Invalid file format.')),
        );
      }
    }
  }

  Future<void> _confirmDelete(int index) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Plan?'),
        content: Text(
          'Are you sure you want to delete "${_plans[index].name}"?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      setState(() {
        _plans.removeAt(index);
      });
      _savePlans();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('My Training Plans'),
        actions: [
          IconButton(
            icon: const Icon(Icons.file_open),
            tooltip: 'Import Plan',
            onPressed: _importPlan,
          ),
          IconButton(
            icon: const Icon(Icons.sensors),
            tooltip: 'Gait Detector',
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (context) => const GaitDetectorScreen()),
              );
            },
          ),
          IconButton(
            icon: const Icon(Icons.settings),
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (context) => const SettingsScreen()),
              );
            },
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : ListView.builder(
              itemCount: _plans.length,
              itemBuilder: (context, index) {
                final plan = _plans[index];
                return ListTile(
                  title: Text(plan.name),
                  subtitle: Text('${plan.intervals.length} intervals'),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        icon: const Icon(Icons.share_outlined),
                        tooltip: 'Export Plan',
                        onPressed: () => _exportPlan(plan),
                      ),
                      IconButton(
                        icon: const Icon(Icons.edit_outlined),
                        onPressed: () => _editPlan(index),
                      ),
                      IconButton(
                        icon: const Icon(Icons.delete_outline),
                        onPressed: () => _confirmDelete(index),
                      ),
                      const Icon(Icons.play_arrow),
                    ],
                  ),
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => TrainingScreen(plan: plan),
                      ),
                    );
                  },
                );
              },
            ),
      floatingActionButton: FloatingActionButton(
        onPressed: _addPlan,
        child: const Icon(Icons.add),
      ),
    );
  }
}

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final FlutterTts _flutterTts = FlutterTts();
  List<dynamic> _voices = [];
  String? _selectedVoiceName;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _initTts();
  }

  Future<void> _initTts() async {
    final voices = await _flutterTts.getVoices;
    final prefs = await SharedPreferences.getInstance();
    final savedVoice = prefs.getString('tts_voice_name');

    setState(() {
      _voices = voices;
      _selectedVoiceName = savedVoice;
      _isLoading = false;
    });
  }

  Future<void> _setVoice(Map<String, String> voice) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('tts_voice_name', voice['name']!);
    await prefs.setString('tts_voice_locale', voice['locale']!);
    setState(() {
      _selectedVoiceName = voice['name'];
    });
    await _flutterTts.setVoice(voice);
    await _flutterTts.speak("This is an example of the selected voice.");
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : ListView.builder(
              itemCount: _voices.length,
              itemBuilder: (context, index) {
                final voice = Map<String, String>.from(_voices[index]);
                final name = voice['name'] ?? 'Unknown';
                final locale = voice['locale'] ?? 'Unknown';
                return RadioListTile<String>(
                  title: Text(name),
                  subtitle: Text(locale),
                  value: name,
                  groupValue: _selectedVoiceName,
                  onChanged: (value) {
                    if (value != null) _setVoice(voice);
                  },
                );
              },
            ),
    );
  }
}

class PlanEditorScreen extends StatefulWidget {
  final TrainingPlan? plan;
  const PlanEditorScreen({super.key, this.plan});

  @override
  State<PlanEditorScreen> createState() => _PlanEditorScreenState();
}

class _PlanEditorScreenState extends State<PlanEditorScreen> {
  late final TextEditingController _nameController;
  late final List<TrainingInterval> _intervals;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.plan?.name ?? '');
    _intervals = widget.plan?.intervals.toList() ?? [];
  }

  void _showIntervalDialog({int? editIndex}) {
    final existing = editIndex != null ? _intervals[editIndex] : null;
    final nameController = TextEditingController(
      text: existing?.name ?? 'Interval',
    );
    final minController = TextEditingController(
      text: existing != null ? existing.duration.inMinutes.toString() : '0',
    );
    final secController = TextEditingController(
      text: existing != null
          ? (existing.duration.inSeconds % 60).toString()
          : '0',
    );

    final List<String> shortcuts = ["Trot", "Walk", "Canter", "Left", "Right"];

    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text(editIndex != null ? 'Edit Interval' : 'Add Interval'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextField(
                  controller: nameController,
                  decoration: const InputDecoration(labelText: 'Activity Name'),
                ),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 8.0,
                  children: shortcuts.map((shortcutName) {
                    return ActionChip(
                      label: Text(shortcutName),
                      onPressed: () {
                        if (shortcutName == "Left" || shortcutName == "Right") {
                          if (nameController.text == 'Interval' ||
                              nameController.text.trim().isEmpty) {
                            nameController.text = shortcutName;
                          } else {
                            nameController.text =
                                '${nameController.text.trim()} $shortcutName';
                          }
                        } else {
                          nameController.text = shortcutName;
                        }
                      },
                    );
                  }).toList(),
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: minController,
                        decoration: const InputDecoration(labelText: 'Minutes'),
                        keyboardType: TextInputType.number,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: TextField(
                        controller: secController,
                        decoration: const InputDecoration(labelText: 'Seconds'),
                        keyboardType: TextInputType.number,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () {
                int minutes = int.tryParse(minController.text) ?? 0;
                int seconds = int.tryParse(secController.text) ?? 0;
                int totalSeconds = (minutes * 60) + seconds;
                if (totalSeconds <= 0) return;

                final interval = TrainingInterval(
                  name: nameController.text.isNotEmpty
                      ? nameController.text
                      : 'Interval',
                  duration: Duration(seconds: totalSeconds),
                );
                setState(() {
                  if (editIndex != null) {
                    _intervals[editIndex] = interval;
                  } else {
                    _intervals.add(interval);
                  }
                });
                Navigator.pop(context);
              },
              child: Text(editIndex != null ? 'Save' : 'Add'),
            ),
          ],
        );
      },
    );
  }

  String _formatDuration(int totalSeconds) {
    final minutes = (totalSeconds / 60).floor();
    final seconds = totalSeconds % 60;
    return '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final isEditing = widget.plan != null;
    return Scaffold(
      appBar: AppBar(
        title: Text(isEditing ? 'Edit Plan' : 'Create Plan'),
        actions: [
          IconButton(
            icon: const Icon(Icons.save),
            onPressed: () {
              if (_nameController.text.isNotEmpty && _intervals.isNotEmpty) {
                Navigator.pop(
                  context,
                  TrainingPlan(
                    id: widget.plan?.id ?? DateTime.now().toString(),
                    name: _nameController.text,
                    intervals: _intervals,
                  ),
                );
              }
            },
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            TextField(
              controller: _nameController,
              decoration: const InputDecoration(labelText: 'Plan Name'),
            ),
            const SizedBox(height: 20),
            Expanded(
              child: ListView.builder(
                itemCount: _intervals.length,
                itemBuilder: (context, index) {
                  final interval = _intervals[index];
                  return ListTile(
                    title: Text(interval.name),
                    subtitle: Text(_formatDuration(interval.duration.inSeconds)),
                    trailing: IconButton(
                      icon: const Icon(Icons.delete),
                      onPressed: () {
                        setState(() => _intervals.removeAt(index));
                      },
                    ),
                    onTap: () => _showIntervalDialog(editIndex: index),
                  );
                },
              ),
            ),
            ElevatedButton(
              onPressed: () => _showIntervalDialog(),
              child: const Text('Add Interval'),
            ),
          ],
        ),
      ),
    );
  }
}

class TrainingScreen extends StatefulWidget {
  final TrainingPlan plan;
  const TrainingScreen({super.key, required this.plan});

  @override
  State<TrainingScreen> createState() => _TrainingScreenState();
}

class _TrainingScreenState extends State<TrainingScreen> {
  int _currentIntervalIndex = 0;
  int _secondsRemaining = 0;
  bool _isPaused = false;
  StreamSubscription? _serviceSubscription;
  Timer? _localTimer;

  final GaitService _gaitService = GaitService();
  StreamSubscription<GaitReading>? _gaitSubscription;
  GaitReading? _latestGaitReading;

  final AccelRecorder _accelRecorder = AccelRecorder();

  @override
  void initState() {
    super.initState();
    _secondsRemaining = widget.plan.intervals[0].duration.inSeconds;
    _startBackgroundWorkout();
    _startGaitDetection();
    _startDataRecording();
  }

  void _startDataRecording() {
    _accelRecorder.start();
    _updateRecordingLabel(0);
  }

  void _updateRecordingLabel(int intervalIndex) {
    final intervalName = widget.plan.intervals[intervalIndex].name;
    _accelRecorder.setLabel(gaitLabelFromIntervalName(intervalName));
  }

  void _startGaitDetection() {
    _gaitService.start();
    _gaitSubscription = _gaitService.gaitStream.listen((reading) {
      if (mounted) {
        setState(() => _latestGaitReading = reading);
      }
    });
  }

  // Local timer drives the countdown directly so the UI never depends solely
  // on background service IPC. Background service 'update' events resync it
  // when they arrive (keeping TTS/notification state authoritative).
  void _startLocalTimer() {
    _localTimer?.cancel();
    _localTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!_isPaused && mounted) {
        if (_secondsRemaining > 0) {
          setState(() {
            _secondsRemaining--;
          });
        } else if (_currentIntervalIndex < widget.plan.intervals.length - 1) {
          setState(() {
            _currentIntervalIndex++;
            _secondsRemaining =
                widget.plan.intervals[_currentIntervalIndex].duration.inSeconds;
          });
          _updateRecordingLabel(_currentIntervalIndex);
        } else {
          _localTimer?.cancel();
          _showCompletionDialog(); // async — must not be inside setState
        }
      }
    });
  }

  void _startBackgroundWorkout() async {
    final service = FlutterBackgroundService();
    bool isRunning = await service.isRunning();

    // Subscribe to events BEFORE invoking startWorkout so we don't miss anything.
    // When updates arrive they resync the local timer with the background state.
    _serviceSubscription = service.on('update').listen((event) {
      if (mounted) {
        final newIndex = event!['index'] as int;
        if (newIndex != _currentIntervalIndex) {
          _updateRecordingLabel(newIndex);
        }
        setState(() {
          _currentIntervalIndex = newIndex;
          _secondsRemaining = event['seconds'];
          _isPaused = event['isPaused'];
        });
        _startLocalTimer();
      }
    });

    service.on('complete').listen((event) {
      if (mounted) {
        _localTimer?.cancel();
        _showCompletionDialog();
      }
    });

    if (!isRunning) {
      final readyFuture = service.on('ready').first;
      await service.startService();
      await readyFuture.timeout(
        const Duration(seconds: 5),
        onTimeout: () => null,
      );
    }

    service.invoke('startWorkout', {"plan": widget.plan.toJson()});
    _startLocalTimer();
  }

  void _skipInterval() {
    if (_currentIntervalIndex < widget.plan.intervals.length - 1) {
      setState(() {
        _currentIntervalIndex++;
        _secondsRemaining =
            widget.plan.intervals[_currentIntervalIndex].duration.inSeconds;
      });
      _updateRecordingLabel(_currentIntervalIndex);
      _startLocalTimer();
    }
    FlutterBackgroundService().invoke('skip');
  }

  void _togglePause() {
    final wasPaused = _isPaused;
    setState(() => _isPaused = !_isPaused);
    FlutterBackgroundService().invoke('pauseResume');
    if (!wasPaused) {
      _accelRecorder.setLabel(null);
    } else {
      _updateRecordingLabel(_currentIntervalIndex);
    }
  }

  Future<bool> _confirmStop() async {
    setState(() => _isPaused = true);
    _accelRecorder.setLabel(null);
    final confirmed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: const Text('Stop Workout?'),
        content: const Text(
          'Are you sure you want to stop this training session?',
        ),
        actions: [
          TextButton(
            onPressed: () {
              setState(() => _isPaused = false);
              _updateRecordingLabel(_currentIntervalIndex);
              Navigator.pop(context, false);
            },
            child: const Text('Resume'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Stop', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      _localTimer?.cancel();
      FlutterBackgroundService().invoke('stopService');
      final file = await _accelRecorder.stop();
      if (mounted && file != null) {
        _showExportDialog(file);
        return false; // export dialog handles navigation
      }
    }
    return confirmed ?? false;
  }

  Future<void> _showCompletionDialog() async {
    final file = await _accelRecorder.stop();
    if (!mounted) return;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: const Text('Workout Complete!'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('Great job!'),
            if (file != null) ...[
              const SizedBox(height: 16),
              Row(
                children: [
                  const Icon(Icons.check_circle, color: Colors.green, size: 20),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      '${_accelRecorder.sampleCount} accelerometer samples recorded',
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
        actions: [
          if (file != null)
            TextButton.icon(
              onPressed: () {
                Share.shareXFiles([XFile(file.path)]);
              },
              icon: const Icon(Icons.share),
              label: const Text('Export gzipped CSV'),
            ),
          TextButton(
            onPressed: () {
              Navigator.pop(context); // Pop dialog
              Navigator.pop(context); // Pop training screen
            },
            child: const Text('Done'),
          ),
        ],
      ),
    );
  }

  void _showExportDialog(File file) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: const Text('Data Recorded'),
        content: Text(
          '${_accelRecorder.sampleCount} accelerometer samples were recorded.',
        ),
        actions: [
          TextButton.icon(
            onPressed: () {
              Share.shareXFiles([XFile(file.path)]);
            },
            icon: const Icon(Icons.share),
            label: const Text('Export CSV'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context); // Pop dialog
              Navigator.pop(context); // Pop training screen
            },
            child: const Text('Done'),
          ),
        ],
      ),
    );
  }

  String _formatDuration(int totalSeconds) {
    final minutes = (totalSeconds / 60).floor();
    final seconds = totalSeconds % 60;
    return '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
  }

  @override
  void dispose() {
    _serviceSubscription?.cancel();
    _localTimer?.cancel();
    _gaitSubscription?.cancel();
    if (_gaitService.isRunning) {
      _gaitService.stop();
    }
    _gaitService.dispose();
    _accelRecorder.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final currentInterval = widget.plan.intervals[_currentIntervalIndex];
    return WillPopScope(
      onWillPop: _confirmStop,
      child: Scaffold(
        appBar: AppBar(title: Text(widget.plan.name)),
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                currentInterval.name,
                style: Theme.of(context).textTheme.displayMedium,
              ),
              const SizedBox(height: 20),
              Text(
                _formatDuration(_secondsRemaining),
                style: Theme.of(context).textTheme.displayLarge?.copyWith(
                  fontSize: 100,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 40),
              Text(
                'Next: ${_currentIntervalIndex < widget.plan.intervals.length - 1 ? widget.plan.intervals[_currentIntervalIndex + 1].name : "Finish"}',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 16),
              if (_latestGaitReading != null)
                Chip(
                  avatar: Icon(
                    gaitIcon(_latestGaitReading!.gait),
                    color: gaitColor(_latestGaitReading!.gait),
                    size: 18,
                  ),
                  label: Text(
                    gaitLabel(_latestGaitReading!.gait),
                    style: TextStyle(color: gaitColor(_latestGaitReading!.gait)),
                  ),
                ),
              if (_accelRecorder.isRecording) ...[
                const SizedBox(height: 8),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.fiber_manual_record,
                      color: gaitLabelFromIntervalName(currentInterval.name) != null
                          ? Colors.red
                          : Colors.grey,
                      size: 12,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      gaitLabelFromIntervalName(currentInterval.name) != null
                          ? 'Recording: ${gaitLabelFromIntervalName(currentInterval.name)}'
                          : 'Recording paused',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: gaitLabelFromIntervalName(currentInterval.name) != null
                            ? Colors.red
                            : Colors.grey,
                      ),
                    ),
                  ],
                ),
              ],
              const SizedBox(height: 24),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  ElevatedButton(
                    onPressed: _togglePause,
                    child: Text(_isPaused ? 'Resume' : 'Pause'),
                  ),
                  const SizedBox(width: 20),
                  ElevatedButton(
                    onPressed: _skipInterval,
                    child: const Text('Skip'),
                  ),
                  const SizedBox(width: 20),
                  ElevatedButton(
                    onPressed: () async {
                      if (await _confirmStop()) {
                        if (mounted) Navigator.pop(context);
                      }
                    },
                    child: const Text('Stop'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
