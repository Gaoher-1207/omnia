import 'package:flutter/material.dart';

void main() => runApp(const OmniaApp());

const ink = Color(0xFF18191E);
const paper = Color(0xFFFFFEFB);
const night = Color(0xFF17181C);
const lilac = Color(0xFFE0C6FF);
const blue = Color(0xFFAED1FF);
const yellow = Color(0xFFFFE493);
const mint = Color(0xFFA9E8CD);
const purple = Color(0xFF7666ED);

class OmniaApp extends StatelessWidget {
  const OmniaApp({super.key});
  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'Omnia',
    debugShowCheckedModeBanner: false,
    theme: ThemeData(
      useMaterial3: true,
      scaffoldBackgroundColor: paper,
      colorScheme: ColorScheme.fromSeed(
        seedColor: purple,
        brightness: Brightness.light,
      ),
    ),
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

class HomePage extends StatelessWidget {
  const HomePage({super.key, required this.openPlan});
  final VoidCallback openPlan;
  @override
  Widget build(BuildContext context) => ListView(
    padding: const EdgeInsets.all(18),
    children: [
      Row(
        children: [
          const Expanded(
            child: Text(
              'Good morning,\nShew.',
              style: TextStyle(
                fontSize: 29,
                height: 1.04,
                fontWeight: FontWeight.w900,
                color: ink,
              ),
            ),
          ),
          IconButton.filledTonal(
            onPressed: () {},
            icon: const Icon(Icons.person_outline),
            style: IconButton.styleFrom(
              backgroundColor: ink,
              foregroundColor: Colors.white,
            ),
          ),
        ],
      ),
      const SizedBox(height: 5),
      const Text(
        'Tuesday, September 23  ·  SAMPLE DAY',
        style: TextStyle(fontSize: 12, letterSpacing: .4, color: ink),
      ),
      const SizedBox(height: 18),
      HardCard(
        color: lilac,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Row(
              children: [
                OmniaMark(),
                SizedBox(width: 9),
                Text(
                  'omnia',
                  style: TextStyle(fontSize: 21, fontWeight: FontWeight.w900),
                ),
                Spacer(),
                LabelTag(text: 'SAMPLE'),
              ],
            ),
            const SizedBox(height: 17),
            const Text(
              'Your DBMS exam is in 8 days.',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: 8),
            const Text(
              'Your plan includes a 45-minute revision session today. '
              'You can adjust it to fit your schedule.',
              style: TextStyle(height: 1.35),
            ),
            const SizedBox(height: 18),
            Row(
              children: [
                Expanded(
                  child: SolidAction(
                    label: "View today's plan",
                    onTap: openPlan,
                  ),
                ),
                const SizedBox(width: 8),
                OutlinedButton(
                  onPressed: () => ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('This is a sample recommendation.'),
                    ),
                  ),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: ink,
                    side: const BorderSide(color: ink, width: 1.5),
                  ),
                  child: const Text('Why?'),
                ),
              ],
            ),
          ],
        ),
      ),
      const SizedBox(height: 10),
      const Row(
        children: [
          Expanded(
            child: CategoryCard(
              icon: Icons.menu_book_outlined,
              title: 'Study',
              amount: '2h 15m',
              goal: '/ 4h',
              progress: .56,
              color: blue,
            ),
          ),
          SizedBox(width: 10),
          Expanded(
            child: CategoryCard(
              icon: Icons.task_alt,
              title: 'Tasks',
              amount: '4 / 6',
              goal: 'completed',
              progress: .67,
              color: yellow,
            ),
          ),
        ],
      ),
      const SizedBox(height: 10),
      const Row(
        children: [
          Expanded(
            child: CategoryCard(
              icon: Icons.directions_run,
              title: 'Activity',
              amount: '6,240',
              goal: '/ 8,000',
              progress: .78,
              color: mint,
            ),
          ),
          SizedBox(width: 10),
          Expanded(
            child: CategoryCard(
              icon: Icons.dark_mode_outlined,
              title: 'Sleep',
              amount: '6h 42m',
              goal: '/ 8h',
              progress: .84,
              color: lilac,
            ),
          ),
        ],
      ),
      const SizedBox(height: 20),
      Row(
        children: [
          const Expanded(
            child: Text(
              'Next up',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900),
            ),
          ),
          TextButton(onPressed: openPlan, child: const Text('See all →')),
        ],
      ),
      const AgendaLine(
        time: '10:00',
        title: 'DBMS Revision',
        duration: '45m',
        icon: Icons.menu_book_outlined,
        color: blue,
      ),
      const AgendaLine(
        time: '11:00',
        title: 'Complete Assignment',
        duration: '1h',
        icon: Icons.task_alt,
        color: yellow,
      ),
      const AgendaLine(
        time: '16:30',
        title: 'Walk',
        duration: '20m',
        icon: Icons.directions_walk,
        color: mint,
      ),
      const SizedBox(height: 18),
    ],
  );
}

class PlanPage extends StatelessWidget {
  const PlanPage({super.key});
  @override
  Widget build(BuildContext context) => ListView(
    padding: const EdgeInsets.all(18),
    children: [
      const Center(
        child: Text(
          "Today's Plan",
          style: TextStyle(
            color: Colors.white,
            fontSize: 25,
            fontWeight: FontWeight.w900,
          ),
        ),
      ),
      const SizedBox(height: 4),
      const Center(
        child: Text(
          'Tue, Sep 23  ·  SAMPLE DAY',
          style: TextStyle(color: Colors.white70, fontSize: 12),
        ),
      ),
      const SizedBox(height: 22),
      Container(
        padding: const EdgeInsets.all(4),
        decoration: BoxDecoration(
          color: const Color(0xFF303238),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            _mode('Timeline', true),
            _mode('List', false),
            _mode('Focus', false),
          ],
        ),
      ),
      const SizedBox(height: 21),
      const TimelineRow(
        time: '08:00',
        title: 'Morning Routine',
        duration: '30m',
        icon: Icons.dark_mode_outlined,
        color: lilac,
      ),
      const TimelineRow(
        time: '09:00',
        title: 'College / Classes',
        duration: '1h',
        icon: Icons.school_outlined,
        color: yellow,
      ),
      TimelineRow(
        time: '10:00',
        title: 'DBMS Revision',
        duration: '45m',
        icon: Icons.menu_book_outlined,
        color: blue,
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const RevisionDetailPage()),
        ),
      ),
      const TimelineRow(
        time: '11:00',
        title: 'Complete Assignment',
        duration: '1h',
        icon: Icons.task_alt,
        color: yellow,
      ),
      const TimelineRow(
        time: '13:00',
        title: 'Lunch',
        duration: '1h',
        icon: Icons.restaurant_outlined,
        color: mint,
      ),
      const TimelineRow(
        time: '16:30',
        title: 'Walk',
        duration: '20m',
        icon: Icons.directions_walk,
        color: mint,
      ),
      const TimelineRow(
        time: '18:30',
        title: 'Push Workout',
        duration: '35m',
        icon: Icons.fitness_center,
        color: mint,
      ),
      const TimelineRow(
        time: '21:00',
        title: 'Revision',
        duration: '45m',
        icon: Icons.menu_book_outlined,
        color: blue,
      ),
      const TimelineRow(
        time: '22:00',
        title: 'Wind Down',
        duration: '30m',
        icon: Icons.dark_mode_outlined,
        color: lilac,
      ),
      const SizedBox(height: 18),
      const HardCard(
        color: lilac,
        child: Row(
          children: [
            OmniaMark(),
            SizedBox(width: 11),
            Expanded(
              child: Text(
                'Your plan will adapt as your day changes.',
                style: TextStyle(fontWeight: FontWeight.w700),
              ),
            ),
            Icon(Icons.arrow_forward),
          ],
        ),
      ),
      const SizedBox(height: 14),
      const Text(
        'Timeline is a visual sample. Scheduling and rescheduling '
        'will be connected when the planning API is ready.',
        style: TextStyle(color: Colors.white60, fontSize: 12),
      ),
    ],
  );
  Widget _mode(String name, bool selected) => Expanded(
    child: Container(
      alignment: Alignment.center,
      padding: const EdgeInsets.symmetric(vertical: 10),
      decoration: BoxDecoration(
        color: selected ? lilac : Colors.transparent,
        borderRadius: BorderRadius.circular(9),
      ),
      child: Text(
        name,
        style: TextStyle(
          color: selected ? ink : Colors.white70,
          fontWeight: FontWeight.w700,
        ),
      ),
    ),
  );
}

class RevisionDetailPage extends StatefulWidget {
  const RevisionDetailPage({super.key});
  @override
  State<RevisionDetailPage> createState() => _RevisionDetailPageState();
}

class _RevisionDetailPageState extends State<RevisionDetailPage> {
  final tasks = [
    'Revise normalization',
    'Practice SQL questions',
    'Go through past papers',
  ];
  final checked = [false, false, false];
  @override
  Widget build(BuildContext context) {
    final done = checked.where((item) => item).length;
    return Scaffold(
      backgroundColor: paper,
      appBar: AppBar(
        backgroundColor: paper,
        title: const Text(
          'DBMS Revision',
          style: TextStyle(fontWeight: FontWeight.w900),
        ),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(18),
          children: [
            Row(
              children: [
                const HardCard(
                  color: blue,
                  child: Icon(Icons.menu_book_outlined, size: 32),
                ),
                const SizedBox(width: 13),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'DBMS Revision',
                        style: TextStyle(
                          fontSize: 21,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      Text('Tue, Sep 23  ·  10:00 – 10:45'),
                      Text(
                        '45 minutes',
                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 22),
            Row(
              children: [
                Expanded(
                  child: SolidAction(
                    label: done == tasks.length ? 'Completed' : 'Mark done',
                    onTap: () => setState(() {
                      for (var i = 0; i < checked.length; i++) {
                        checked[i] = true;
                      }
                    }),
                  ),
                ),
                const SizedBox(width: 8),
                _smallAction(context, Icons.edit_outlined, 'Edit'),
                const SizedBox(width: 8),
                _smallAction(context, Icons.more_horiz, 'More'),
              ],
            ),
            const SizedBox(height: 20),
            HardCard(
              color: lilac,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Row(
                    children: [
                      OmniaMark(),
                      SizedBox(width: 8),
                      Text(
                        'omnia recommends',
                        style: TextStyle(
                          fontWeight: FontWeight.w900,
                          fontSize: 16,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'Keep this revision session short so you have time '
                    'for the rest of your plan.',
                    style: TextStyle(height: 1.35),
                  ),
                  const SizedBox(height: 12),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: paper,
                      border: Border.all(color: ink),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'What changed?',
                          style: TextStyle(fontWeight: FontWeight.w900),
                        ),
                        SizedBox(height: 5),
                        Text(
                          'This is sample copy. The AI explanation will be '
                          'connected when that service is ready.',
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
            const Text(
              'Materials',
              style: TextStyle(fontSize: 19, fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: 9),
            const HardCard(
              color: paper,
              child: Row(
                children: [
                  Icon(Icons.description_outlined),
                  SizedBox(width: 10),
                  Expanded(child: Text('DBMS Notes.pdf  ·  Sample')),
                  Icon(Icons.more_vert),
                ],
              ),
            ),
            const SizedBox(height: 19),
            Text(
              'Sub-tasks  $done/${tasks.length}',
              style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w900),
            ),
            for (var i = 0; i < tasks.length; i++)
              CheckboxListTile(
                value: checked[i],
                activeColor: ink,
                controlAffinity: ListTileControlAffinity.leading,
                contentPadding: EdgeInsets.zero,
                title: Text(
                  tasks[i],
                  style: TextStyle(
                    decoration: checked[i] ? TextDecoration.lineThrough : null,
                  ),
                ),
                onChanged: (value) =>
                    setState(() => checked[i] = value ?? false),
              ),
            const SizedBox(height: 15),
            SolidAction(
              label: 'Start Focus Session',
              onTap: () => ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Focus session is coming later.')),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _smallAction(BuildContext context, IconData icon, String title) =>
      Expanded(
        child: OutlinedButton.icon(
          onPressed: () => ScaffoldMessenger.of(context)
              .showSnackBar(SnackBar(content: Text('$title is coming later.'))),
          icon: Icon(icon, size: 18),
          label: Text(title),
          style: OutlinedButton.styleFrom(
            foregroundColor: ink,
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 15),
            side: const BorderSide(color: ink, width: 1.5),
          ),
        ),
      );
}

class TrackPage extends StatelessWidget {
  const TrackPage({super.key});
  @override
  Widget build(BuildContext context) => ListView(
    padding: const EdgeInsets.all(18),
    children: const [
      Text(
        'Track',
        style: TextStyle(fontSize: 29, fontWeight: FontWeight.w900),
      ),
      SizedBox(height: 4),
      Text('Your day at a glance  ·  SAMPLE DATA'),
      SizedBox(height: 20),
      TrackTile(
        icon: Icons.menu_book_outlined,
        name: 'Study',
        amount: '2h 15m',
        goal: '4h goal',
        progress: .56,
        color: blue,
      ),
      TrackTile(
        icon: Icons.task_alt,
        name: 'Tasks',
        amount: '4 of 6',
        goal: 'tasks done',
        progress: .67,
        color: yellow,
      ),
      TrackTile(
        icon: Icons.directions_walk,
        name: 'Activity',
        amount: '6,240',
        goal: '8,000 steps',
        progress: .78,
        color: mint,
      ),
      TrackTile(
        icon: Icons.dark_mode_outlined,
        name: 'Sleep',
        amount: '6h 42m',
        goal: '8h goal',
        progress: .84,
        color: lilac,
      ),
      SizedBox(height: 15),
      Text(
        'Today’s activity',
        style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900),
      ),
      SizedBox(height: 9),
      HardCard(
        color: paper,
        child: Column(
          children: [
            ActivityLine(
              icon: Icons.check,
              title: 'Morning routine',
              time: '08:30',
            ),
            Divider(),
            ActivityLine(
              icon: Icons.menu_book_outlined,
              title: 'DBMS study',
              time: '10:00',
            ),
            Divider(),
            ActivityLine(
              icon: Icons.directions_walk,
              title: 'Walk',
              time: '16:30',
            ),
          ],
        ),
      ),
      SizedBox(height: 20),
    ],
  );
}

class InsightsPage extends StatelessWidget {
  const InsightsPage({super.key});
  @override
  Widget build(BuildContext context) => ListView(
    padding: const EdgeInsets.all(18),
    children: const [
      Text(
        'Insights',
        style: TextStyle(fontSize: 29, fontWeight: FontWeight.w900),
      ),
      SizedBox(height: 5),
      Text('Patterns across your week  ·  SAMPLE DATA'),
      SizedBox(height: 24),
      HardCard(
        color: lilac,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            OmniaMark(),
            SizedBox(height: 12),
            Text(
              'Your week in perspective',
              style: TextStyle(fontSize: 21, fontWeight: FontWeight.w900),
            ),
            SizedBox(height: 6),
            Text(
              'Insights will be connected to your real activity after '
              'tracking and the backend are ready.',
            ),
          ],
        ),
      ),
    ],
  );
}

class HardCard extends StatelessWidget {
  const HardCard({super.key, required this.color, required this.child});
  final Color color;
  final Widget child;
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: color,
      borderRadius: BorderRadius.circular(14),
      border: Border.all(color: ink, width: 1.6),
    ),
    child: child,
  );
}

class OmniaMark extends StatelessWidget {
  const OmniaMark({super.key});
  @override
  Widget build(BuildContext context) => SizedBox(
    width: 34,
    height: 34,
    child: Stack(
      children: [
        Positioned(
          left: 1,
          top: 8,
          child: _circle(22, purple.withValues(alpha: .65)),
        ),
        Positioned(
          left: 10,
          top: 1,
          child: _circle(22, const Color(0xFFAA92FF).withValues(alpha: .8)),
        ),
        Positioned(
          left: 12,
          top: 12,
          child: _circle(20, const Color(0xFF4538D8).withValues(alpha: .75)),
        ),
      ],
    ),
  );
  Widget _circle(double size, Color color) => Container(
    width: size,
    height: size,
    decoration: BoxDecoration(shape: BoxShape.circle, color: color),
  );
}

class LabelTag extends StatelessWidget {
  const LabelTag({super.key, required this.text});
  final String text;
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
    decoration: BoxDecoration(
      color: ink,
      borderRadius: BorderRadius.circular(7),
    ),
    child: Text(
      text,
      style: const TextStyle(
        color: Colors.white,
        fontSize: 10,
        fontWeight: FontWeight.w900,
      ),
    ),
  );
}

class SolidAction extends StatelessWidget {
  const SolidAction({super.key, required this.label, required this.onTap});
  final String label;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => FilledButton(
    onPressed: onTap,
    style: FilledButton.styleFrom(
      backgroundColor: ink,
      foregroundColor: Colors.white,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 15),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(9)),
    ),
    child: Text(
      label,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: const TextStyle(fontWeight: FontWeight.w800),
    ),
  );
}

class CategoryCard extends StatelessWidget {
  const CategoryCard({
    super.key,
    required this.icon,
    required this.title,
    required this.amount,
    required this.goal,
    required this.progress,
    required this.color,
  });
  final IconData icon;
  final String title, amount, goal;
  final double progress;
  final Color color;
  @override
  Widget build(BuildContext context) => HardCard(
    color: color,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 27),
        const SizedBox(height: 5),
        Text(title, style: const TextStyle(fontWeight: FontWeight.w800)),
        Text(
          amount,
          style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w900),
        ),
        Text(goal, style: const TextStyle(fontSize: 11)),
        const SizedBox(height: 8),
        ClipRRect(
          borderRadius: BorderRadius.circular(9),
          child: LinearProgressIndicator(
            value: progress,
            minHeight: 7,
            backgroundColor: Colors.white70,
            color: ink,
          ),
        ),
      ],
    ),
  );
}

class AgendaLine extends StatelessWidget {
  const AgendaLine({
    super.key,
    required this.time,
    required this.title,
    required this.duration,
    required this.icon,
    required this.color,
  });
  final String time, title, duration;
  final IconData icon;
  final Color color;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 5),
    child: Row(
      children: [
        SizedBox(
          width: 54,
          child: Text(time, style: const TextStyle(fontSize: 12)),
        ),
        CircleAvatar(
          radius: 14,
          backgroundColor: color,
          child: Icon(icon, size: 16, color: ink),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 13),
          ),
        ),
        Text(duration, style: const TextStyle(fontSize: 12)),
      ],
    ),
  );
}

class TimelineRow extends StatelessWidget {
  const TimelineRow({
    super.key,
    required this.time,
    required this.title,
    required this.duration,
    required this.icon,
    required this.color,
    this.onTap,
  });
  final String time, title, duration;
  final IconData icon;
  final Color color;
  final VoidCallback? onTap;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 10),
    child: Row(
      children: [
        SizedBox(
          width: 52,
          child: Text(
            time,
            style: const TextStyle(color: Colors.white70, fontSize: 12),
          ),
        ),
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 9),
        Expanded(
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(10),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 14),
              decoration: BoxDecoration(
                color: color,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(
                children: [
                  Icon(icon, color: ink, size: 21),
                  const SizedBox(width: 9),
                  Expanded(
                    child: Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: ink,
                        fontSize: 13,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  Text(
                    duration,
                    style: const TextStyle(color: ink, fontSize: 12),
                  ),
                  if (onTap != null)
                    const Padding(
                      padding: EdgeInsets.only(left: 6),
                      child: Icon(Icons.chevron_right, size: 16, color: ink),
                    ),
                ],
              ),
            ),
          ),
        ),
      ],
    ),
  );
}

class TrackTile extends StatelessWidget {
  const TrackTile({
    super.key,
    required this.icon,
    required this.name,
    required this.amount,
    required this.goal,
    required this.progress,
    required this.color,
  });
  final IconData icon;
  final String name, amount, goal;
  final double progress;
  final Color color;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 10),
    child: HardCard(
      color: color,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  name,
                  style: const TextStyle(fontWeight: FontWeight.w900),
                ),
              ),
              Text(goal, style: const TextStyle(fontSize: 12)),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            amount,
            style: const TextStyle(fontSize: 23, fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 10),
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: LinearProgressIndicator(
              value: progress,
              minHeight: 8,
              backgroundColor: Colors.white70,
              color: ink,
            ),
          ),
        ],
      ),
    ),
  );
}

class ActivityLine extends StatelessWidget {
  const ActivityLine({
    super.key,
    required this.icon,
    required this.title,
    required this.time,
  });
  final IconData icon;
  final String title, time;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 5),
    child: Row(
      children: [
        Icon(icon, size: 20),
        const SizedBox(width: 9),
        Expanded(child: Text(title)),
        Text(time, style: const TextStyle(fontSize: 12)),
      ],
    ),
  );
}
