import 'dart:async';
import 'package:flutter/material.dart';
import 'ambience_native.dart' if (dart.library.js_interop) 'ambience_web.dart';

class StudioAmbience extends StatefulWidget {
  const StudioAmbience({super.key});
  @override
  State<StudioAmbience> createState() => _StudioAmbienceState();
}

class _StudioAmbienceState extends State<StudioAmbience> {
  double volume = .25;
  bool playing = false;
  String? error;
  Future<void> change(bool play, double level) async {
    setState(() {
      playing = play;
      volume = level;
      error = null;
    });
    try {
      await ambience(play ? level : 0);
    } catch (_) {
      if (mounted)
        setState(() {
          playing = false;
          error = 'Audio unavailable on this device.';
        });
    }
  }

  @override
  void dispose() {
    if (playing) unawaited(ambience(0).catchError((_) {}));
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Column(children: [
        SwitchListTile(
            title: const Text('Ambient sound'),
            subtitle: error == null ? null : Text(error!),
            value: playing,
            onChanged: (v) => change(v, volume)),
        if (playing)
          Slider(
              value: volume,
              min: .01,
              max: 1,
              label: 'Volume',
              onChanged: (v) => change(true, v)),
      ]);
}
