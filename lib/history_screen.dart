import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'models.dart';
import 'gait_models.dart';
import 'gait_screen.dart';

class HistoryScreen extends StatefulWidget {
  const HistoryScreen({super.key});

  static Future<void> saveWorkoutRecord(WorkoutRecord record) async {
    final prefs = await SharedPreferences.getInstance();
    final String? historyJson = prefs.getString('workout_history');
    List<WorkoutRecord> history = [];
    if (historyJson != null) {
      final List<dynamic> decoded = json.decode(historyJson);
      history = decoded.map((item) => WorkoutRecord.fromJson(item)).toList();
    }
    history.add(record);
    final String encoded = json.encode(history.map((r) => r.toJson()).toList());
    await prefs.setString('workout_history', encoded);
  }

  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen> {
  List<WorkoutRecord> _history = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadHistory();
  }

  Future<void> _loadHistory() async {
    final prefs = await SharedPreferences.getInstance();
    final String? historyJson = prefs.getString('workout_history');
    if (historyJson != null) {
      final List<dynamic> decoded = json.decode(historyJson);
      setState(() {
        _history = decoded.map((item) => WorkoutRecord.fromJson(item)).toList();
        // Sort descending by timestamp
        _history.sort((a, b) => b.timestamp.compareTo(a.timestamp));
      });
    }
    setState(() {
      _isLoading = false;
    });
  }

  Future<void> _saveHistory() async {
    final prefs = await SharedPreferences.getInstance();
    final String encoded = json.encode(
      _history.map((r) => r.toJson()).toList(),
    );
    await prefs.setString('workout_history', encoded);
  }

  void _confirmDelete(int index) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Workout?'),
        content: Text(
          'Are you sure you want to delete "${_history[index].title}" from your history?',
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
        _history.removeAt(index);
      });
      _saveHistory();
    }
  }

  String _formatDuration(Duration d) {
    final h = d.inHours;
    final m = d.inMinutes % 60;
    final s = d.inSeconds % 60;
    if (h > 0) {
      return '${h.toString()}:${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
    }
    return '${m.toString()}:${s.toString().padLeft(2, '0')}';
  }

  String _formatDate(DateTime date) {
    return '${date.day.toString().padLeft(2, '0')}/${date.month.toString().padLeft(2, '0')}/${date.year} ${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
  }

  void _openDetails(WorkoutRecord record) {
    if (record.type == 'gait' && record.planJson != null) {
      try {
        final session = GaitSession.fromJson(json.decode(record.planJson!));
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => GaitSessionSummaryScreen(session: session),
          ),
        );
      } catch (e) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not load detailed session data')),
        );
      }
    } else if (record.type == 'interval' && record.planJson != null) {
      // Just visual confirmation
      showDialog(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(record.title),
          content: Text(
            'Type: Interval Training\nDate: ${_formatDate(record.timestamp)}\nDuration: ${_formatDuration(record.duration)}',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Close'),
            ),
          ],
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Workout History')),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _history.isEmpty
          ? const Center(child: Text('No previous workouts found.'))
          : ListView.builder(
              itemCount: _history.length,
              itemBuilder: (context, index) {
                final record = _history[index];
                final isGait = record.type == 'gait';
                return ListTile(
                  leading: Icon(
                    isGait ? Icons.sensors : Icons.timer,
                    color: isGait ? Colors.blue : Colors.orange,
                    size: 32,
                  ),
                  title: Text(record.title),
                  subtitle: Text(
                    '${_formatDate(record.timestamp)} • ${_formatDuration(record.duration)}',
                  ),
                  trailing: IconButton(
                    icon: const Icon(Icons.delete_outline),
                    onPressed: () => _confirmDelete(index),
                  ),
                  onTap: () => _openDetails(record),
                );
              },
            ),
    );
  }
}
