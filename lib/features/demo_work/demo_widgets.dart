import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../shared/widgets/app_workspace.dart';
import '../../shared/navigation/app_routes.dart';
import '../../shared/widgets/design_primitives.dart';
import '../applications/module2_widgets.dart';

class Phase3Notice extends StatelessWidget {
  const Phase3Notice(this.message, {super.key});
  final String message;
  @override
  Widget build(BuildContext context) => PreviewNotice(message);
}

class DemoPage extends StatelessWidget {
  const DemoPage({
    super.key,
    required this.title,
    required this.path,
    required this.role,
    required this.children,
    this.back,
    this.maxWidth,
    this.sidebar = const [],
  });
  final String title, path, role;
  final List<Widget> children;
  final List<Widget> sidebar;
  final String? back;
  final double? maxWidth;
  @override
  Widget build(BuildContext context) => AppWorkspace(
    title: title,
    path: path,
    role: role,
    focused: back != null,
    leading: back != null && !kIsWeb
        ? BackButton(onPressed: () => moduleBack(context, back!))
        : null,
    child: WorkspaceContent(
      maxWidth:
          maxWidth ??
          (role == 'administrator'
              ? 896
              : path == AppRoutes.attendanceReview
              ? 768
              : 672),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (back != null && kIsWeb)
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: () => moduleBack(context, back!),
                icon: kIsWeb ? null : const Icon(Icons.arrow_back),
                label: const Text('Back'),
              ),
            ),
          PageHeading(title: title, description: ''),
          if (sidebar.isEmpty)
            ...children
          else
            LayoutBuilder(
              builder: (context, box) {
                final main = Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: children,
                );
                final side = Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: sidebar,
                );
                return box.maxWidth >= 900
                    ? Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(flex: 2, child: main),
                          const SizedBox(width: 16),
                          Expanded(child: side),
                        ],
                      )
                    : Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [main, const SizedBox(height: 20), side],
                      );
              },
            ),
        ],
      ),
    ),
  );
}

void demoMessage(BuildContext context, String message) =>
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));

Future<bool> demoConfirm(
  BuildContext context,
  String title,
  String message,
) async =>
    await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: Text(
          '$message\n\nDEMO ONLY: this changes session state, not a server record.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Confirm demo action'),
          ),
        ],
      ),
    ) ==
    true;

String demoTime(DateTime? value) => value == null
    ? 'Not recorded'
    : '${value.hour.toString().padLeft(2, '0')}:${value.minute.toString().padLeft(2, '0')}';
String demoDuration(Duration value) =>
    '${value.inHours}h ${value.inMinutes.remainder(60)}m ${value.inSeconds.remainder(60)}s';

class DemoStats extends StatelessWidget {
  const DemoStats(this.values, {super.key});
  final Map<String, int> values;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 20),
    child: StatGrid(
      children: [
        for (final v in values.entries)
          StatTile(
            label: v.key,
            value: '${v.value}',
            icon: Icons.insights_outlined,
            note: 'Demo records',
          ),
      ],
    ),
  );
}
