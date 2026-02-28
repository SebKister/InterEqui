class TrainingInterval {
  final String name;
  final Duration duration;

  TrainingInterval({required this.name, required this.duration});

  Map<String, dynamic> toJson() => {
    'name': name,
    'duration': duration.inSeconds,
  };

  factory TrainingInterval.fromJson(Map<String, dynamic> json) => TrainingInterval(
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
    intervals: (json['intervals'] as List).map((i) => TrainingInterval.fromJson(i)).toList(),
  );
}
