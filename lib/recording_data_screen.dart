import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';
import 'gait_models.dart';
import 'accel_recorder.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:speech_to_text/speech_to_text.dart';
import 'package:speech_to_text/speech_recognition_result.dart';

class RecordingDataScreen extends StatefulWidget {
  const RecordingDataScreen({super.key});

  @override
  State<RecordingDataScreen> createState() => _RecordingDataScreenState();
}

enum _RecordingState { idle, countingDown, recording }

class _RecordingDataScreenState extends State<RecordingDataScreen> {
  final AccelRecorder _accelRecorder = AccelRecorder();
  final FlutterTts _tts = FlutterTts();
  final SpeechToText _speechToText = SpeechToText();

  bool _speechEnabled = false;
  bool _isListening = false;

  GaitType _selectedGait = GaitType.walk;
  _RecordingState _state = _RecordingState.idle;

  Timer? _timer;
  int _secondsRemaining = 0;
  int _recordingDurationSeconds = 0;

  @override
  void initState() {
    super.initState();
    _initSpeech();
  }

  Future<void> _initSpeech() async {
    _speechEnabled = await _speechToText.initialize();
    setState(() {});
  }

  Future<void> _toggleListening() async {
    if (_isListening) {
      await _stopListening();
    } else {
      await _startListening();
    }
  }

  Future<void> _startListening() async {
    if (!_speechEnabled) return;
    await _speechToText.listen(onResult: _onSpeechResult);
    setState(() {
      _isListening = true;
    });
  }

  Future<void> _stopListening() async {
    await _speechToText.stop();
    setState(() {
      _isListening = false;
    });
  }

  void _onSpeechResult(SpeechRecognitionResult result) {
    if (!result.finalResult) return;

    final command = result.recognizedWords.toLowerCase();

    bool handled = false;
    if (command.contains("walk")) {
      setState(() => _selectedGait = GaitType.walk);
      handled = true;
    } else if (command.contains("trot")) {
      setState(() => _selectedGait = GaitType.trot);
      handled = true;
    } else if (command.contains("canter")) {
      setState(() => _selectedGait = GaitType.canter);
      handled = true;
    } else if (command.contains("halt")) {
      setState(() => _selectedGait = GaitType.halt);
      handled = true;
    }

    if (command.contains("start recording") || command.contains("start")) {
      if (_state == _RecordingState.idle) {
        _startSequence();
      }
      handled = true;
    } else if (command.contains("stop recording") || command.contains("stop")) {
      if (_state == _RecordingState.recording) {
        _stopRecording();
      }
      handled = true;
    }

    if (handled) {
      // Provide audio feedback or just stop listening
      _tts.speak("Got it").catchError((_) {});
    }

    setState(() {
      _isListening = false; // After a final result, it stops listening
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    _accelRecorder.dispose();
    super.dispose();
  }

  Future<void> _startSequence() async {
    if (_state != _RecordingState.idle) return;

    setState(() {
      _state = _RecordingState.countingDown;
      _secondsRemaining = 5; // 5 seconds delay
      _recordingDurationSeconds = 0;
    });

    for (int i = 5; i > 0; i--) {
      if (!mounted || _state != _RecordingState.countingDown) return;

      setState(() {
        _secondsRemaining = i;
      });

      if (i <= 3) {
        try {
          _tts.speak(i.toString()); // Fire and forget so we don't block
        } catch (_) {}
      }

      await Future.delayed(const Duration(seconds: 1));
    }

    if (!mounted || _state != _RecordingState.countingDown) return;

    try {
      _tts.speak("Start recording");
    } catch (_) {}

    _startRecording();
  }

  Future<void> _startRecording() async {
    if (!mounted) return;
    setState(() {
      _state = _RecordingState.recording;
    });

    await _accelRecorder.start(ignoreLast: const Duration(seconds: 5));
    _accelRecorder.setLabel(gaitLabel(_selectedGait).toLowerCase());

    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (mounted) {
        setState(() {
          _recordingDurationSeconds++;
        });
      }
    });
  }

  Future<void> _stopRecording() async {
    if (_state != _RecordingState.recording) return;

    _timer?.cancel();
    setState(() {
      _state = _RecordingState.idle;
    });

    await _tts.speak("Recording stopped");

    // Stop removes last 5s out of the box because of AccelRecorder implementation
    final file = await _accelRecorder.stop();
    if (mounted && file != null) {
      _showExportDialog(file);
    }
  }

  void _cancelCountdown() {
    _timer?.cancel();
    setState(() {
      _state = _RecordingState.idle;
    });
  }

  void _showExportDialog(File file) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: const Text('Data Recorded'),
        content: Text(
          '${_accelRecorder.sampleCount} accelerometer samples were recorded '
          '(last 5 seconds ignored).\n\n'
          'The data is ready to be exported.',
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              file.delete(); // Delete if discarded
            },
            child: const Text('Discard', style: TextStyle(color: Colors.red)),
          ),
          TextButton.icon(
            onPressed: () {
              Share.shareXFiles([XFile(file.path)]);
              Navigator.pop(context);
            },
            icon: const Icon(Icons.share),
            label: const Text('Export CSV'),
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

  Future<bool> _showExitConfirmationDialog() async {
    final shouldExit = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Exit Training Session?'),
        content: const Text(
          'You are currently recording data. If you exit now, the recorded data will be discarded. Are you sure you want to exit?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Exit', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
    return shouldExit ?? false;
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: _state == _RecordingState.idle,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) {
          return;
        }
        
        final shouldPop = await _showExitConfirmationDialog();
        if (shouldPop) {
          if (mounted) {
            _timer?.cancel();
            _accelRecorder.dispose(); // Ensure it gets cleaned up
            Navigator.of(context).pop();
          }
        }
      },
      child: Scaffold(
        appBar: AppBar(
        title: const Text('Record Training Data'),
        actions: [
          if (_speechEnabled)
            IconButton(
              icon: Icon(
                _isListening ? Icons.mic : Icons.mic_none,
                color: _isListening ? Colors.red : null,
              ),
              onPressed: _toggleListening,
              tooltip: 'Voice Command',
            ),
        ],
      ),
      body: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                'Select the gait to record. Data collected here will be used to train the machine learning model. When started, you will have a 5-second delay to put the phone in your pocket. The last 5 seconds of the recording will be automatically ignored.',
                style: TextStyle(fontSize: 16),
              ),
              const SizedBox(height: 32),
              const Text(
                'Gait Type:',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 16),
              Wrap(
                spacing: 8.0,
                children:
                    [
                      GaitType.halt,
                      GaitType.walk,
                      GaitType.trot,
                      GaitType.canter,
                    ].map((gait) {
                      return ChoiceChip(
                        label: Text(gaitLabel(gait)),
                        selected: _selectedGait == gait,
                        onSelected: _state == _RecordingState.idle
                            ? (selected) {
                                if (selected) {
                                  setState(() {
                                    _selectedGait = gait;
                                  });
                                }
                              }
                            : null,
                      );
                    }).toList(),
              ),
              const SizedBox(height: 48),
              if (_state == _RecordingState.countingDown) ...[
                Text(
                  'Starting in $_secondsRemaining',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 48,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 24),
                ElevatedButton.icon(
                  onPressed: _cancelCountdown,
                  icon: const Icon(Icons.cancel),
                  label: const Text('Cancel Delay'),
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    backgroundColor: Colors.red.shade100,
                  ),
                ),
              ] else if (_state == _RecordingState.recording) ...[
                Text(
                  'Recording: ${_formatDuration(_recordingDurationSeconds)}',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 32,
                    fontWeight: FontWeight.bold,
                    color: Colors.red,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Samples: ${_accelRecorder.sampleCount}',
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 16),
                ),
                const SizedBox(height: 24),
                ElevatedButton.icon(
                  onPressed: _stopRecording,
                  icon: const Icon(Icons.stop),
                  label: const Text(
                    'Stop Recording',
                    style: TextStyle(fontSize: 24, inherit: true),
                  ),
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 24),
                    backgroundColor: Colors.red,
                    foregroundColor: Colors.white,
                  ),
                ),
              ] else ...[
                ElevatedButton.icon(
                  onPressed: _startSequence,
                  icon: const Icon(Icons.play_arrow),
                  label: const Text(
                    'Start Recording',
                    style: TextStyle(fontSize: 24, inherit: true),
                  ),
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 24),
                    backgroundColor: Colors.green,
                    foregroundColor: Colors.white,
                  ),
                ),
              ],
              const SizedBox(height: 48),
            ],
          ),
        ),
      ),
      ),
    );
  }
}
