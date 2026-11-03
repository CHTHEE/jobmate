import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../shared/widgets/app_workspace.dart';
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
  });
  final String title, path, role;
  final List<Widget> children;
  final String? back;
  @override
  Widget build(BuildContext context) => AppWorkspace(
    title: title,
    path: path,
    role: role,
    leading: back != null && !kIsWeb
        ? BackButton(onPressed: () => moduleBack(context, back!))
        : null,
    child: WorkspaceContent(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (back != null)
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: () => moduleBack(context, back!),
                icon: const Icon(Icons.arrow_back),
                label: const Text('Back'),
              ),
            ),
          PageHeading(
            title: title,
            description: '',
            eyebrow: role == 'employer'
                ? 'Hiring workspace'
                : role == 'administrator'
                ? 'Administration'
                : 'Your workspace',
          ),
          ...children,
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
    child: Wrap(
      spacing: 12,
      runSpacing: 12,
      children: [
        for (final v in values.entries)
          SizedBox(
            width: 180,
            child: WorkspaceCard(
              title: '${v.value}',
              subtitle: v.key,
              child: const Text('Demo records'),
            ),
          ),
      ],
    ),
  );
}
