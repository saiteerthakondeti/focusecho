import 'dart:js_interop';
import 'package:web/web.dart' as web;

final _audio = web.HTMLAudioElement()
  ..src = 'assets/assets/audio/soft_noise.wav'
  ..loop = true;
Future<void> ambience(double volume) async {
  if (volume == 0) {
    _audio.pause();
    return;
  }
  _audio.volume = volume;
  if (_audio.paused) await _audio.play().toDart;
}
