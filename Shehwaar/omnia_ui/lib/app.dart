import 'package:flutter/material.dart';
import 'package:omnia_ui/core/theme/app_colors.dart';
import 'package:omnia_ui/core/theme/app_theme.dart';
import 'package:omnia_ui/features/home/home_page.dart';
import 'package:omnia_ui/features/insights/insights_page.dart';
import 'package:omnia_ui/features/plan/plan_page.dart';
import 'package:omnia_ui/features/track/track_page.dart';

class OmniaApp extends StatelessWidget {
  const OmniaApp({super.key});
  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'Omnia',
    debugShowCheckedModeBanner: false,
    theme: buildAppTheme(),
    home: const OmniaHome(),
  );
}

class OmniaHome extends StatefulWidget {
  const OmniaHome({super.key});
  @override
  State<OmniaHome> createState() => _OmniaHomeState();
}

class _OmniaHomeState extends State<OmniaHome> {
  int tab = 0;
  @override
  Widget build(BuildContext context) {
    final pages = [
      HomePage(openPlan: () => setState(() => tab = 1)),
      const PlanPage(),
      const TrackPage(),
      const InsightsPage(),
    ];
    final dark = tab == 1;
    return Scaffold(
      backgroundColor: dark ? night : paper,
      body: SafeArea(child: pages[tab]),
      bottomNavigationBar: Container(
        decoration: BoxDecoration(
          color: dark ? night : paper,
          border: Border(
            top: BorderSide(color: dark ? Colors.white24 : ink, width: 1.5),
          ),
        ),
        child: SafeArea(
          top: false,
          child: Row(
            children: [
              _nav(0, Icons.home_rounded, 'Home', dark),
              _nav(1, Icons.calendar_month_outlined, 'Plan', dark),
              _nav(2, Icons.bar_chart_rounded, 'Track', dark),
              _nav(3, Icons.pie_chart_outline, 'Insights', dark),
            ],
          ),
        ),
      ),
    );
  }

  Widget _nav(int index, IconData icon, String title, bool dark) {
    final active = tab == index;
    final color = dark ? Colors.white : ink;
    return Expanded(
      child: InkWell(
        onTap: () => setState(() => tab = index),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 9),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 4,
                ),
                decoration: BoxDecoration(
                  color: active ? (dark ? lilac : blue) : Colors.transparent,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Icon(
                  icon,
                  size: 23,
                  color: active ? ink : color.withValues(alpha: .65),
                ),
              ),
              const SizedBox(height: 3),
              Text(
                title,
                style: TextStyle(
                  fontSize: 11,
                  color: color,
                  fontWeight: active ? FontWeight.w800 : FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
