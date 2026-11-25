import 'package:flutter/material.dart';

import '../onboarding/app_selector/app_selector_viewmodel.dart';

class SessionAppLogo extends StatelessWidget {
  const SessionAppLogo(this.app, {super.key});

  final String app;

  static const _icons = {
    'chrome': 'chrome',
    'google chrome': 'chrome',
    'com.android.chrome': 'chrome',
    'vs code': 'vscode',
    'visual studio code': 'vscode',
    'vscode': 'vscode',
    'youtube': 'youtube',
    'notion': 'notion',
    'google docs': 'docs',
    'github': 'github',
    'coursera': 'coursera',
    'khan academy': 'khan',
    'instagram': 'instagram',
    'reddit': 'reddit',
    'duolingo': 'duolingo',
  };

  static String label(String app) {
    final value = app.trim();
    if (value.toLowerCase() == 'com.android.chrome') return 'Chrome';
    return AppSelectorViewModel.productiveApps[value] ??
        AppSelectorViewModel.distractingApps[value] ??
        (value.isEmpty ? 'Focus session' : value);
  }

  @override
  Widget build(BuildContext context) {
    final name = label(app).toLowerCase();
    final host =
        Uri.tryParse(name.contains('://') ? name : 'https://$name')?.host ?? '';
    final asset = _icons[name] ??
        const {
          'instagram.com': 'instagram',
          'youtube.com': 'youtube',
          'youtu.be': 'youtube',
          'reddit.com': 'reddit'
        }[host.replaceFirst(RegExp(r'^www\.'), '')];
    return SizedBox.square(
      dimension: 38,
      child: asset == null
          ? const Icon(Icons.apps_rounded, color: Color(0xff7dcfe6))
          : Padding(
              padding: const EdgeInsets.all(2),
              child: Image.asset('assets/apps/$asset.png',
                  excludeFromSemantics: true)),
    );
  }
}
