class TrainingInterval {
  final String name;
  final Duration duration;

  TrainingInterval({required this.name, required this.duration});

  Map<String, dynamic> toJson() => {
    'name': name,
    'duration': duration.inSeconds,
  };

  factory TrainingInterval.fromJson(Map<String, dynamic> json) =>
      TrainingInterval(
        name: json['name'],
        duration: Duration(seconds: json['duration']),
      );
}

class TrainingPlan {
  final String id;
  final String name;
  final List<TrainingInterval> intervals;

  TrainingPlan({required this.id, required this.name, required this.intervals});

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'intervals': intervals.map((i) => i.toJson()).toList(),
  };

  factory TrainingPlan.fromJson(Map<String, dynamic> json) => TrainingPlan(
    id: json['id'],
    name: json['name'],
    intervals: (json['intervals'] as List)
        .map((i) => TrainingInterval.fromJson(i))
        .toList(),
  );
}

class WorkoutRecord {
  final String id;
  final String title;
  final DateTime timestamp;
  final Duration duration;
  final String type; // 'interval' or 'gait'
  final String? planJson; // Optional JSON encoded GaitSession or TrainingPlan

  WorkoutRecord({
    required this.id,
    required this.title,
    required this.timestamp,
    required this.duration,
    required this.type,
    this.planJson,
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'title': title,
    'timestamp': timestamp.millisecondsSinceEpoch,
    'duration': duration.inSeconds,
    'type': type,
    'planJson': planJson,
  };

  factory WorkoutRecord.fromJson(Map<String, dynamic> json) => WorkoutRecord(
    id: json['id'],
    title: json['title'],
    timestamp: DateTime.fromMillisecondsSinceEpoch(json['timestamp']),
    duration: Duration(seconds: json['duration']),
    type: json['type'],
    planJson: json['planJson'],
  );
}
