import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'focusecho_brand.dart';

const _workspaceRoutes = <({String label, String path, IconData icon})>[
  (label: 'Home', path: '/dashboard', icon: Icons.home_outlined),
  (label: 'Planner', path: '/planner', icon: Icons.calendar_month_outlined),
  (label: 'Focus Studio', path: '/studio', icon: Icons.timer_outlined),
  (label: 'Recovery Lab', path: '/recovery', icon: Icons.favorite_border),
  (label: 'EchoCoach AI', path: '/echo-coach', icon: Icons.psychology_outlined),
  (label: 'Analytics', path: '/analytics', icon: Icons.equalizer),
  (
    label: 'Streaks & XP',
    path: '/streaks-xp',
    icon: Icons.local_fire_department_outlined
  ),
  (label: 'Settings', path: '/settings', icon: Icons.settings_outlined),
];

/// Shared responsive navigation used by the four workspaces and the main app.
class FocusWorkspaceAppBar extends StatelessWidget
    implements PreferredSizeWidget {
  const FocusWorkspaceAppBar({
    super.key,
    required this.activePath,
    this.pageTitle,
    this.actions = const [],
  });

  final String activePath;
  final String? pageTitle;
  final List<Widget> actions;

  @override
  Size get preferredSize => const Size.fromHeight(68);

  bool _isActive(String path) =>
      activePath == path ||
      (path == '/studio' && activePath == '/focus-session');

  @override
  Widget build(BuildContext context) {
    final wide = MediaQuery.sizeOf(context).width >= 1180;
    return AppBar(
      toolbarHeight: 68,
      titleSpacing: 16,
      backgroundColor: const Color(0xff080d1d),
      surfaceTintColor: Colors.transparent,
      title: Row(
        children: [
          const FocusEchoBrand(),
          const SizedBox(width: 22),
          if (wide)
            Expanded(
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    for (final item in _workspaceRoutes)
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 2),
                        child: TextButton.icon(
                          onPressed: () => context.go(item.path),
                          icon: Icon(item.icon, size: 18),
                          label: Text(item.label, maxLines: 1),
                          style: TextButton.styleFrom(
                            foregroundColor: _isActive(item.path)
                                ? Colors.white
                                : const Color(0xffc3c8dc),
                            backgroundColor: _isActive(item.path)
                                ? const Color(0xff6630dc)
                                : Colors.transparent,
                            padding: const EdgeInsets.symmetric(
                                horizontal: 10, vertical: 11),
                            shape: const StadiumBorder(),
                            textStyle: const TextStyle(
                                fontSize: 13, fontWeight: FontWeight.w600),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            )
          else ...[
            Expanded(
              child: Text(
                pageTitle ??
                    _workspaceRoutes
                        .where((item) => _isActive(item.path))
                        .map((item) => item.label)
                        .firstOrNull ??
                    'FocusEcho',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style:
                    const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
              ),
            ),
            PopupMenuButton<String>(
              tooltip: 'Navigate to a workspace',
              icon: const Icon(Icons.apps_rounded),
              onSelected: context.go,
              itemBuilder: (_) => [
                for (final item in _workspaceRoutes)
                  PopupMenuItem<String>(
                    value: item.path,
                    child: Row(children: [
                      Icon(item.icon, size: 19),
                      const SizedBox(width: 12),
                      Text(item.label),
                    ]),
                  ),
              ],
            ),
          ],
        ],
      ),
      actions: [
        ...actions,
        if (wide)
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 14),
            child: CircleAvatar(
              radius: 17,
              backgroundColor: Color(0xff343f76),
              child: Icon(Icons.person_outline, size: 20, color: Colors.white),
            ),
          ),
      ],
      bottom: const PreferredSize(
        preferredSize: Size.fromHeight(1),
        child: Divider(height: 1, color: Color(0xff25304b)),
      ),
    );
  }
}

class WorkspacePageHeader extends StatelessWidget {
  const WorkspacePageHeader({
    super.key,
    required this.title,
    required this.subtitle,
    required this.icon,
    this.trailing,
    this.accent = const Color(0xffbb70ff),
  });

  final String title;
  final String subtitle;
  final IconData icon;
  final Widget? trailing;
  final Color accent;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(4, 8, 4, 18),
        child: Row(
          children: [
            Container(
              width: 54,
              height: 54,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: accent.withValues(alpha: .13),
                boxShadow: [
                  BoxShadow(color: accent.withValues(alpha: .2), blurRadius: 22)
                ],
              ),
              child: Icon(icon, size: 30, color: accent),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title,
                      style:
                          Theme.of(context).textTheme.headlineSmall?.copyWith(
                                fontWeight: FontWeight.w700,
                                letterSpacing: -.4,
                              )),
                  const SizedBox(height: 3),
                  Text(subtitle,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            color: const Color(0xffaeb9d3),
                          )),
                ],
              ),
            ),
            if (trailing != null) ...[
              const SizedBox(width: 10),
              trailing!,
            ],
          ],
        ),
      );
}

class WorkspaceStatCard extends StatelessWidget {
  const WorkspaceStatCard({
    super.key,
    required this.icon,
    required this.value,
    required this.label,
    this.accent = const Color(0xff32d8f2),
    this.detail,
  });

  final IconData icon;
  final String value;
  final String label;
  final Color accent;
  final String? detail;

  @override
  Widget build(BuildContext context) => Container(
        constraints: const BoxConstraints(minWidth: 150),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: accent.withValues(alpha: .42)),
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              accent.withValues(alpha: .13),
              const Color(0xff11182c),
              const Color(0xff10142b),
            ],
          ),
        ),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: accent.withValues(alpha: .14),
              ),
              child: Icon(icon, color: accent, size: 21),
            ),
            const SizedBox(width: 11),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(value,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          fontSize: 19,
                          color: Colors.white,
                          fontWeight: FontWeight.w700)),
                  Text(label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          fontSize: 12, color: Color(0xffabb7d1))),
                  if (detail != null)
                    Text(detail!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 11, color: accent)),
                ],
              ),
            ),
          ],
        ),
      );
}

class WorkspaceChip extends StatelessWidget {
  const WorkspaceChip(
      {super.key,
      required this.label,
      this.icon,
      this.accent = const Color(0xffbb70ff)});
  final String label;
  final IconData? icon;
  final Color accent;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: accent.withValues(alpha: .1),
          border: Border.all(color: accent.withValues(alpha: .42)),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          if (icon != null) ...[
            Icon(icon, size: 16, color: accent),
            const SizedBox(width: 7),
          ],
          Text(label,
              style: TextStyle(color: accent, fontWeight: FontWeight.w600)),
        ]),
      );
}
