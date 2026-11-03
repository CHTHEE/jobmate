import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../shared/navigation/app_routes.dart';
import '../../shared/theme/jobmate_theme.dart';
import '../../shared/widgets/app_workspace.dart';
import '../../shared/widgets/design_primitives.dart';
import '../../shared/widgets/mobile_back_action.dart';
import '../../shared/widgets/responsive_layout.dart';
import 'module2_repository.dart';

class Module2Gate extends StatefulWidget {
  const Module2Gate({
    super.key,
    required this.role,
    required this.child,
    this.checkAccess,
  });
  final String role;
  final Widget child;
  final Future<bool> Function()? checkAccess;
  @override
  State<Module2Gate> createState() => _Module2GateState();
}

class _Module2GateState extends State<Module2Gate> {
  late Future<bool> access = load();
  Future<bool> load() async {
    if (widget.checkAccess != null) return widget.checkAccess!();
    final client = Supabase.instance.client;
    final id = client.auth.currentUser?.id;
    if (id == null) return false;
    final account = await client
        .from('users')
        .select('role, status')
        .eq('user_id', id)
        .single();
    return client.auth.currentUser?.id == id &&
        account['role'] == widget.role &&
        account['status'] == 'active';
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<bool>(
    future: access,
    builder: (context, snapshot) {
      if (snapshot.data == true) return widget.child;
      return Scaffold(
        appBar: const ResponsivePageAppBar(
          title: Text('JobMate'),
          showReturnAction: false,
        ),
        body: Center(
          child: SingleChildScrollView(
            child: Padding(
              padding: ResponsiveLayout.pagePadding(context),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  snapshot.connectionState != ConnectionState.done
                      ? const CircularProgressIndicator()
                      : ModuleState(
                          title: snapshot.hasError
                              ? 'Unable to check access'
                              : 'Page unavailable',
                          message: snapshot.hasError
                              ? 'Check your connection and retry.'
                              : 'An active ${widget.role.replaceAll('_', ' ')} account is required.',
                          action: snapshot.hasError
                              ? () => setState(() {
                                  access = load();
                                })
                              : () => context.go(AppRoutes.home),
                          actionLabel: snapshot.hasError
                              ? 'Retry'
                              : 'Dashboard',
                        ),
                  TextButton(
                    onPressed: () => context.go(AppRoutes.home),
                    child: const Text('Back to Dashboard'),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    },
  );
}

class DemoNotice extends StatelessWidget {
  const DemoNotice({super.key});
  @override
  Widget build(BuildContext context) => const PreviewNotice(
    'Fictional jobs, companies, profiles and applications. No real application is sent or resume shared.',
  );
}

class ModuleState extends StatelessWidget {
  const ModuleState({
    super.key,
    required this.title,
    required this.message,
    this.action,
    this.actionLabel = 'Retry',
  });
  final String title, message, actionLabel;
  final VoidCallback? action;
  @override
  Widget build(BuildContext context) => WorkspaceCard(
    title: title,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(message),
        if (action != null) ...[
          const SizedBox(height: 16),
          OutlinedButton(onPressed: action, child: Text(actionLabel)),
        ],
      ],
    ),
  );
}

class StageBadge extends StatelessWidget {
  const StageBadge(this.stage, {super.key});
  final ApplicationStage stage;
  @override
  Widget build(BuildContext context) {
    final color = switch (stage) {
      ApplicationStage.rejected => Colors.red.shade800,
      ApplicationStage.withdrawn => Colors.blueGrey.shade700,
      ApplicationStage.offered => const Color(0xFF7E22CE),
      ApplicationStage.applied => const Color(0xFF1D4ED8),
      ApplicationStage.shortlisted => const Color(0xFFB45309),
      ApplicationStage.interview => JobMateTheme.teal,
      ApplicationStage.hired => const Color(0xFF15803D),
    };
    return Chip(
      label: Text(
        stage.label,
        style: TextStyle(
          color: color,
          fontSize: 11,
          fontWeight: FontWeight.w500,
        ),
      ),
      side: BorderSide(color: color.withValues(alpha: .15)),
      visualDensity: VisualDensity.compact,
      backgroundColor: color.withValues(alpha: .07),
    );
  }
}

class ModuleSelect extends StatelessWidget {
  const ModuleSelect({
    super.key,
    required this.label,
    required this.value,
    required this.options,
    required this.onChanged,
  });
  final String label, value;
  final Map<String, String> options;
  final ValueChanged<String> onChanged;
  @override
  Widget build(BuildContext context) => ResponsiveFilter(
    child: DropdownButtonFormField<String>(
      key: ValueKey('$label:$value'),
      initialValue: value,
      isExpanded: true,
      decoration: InputDecoration(labelText: label),
      items: options.entries
          .map(
            (e) => DropdownMenuItem(
              value: e.key,
              child: Text(e.value, overflow: TextOverflow.ellipsis),
            ),
          )
          .toList(),
      onChanged: (v) {
        if (v != null) onChanged(v);
      },
    ),
  );
}

Future<T?> moduleModal<T>(
  BuildContext context,
  Widget child, {
  double maxWidth = 448,
  double heightFraction = .85,
}) {
  if (ResponsiveLayout.isCompact(context)) {
    return showModalBottomSheet<T>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      isDismissible: false,
      enableDrag: false,
      builder: (_) => FractionallySizedBox(heightFactor: .94, child: child),
    );
  }
  return showDialog<T>(
    context: context,
    barrierDismissible: false,
    builder: (_) => Dialog(
      child: SizedBox(
        width: maxWidth,
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.sizeOf(context).height * heightFraction,
          ),
          child: child,
        ),
      ),
    ),
  );
}

class ModalBody extends StatelessWidget {
  const ModalBody({
    super.key,
    required this.title,
    required this.children,
    required this.actions,
  });
  final String title;
  final List<Widget> children, actions;
  @override
  Widget build(BuildContext context) => SafeArea(
    child: Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(title, style: Theme.of(context).textTheme.headlineMedium),
            const SizedBox(height: 20),
            ...children,
            const SizedBox(height: 24),
            Wrap(spacing: 12, runSpacing: 12, children: actions),
          ],
        ),
      ),
    ),
  );
}

void moduleBack(BuildContext context, String fallback) {
  if (context.canPop()) {
    context.pop();
  } else {
    context.go(fallback);
  }
}
