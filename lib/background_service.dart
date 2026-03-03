import 'dart:async';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'models.dart';

Future<void> initializeService() async {
  final service = FlutterBackgroundService();

  const AndroidNotificationChannel channel = AndroidNotificationChannel(
    'intervaller_foreground',
    'InterEqui Service',
    description: 'Displays the active workout interval and time remaining.',
    importance: Importance.low,
  );

  final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin =
      FlutterLocalNotificationsPlugin();

  await flutterLocalNotificationsPlugin
      .resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin
      >()
      ?.createNotificationChannel(channel);

  await service.configure(
    androidConfiguration: AndroidConfiguration(
      onStart: onStart,
      autoStart: false,
      isForegroundMode: true,
      notificationChannelId: 'intervaller_foreground',
      initialNotificationTitle: 'InterEqui',
      initialNotificationContent: 'Preparing workout...',
      foregroundServiceNotificationId: 888,
      foregroundServiceTypes: [AndroidForegroundType.specialUse],
    ),
    iosConfiguration: IosConfiguration(
      autoStart: false,
      onForeground: onStart,
      onBackground: onIosBackground,
    ),
  );
}

@pragma('vm:entry-point')
Future<bool> onIosBackground(ServiceInstance service) async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    DartPluginRegistrant.ensureInitialized();
  } catch (_) {}
  return true;
}

@pragma('vm:entry-point')
void onStart(ServiceInstance service) async {
  // Some UI-only plugins (file_picker, share_plus, etc.) throw when
  // initialised in a background isolate. Catch so the plugins that DO
  // support background execution (TTS, notifications, prefs) still work.
  try {
    DartPluginRegistrant.ensureInitialized();
  } catch (_) {}

  final FlutterTts flutterTts = FlutterTts();
  final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin =
      FlutterLocalNotificationsPlugin();

  TrainingPlan? currentPlan;
  int currentIntervalIndex = 0;
  int secondsRemaining = 0;
  bool isPaused = false;
  Timer? timer;

  Future<void> speak(String text) async {
    try {
      await flutterTts.speak(text);
    } catch (e) {
      debugPrint('TTS speak error: $e');
    }
  }

  String speakDuration(Duration duration) {
    final mins = duration.inMinutes;
    final secs = duration.inSeconds % 60;
    if (mins > 0 && secs > 0) {
      return '$mins minute${mins > 1 ? 's' : ''} and $secs second${secs > 1 ? 's' : ''}';
    } else if (mins > 0) {
      return '$mins minute${mins > 1 ? 's' : ''}';
    } else {
      return '$secs second${secs > 1 ? 's' : ''}';
    }
  }

  Future<void> updateNotification() async {
    if (currentPlan == null) return;
    final interval = currentPlan!.intervals[currentIntervalIndex];

    String timeStr =
        '${(secondsRemaining ~/ 60).toString().padLeft(2, '0')}:${(secondsRemaining % 60).toString().padLeft(2, '0')}';

    flutterLocalNotificationsPlugin.show(
      888,
      'InterEqui: ${interval.name}',
      'Time remaining: $timeStr',
      const NotificationDetails(
        android: AndroidNotificationDetails(
          'intervaller_foreground',
          'InterEqui Service',
          icon: 'ic_bg_service_small',
          ongoing: true,
        ),
      ),
    );

    service.invoke('update', {
      "index": currentIntervalIndex,
      "seconds": secondsRemaining,
      "isPaused": isPaused,
    });
  }

  void startTimer() {
    timer?.cancel();
    timer = Timer.periodic(const Duration(seconds: 1), (t) async {
      if (!isPaused) {
        if (secondsRemaining > 0) {
          secondsRemaining--;

          if (secondsRemaining > 0 && secondsRemaining % 60 == 0) {
            int mins = secondsRemaining ~/ 60;
            speak('$mins minute${mins > 1 ? 's' : ''} remaining');
          }

          if (secondsRemaining <= 3 && secondsRemaining > 0) {
            speak(secondsRemaining.toString());
          }

          updateNotification();
        } else {
          if (currentIntervalIndex < currentPlan!.intervals.length - 1) {
            currentIntervalIndex++;
            secondsRemaining =
                currentPlan!.intervals[currentIntervalIndex].duration.inSeconds;
            final nextInterval = currentPlan!.intervals[currentIntervalIndex];
            speak('${nextInterval.name} for ${speakDuration(nextInterval.duration)}');
            updateNotification();
          } else {
            speak("Workout complete. Great job!");
            service.invoke('complete');
            t.cancel();
            service.stopSelf();
          }
        }
      }
    });
  }

  // Register all listeners synchronously before any awaits to avoid
  // missing events sent by the UI immediately after startService().
  service.on('startWorkout').listen((event) {
    final planJson = event!['plan'];
    currentPlan = TrainingPlan.fromJson(planJson);
    currentIntervalIndex = 0;
    secondsRemaining = currentPlan!.intervals[0].duration.inSeconds;
    isPaused = false;

    final interval = currentPlan!.intervals[0];
    speak('${interval.name} for ${speakDuration(interval.duration)}');

    startTimer();
    updateNotification();
  });

  service.on('pauseResume').listen((event) {
    isPaused = !isPaused;
    updateNotification();
  });

  service.on('skip').listen((event) {
    if (currentPlan != null &&
        currentIntervalIndex < currentPlan!.intervals.length - 1) {
      currentIntervalIndex++;
      secondsRemaining =
          currentPlan!.intervals[currentIntervalIndex].duration.inSeconds;
      final nextInterval = currentPlan!.intervals[currentIntervalIndex];
      speak('${nextInterval.name} for ${speakDuration(nextInterval.duration)}');
      updateNotification();
    }
  });

  service.on('stopService').listen((event) {
    timer?.cancel();
    service.stopSelf();
  });

  // Initialize TTS with saved voice (async, after listeners are registered).
  // Wrapped in try-catch so that 'ready' is always sent even if
  // SharedPreferences or TTS voice setup fails in the background isolate.
  try {
    final prefs = await SharedPreferences.getInstance();
    final voiceName = prefs.getString('tts_voice_name');
    final voiceLocale = prefs.getString('tts_voice_locale');
    if (voiceName != null && voiceLocale != null) {
      await flutterTts.setVoice({"name": voiceName, "locale": voiceLocale});
    }
  } catch (e) {
    debugPrint('Background TTS voice init error: $e');
  }

  // Signal to the UI that the service is ready to receive commands
  service.invoke('ready');
}
