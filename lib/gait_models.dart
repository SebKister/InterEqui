import 'package:flutter/material.dart';

enum GaitType {
  halt,
  walk,
  trot,
  canter,
  unknown,
}

class GaitReading {
  final DateTime timestamp;
  final GaitType gait;
  final double confidence;
  final double dominantFrequency;
  final double amplitude;

  GaitReading({
    required this.timestamp,
    required this.gait,
    required this.confidence,
    required this.dominantFrequency,
    required this.amplitude,
  });

  Map<String, dynamic> toJson() => {
    'timestamp': timestamp.millisecondsSinceEpoch,
    'gait': gait.name,
    'confidence': confidence,
    'dominantFrequency': dominantFrequency,
    'amplitude': amplitude,
  };

  factory GaitReading.fromJson(Map<String, dynamic> json) => GaitReading(
    timestamp: DateTime.fromMillisecondsSinceEpoch(json['timestamp']),
    gait: GaitType.values.byName(json['gait']),
    confidence: (json['confidence'] as num).toDouble(),
    dominantFrequency: (json['dominantFrequency'] as num).toDouble(),
    amplitude: (json['amplitude'] as num).toDouble(),
  );
}

class GaitTransition {
  final DateTime timestamp;
  final GaitType fromGait;
  final GaitType toGait;

  GaitTransition({
    required this.timestamp,
    required this.fromGait,
    required this.toGait,
  });

  Map<String, dynamic> toJson() => {
    'timestamp': timestamp.millisecondsSinceEpoch,
    'fromGait': fromGait.name,
    'toGait': toGait.name,
  };

  factory GaitTransition.fromJson(Map<String, dynamic> json) => GaitTransition(
    timestamp: DateTime.fromMillisecondsSinceEpoch(json['timestamp']),
    fromGait: GaitType.values.byName(json['fromGait']),
    toGait: GaitType.values.byName(json['toGait']),
  );
}

class GaitSession {
  final String id;
  final DateTime startTime;
  final DateTime? endTime;
  final List<GaitTransition> transitions;
  final Map<GaitType, Duration> gaitDurations;

  GaitSession({
    required this.id,
    required this.startTime,
    this.endTime,
    required this.transitions,
    required this.gaitDurations,
  });

  Duration get totalDuration =>
    (endTime ?? DateTime.now()).difference(startTime);

  Map<String, dynamic> toJson() => {
    'id': id,
    'startTime': startTime.millisecondsSinceEpoch,
    'endTime': endTime?.millisecondsSinceEpoch,
    'transitions': transitions.map((t) => t.toJson()).toList(),
    'gaitDurations': gaitDurations.map(
      (k, v) => MapEntry(k.name, v.inMilliseconds),
    ),
  };

  factory GaitSession.fromJson(Map<String, dynamic> json) {
    final durMap = (json['gaitDurations'] as Map<String, dynamic>).map(
      (k, v) => MapEntry(GaitType.values.byName(k), Duration(milliseconds: v as int)),
    );
    return GaitSession(
      id: json['id'],
      startTime: DateTime.fromMillisecondsSinceEpoch(json['startTime']),
      endTime: json['endTime'] != null
        ? DateTime.fromMillisecondsSinceEpoch(json['endTime'])
        : null,
      transitions: (json['transitions'] as List)
        .map((t) => GaitTransition.fromJson(t)).toList(),
      gaitDurations: durMap,
    );
  }
}

Color gaitColor(GaitType gait) {
  switch (gait) {
    case GaitType.halt:    return Colors.grey;
    case GaitType.walk:    return Colors.green;
    case GaitType.trot:    return Colors.orange;
    case GaitType.canter:  return Colors.red;
    case GaitType.unknown: return Colors.blueGrey;
  }
}

IconData gaitIcon(GaitType gait) {
  switch (gait) {
    case GaitType.halt:    return Icons.pause_circle_outline;
    case GaitType.walk:    return Icons.directions_walk;
    case GaitType.trot:    return Icons.speed;
    case GaitType.canter:  return Icons.flash_on;
    case GaitType.unknown: return Icons.help_outline;
  }
}

String gaitLabel(GaitType gait) {
  switch (gait) {
    case GaitType.halt:    return 'Halt';
    case GaitType.walk:    return 'Walk';
    case GaitType.trot:    return 'Trot';
    case GaitType.canter:  return 'Canter';
    case GaitType.unknown: return '...';
  }
}
