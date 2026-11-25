import 'package:flutter/services.dart';

Future<void> ambience(double volume) =>
    const MethodChannel('focus_echo/session')
        .invokeMethod<void>('studioAmbience', volume);
