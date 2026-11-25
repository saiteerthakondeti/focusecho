import 'package:flutter/material.dart';

class FocusEchoLogo extends StatelessWidget {
  const FocusEchoLogo({super.key, this.size = 36});
  final double size;
  @override
  Widget build(BuildContext context) => Image.asset('assets/focusecho.png',
      width: size, height: size, semanticLabel: 'FocusEcho');
}

class FocusEchoBrand extends StatelessWidget {
  const FocusEchoBrand({super.key});
  @override
  Widget build(BuildContext context) =>
      const Row(mainAxisSize: MainAxisSize.min, children: [
        FocusEchoLogo(),
        SizedBox(width: 9),
        Text.rich(
            TextSpan(text: 'Focus', children: [
              TextSpan(text: 'Echo', style: TextStyle(color: Color(0xff36e2ed)))
            ]),
            style: TextStyle(
                fontWeight: FontWeight.w700,
                fontSize: 21,
                color: Colors.white)),
      ]);
}

class NeonPanel extends StatelessWidget {
  const NeonPanel(
      {super.key, required this.child, this.accent = const Color(0xff9464de)});
  final Widget child;
  final Color accent;
  @override
  Widget build(BuildContext context) => Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: accent.withValues(alpha: .55)),
          gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                Color.alphaBlend(
                    accent.withValues(alpha: .19), const Color(0xff0b1024)),
                const Color(0xff0a1528),
                const Color(0xff17142d)
              ])),
      child: child);
}
