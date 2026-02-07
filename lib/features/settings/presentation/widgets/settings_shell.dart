import 'package:flutter/material.dart';

import '../../../../shared/widgets/glass/glass.dart';

class SettingsHeader extends StatelessWidget {
  const SettingsHeader({super.key, this.title = 'Settings'});

  final String title;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      child: Row(
        children: [
          Expanded(
            child: Text(
              title,
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.w700,
                letterSpacing: -0.5,
              ),
            ),
          ),
          GlassIconButton.panel(
            tooltip: 'Close',
            icon: Icons.close_rounded,
            onPressed: () => Navigator.of(context).maybePop(),
          ),
        ],
      ),
    );
  }
}

class SettingsTabStrip extends StatelessWidget {
  const SettingsTabStrip({super.key});

  @override
  Widget build(BuildContext context) {
    return GlassPanel(
      padding: const EdgeInsets.all(6),
      child: TabBar(
        dividerColor: Colors.transparent,
        indicatorSize: TabBarIndicatorSize.tab,
        indicator: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(12),
        ),
        labelColor: Colors.white.withValues(alpha: 0.95),
        unselectedLabelColor: Colors.white.withValues(alpha: 0.65),
        tabs: const [
          Tab(icon: Icon(Icons.settings_rounded, size: 18), text: 'General'),
          Tab(
            icon: Icon(Icons.notifications_rounded, size: 18),
            text: 'Notifications',
          ),
          Tab(icon: Icon(Icons.auto_awesome_rounded, size: 18), text: 'LLM'),
          Tab(icon: Icon(Icons.mic_rounded, size: 18), text: 'STT'),
        ],
      ),
    );
  }
}
