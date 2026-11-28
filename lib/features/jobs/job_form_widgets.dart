import 'package:material_ui/material_ui.dart';

import '../../shared/theme/jobmate_theme.dart';

class JobFormSection extends StatelessWidget {
  const JobFormSection({
    super.key,
    required this.title,
    required this.icon,
    required this.child,
    this.compact = false,
  });
  final String title;
  final IconData icon;
  final Widget child;
  final bool compact;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 16),
    child: Material(
      color: Colors.white,
      shape: RoundedRectangleBorder(
        side: const BorderSide(color: JobMateTheme.divider),
        borderRadius: BorderRadius.circular(14),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: EdgeInsets.symmetric(
              horizontal: compact ? 12 : 18,
              vertical: compact ? 6 : 12,
            ),
            decoration: const BoxDecoration(
              color: JobMateTheme.background,
              border: Border(bottom: BorderSide(color: JobMateTheme.divider)),
            ),
            child: Row(
              children: [
                Icon(icon, color: JobMateTheme.darkTeal, size: 20),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    title,
                    style: Theme.of(context).textTheme.titleSmall
                        ?.copyWith(fontWeight: FontWeight.w700),
                  ),
                ),
              ],
            ),
          ),
          Padding(padding: EdgeInsets.all(compact ? 12 : 18), child: child),
        ],
      ),
    ),
  );
}

class JobLabeledField extends StatelessWidget {
  const JobLabeledField({
    super.key,
    required this.label,
    required this.child,
    this.action,
  });
  final Widget label, child;
  final Widget? action;
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      if (action == null)
        label
      else
        Wrap(
          alignment: WrapAlignment.spaceBetween,
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: 12,
          runSpacing: 6,
          children: [label, action!],
        ),
      const SizedBox(height: 8),
      child,
    ],
  );
}
