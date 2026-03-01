import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'models.dart';

void main() {
  runApp(const IntervallerApp());
}

class IntervallerApp extends StatelessWidget {
  const IntervallerApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Intervaller',
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
    final updatedPlan = await Navigator.push<TrainingPlan>(
      context,
      MaterialPageRoute(
        builder: (context) => PlanEditorScreen(existingPlan: _plans[index]),
      ),
    );
    if (updatedPlan != null) {
      setState(() {
        _plans[index] = updatedPlan;
      });
      _savePlans();
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

  void _viewPlan(int index) async {
    final updatedPlan = await Navigator.push<TrainingPlan>(
      context,
      MaterialPageRoute(
        builder: (context) => PlanDetailScreen(plan: _plans[index]),
      ),
    );
    if (updatedPlan != null) {
      setState(() {
        _plans[index] = updatedPlan;
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
                        icon: const Icon(Icons.edit_outlined),
                        tooltip: 'Edit',
                        onPressed: () => _editPlan(index),
                      ),
                      IconButton(
                        icon: const Icon(Icons.delete_outline),
                        tooltip: 'Delete',
                        onPressed: () => _confirmDelete(index),
                      ),
                      IconButton(
                        icon: const Icon(Icons.play_arrow),
                        tooltip: 'Start',
                        onPressed: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (context) =>
                                  TrainingScreen(plan: plan),
                            ),
                          );
                        },
                      ),
                    ],
                  ),
                  onTap: () => _viewPlan(index),
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

class PlanDetailScreen extends StatelessWidget {
  final TrainingPlan plan;

  const PlanDetailScreen({super.key, required this.plan});

  String _formatDuration(int totalSeconds) {
    final minutes = (totalSeconds / 60).floor();
    final seconds = totalSeconds % 60;
    return '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(plan.name),
        actions: [
          IconButton(
            icon: const Icon(Icons.edit),
            tooltip: 'Edit plan',
            onPressed: () async {
              final updatedPlan = await Navigator.push<TrainingPlan>(
                context,
                MaterialPageRoute(
                  builder: (context) => PlanEditorScreen(existingPlan: plan),
                ),
              );
              if (updatedPlan != null && context.mounted) {
                Navigator.pop(context, updatedPlan);
              }
            },
          ),
        ],
      ),
      body: ListView.builder(
        padding: const EdgeInsets.symmetric(vertical: 8),
        itemCount: plan.intervals.length,
        itemBuilder: (context, index) {
          final interval = plan.intervals[index];
          return ListTile(
            leading: CircleAvatar(child: Text('${index + 1}')),
            title: Text(interval.name),
            subtitle: Text(_formatDuration(interval.duration.inSeconds)),
          );
        },
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => TrainingScreen(plan: plan),
            ),
          );
        },
        icon: const Icon(Icons.play_arrow),
        label: const Text('Start Workout'),
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
  final TrainingPlan? existingPlan;

  const PlanEditorScreen({super.key, this.existingPlan});

  @override
  State<PlanEditorScreen> createState() => _PlanEditorScreenState();
}

class _PlanEditorScreenState extends State<PlanEditorScreen> {
  late final TextEditingController _nameController;
  late List<TrainingInterval> _intervals;

  @override
  void initState() {
    super.initState();
    _nameController =
        TextEditingController(text: widget.existingPlan?.name ?? '');
    _intervals = widget.existingPlan?.intervals.toList() ?? [];
  }

  void _showIntervalDialog({int? editIndex}) {
    final existing = editIndex != null ? _intervals[editIndex] : null;
    final nameController =
        TextEditingController(text: existing?.name ?? 'Interval');
    final existingSeconds = existing?.duration.inSeconds ?? 30;
    final minController =
        TextEditingController(text: '${existingSeconds ~/ 60}');
    final secController =
        TextEditingController(text: '${existingSeconds % 60}');

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
                  decoration:
                      const InputDecoration(labelText: 'Activity Name'),
                ),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 8.0,
                  children: shortcuts.map((shortcutName) {
                    return ActionChip(
                      label: Text(shortcutName),
                      onPressed: () {
                        if (shortcutName == "Left" ||
                            shortcutName == "Right") {
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
                        decoration:
                            const InputDecoration(labelText: 'Minutes'),
                        keyboardType: TextInputType.number,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: TextField(
                        controller: secController,
                        decoration:
                            const InputDecoration(labelText: 'Seconds'),
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
                if (totalSeconds <= 0) totalSeconds = 30;

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
    return Scaffold(
      appBar: AppBar(
        title:
            Text(widget.existingPlan != null ? 'Edit Plan' : 'Create Plan'),
        actions: [
          IconButton(
            icon: const Icon(Icons.save),
            onPressed: () {
              if (_nameController.text.isNotEmpty && _intervals.isNotEmpty) {
                Navigator.pop(
                  context,
                  TrainingPlan(
                    id: widget.existingPlan?.id ?? DateTime.now().toString(),
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
                    subtitle: Text(
                      _formatDuration(interval.duration.inSeconds),
                    ),
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
  late int _secondsRemaining;
  Timer? _timer;
  bool _isPaused = false;
  final FlutterTts _flutterTts = FlutterTts();

  @override
  void initState() {
    super.initState();
    _secondsRemaining = widget.plan.intervals[0].duration.inSeconds;
    _initTtsAndStart();
  }

  Future<void> _initTtsAndStart() async {
    final prefs = await SharedPreferences.getInstance();
    final name = prefs.getString('tts_voice_name');
    final locale = prefs.getString('tts_voice_locale');
    if (name != null && locale != null) {
      await _flutterTts.setVoice({"name": name, "locale": locale});
    }
    _speakCurrentInterval();
    _startTimer();
  }

  Future<void> _speakCurrentInterval() async {
    final interval = widget.plan.intervals[_currentIntervalIndex];
    final duration = interval.duration;

    String durationText = '';
    if (duration.inMinutes > 0) {
      durationText +=
          '${duration.inMinutes} minute${duration.inMinutes > 1 ? 's' : ''}';
      if (duration.inSeconds % 60 > 0) {
        durationText += ' and ${duration.inSeconds % 60} seconds';
      }
    } else {
      durationText = '${duration.inSeconds} seconds';
    }

    await _flutterTts.speak('${interval.name} for $durationText');
  }

  void _startTimer() {
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!_isPaused) {
        setState(() {
          if (_secondsRemaining > 0) {
            _secondsRemaining--;

            // Minute countdown
            if (_secondsRemaining > 0 && _secondsRemaining % 60 == 0) {
              int mins = _secondsRemaining ~/ 60;
              _flutterTts.speak('$mins minute${mins > 1 ? 's' : ''} remaining');
            }

            // Final seconds countdown
            if (_secondsRemaining <= 3 && _secondsRemaining > 0) {
              _flutterTts.speak(_secondsRemaining.toString());
            }
          } else {
            _nextInterval();
          }
        });
      }
    });
  }

  void _nextInterval() {
    if (_currentIntervalIndex < widget.plan.intervals.length - 1) {
      _currentIntervalIndex++;
      _secondsRemaining =
          widget.plan.intervals[_currentIntervalIndex].duration.inSeconds;
      _speakCurrentInterval();
    } else {
      _timer?.cancel();
      _flutterTts.speak("Workout complete. Great job!");
      _showCompletionDialog();
    }
  }

  void _skipInterval() {
    setState(() {
      _nextInterval();
    });
  }

  Future<bool> _confirmStop() async {
    setState(() => _isPaused = true);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Stop Workout?'),
        content: const Text(
          'Are you sure you want to stop this training session?',
        ),
        actions: [
          TextButton(
            onPressed: () {
              setState(() => _isPaused = false);
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
    return confirmed ?? false;
  }

  void _showCompletionDialog() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: const Text('Workout Complete!'),
        content: const Text('Great job!'),
        actions: [
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
    _timer?.cancel();
    _flutterTts.stop();
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
              const SizedBox(height: 40),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  ElevatedButton(
                    onPressed: () => setState(() => _isPaused = !_isPaused),
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
