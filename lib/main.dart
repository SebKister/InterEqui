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
  const PlanEditorScreen({super.key});

  @override
  State<PlanEditorScreen> createState() => _PlanEditorScreenState();
}

class _PlanEditorScreenState extends State<PlanEditorScreen> {
  final _nameController = TextEditingController();
  final List<TrainingInterval> _intervals = [];

  void _addInterval() {
    final nameController = TextEditingController(text: 'Interval');
    final minController = TextEditingController(text: '0');
    final secController = TextEditingController(text: '30');

    final List<String> shortcuts = ["Trot", "Walk", "Canter", "Left", "Right"];

    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Add Interval'),
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
                          // If the name is exactly default "Interval", replace it, otherwise append.
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
                if (totalSeconds <= 0) totalSeconds = 30; // fallback default

                setState(() {
                  _intervals.add(
                    TrainingInterval(
                      name: nameController.text.isNotEmpty
                          ? nameController.text
                          : 'Interval',
                      duration: Duration(seconds: totalSeconds),
                    ),
                  );
                });
                Navigator.pop(context);
              },
              child: const Text('Add'),
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
        title: const Text('Create Plan'),
        actions: [
          IconButton(
            icon: const Icon(Icons.save),
            onPressed: () {
              if (_nameController.text.isNotEmpty && _intervals.isNotEmpty) {
                Navigator.pop(
                  context,
                  TrainingPlan(
                    id: DateTime.now().toString(),
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
                  );
                },
              ),
            ),
            ElevatedButton(
              onPressed: _addInterval,
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
