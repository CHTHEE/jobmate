import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';

import '../../shared/navigation/app_page.dart';
import 'job_form_page.dart';
import 'job_form_result.dart';
import 'job_postings_repository.dart';
import 'workplace_map_picker.dart';

const _dialogEntry = 'job-list';

Future<JobFormResult?> openJobFormDialog(BuildContext context, String path) =>
    context.push<JobFormResult>(path, extra: _dialogEntry);

/// A pushed route instance owns its form key and exit guard. A second Create
/// Job route must never reuse the key of a form still below it in the stack.
GoRoute jobFormRoute(
  String path, {
  JobPostingsRepository? repository,
  WorkplacePicker pickWorkplace = showWorkplacePicker,
}) {
  final guards = <LocalKey, Future<bool> Function()>{};
  return GoRoute(
    path: path,
    onExit: (_, state) async => await guards[state.pageKey]?.call() ?? true,
    pageBuilder: (_, state) {
      final dialog = state.extra == _dialogEntry;
      final body = _JobFormRouteBody(
        key: ValueKey(
          '${state.pageKey.value}:${state.pathParameters['jobId'] ?? ''}',
        ),
        routeKey: state.pageKey,
        guards: guards,
        repository: repository,
        pickWorkplace: pickWorkplace,
        jobId: state.pathParameters['jobId'],
        dialog: dialog,
      );
      return dialog
          ? _JobFormDialogPage(key: state.pageKey, child: body)
          : appPage(state, body);
    },
  );
}

class _JobFormDialogPage extends Page<JobFormResult> {
  const _JobFormDialogPage({required super.key, required this.child});
  final Widget child;

  @override
  Route<JobFormResult> createRoute(BuildContext context) =>
      DialogRoute<JobFormResult>(
        context: context,
        settings: this,
        barrierDismissible: false,
        animationStyle: MediaQuery.disableAnimationsOf(context)
            ? AnimationStyle.noAnimation
            : const AnimationStyle(
                duration: Duration(milliseconds: 160),
                reverseDuration: Duration(milliseconds: 120),
              ),
        builder: (_) => child,
      );
}

class _JobFormRouteBody extends StatefulWidget {
  const _JobFormRouteBody({
    super.key,
    required this.routeKey,
    required this.guards,
    required this.pickWorkplace,
    this.repository,
    this.jobId,
    required this.dialog,
  });

  final LocalKey routeKey;
  final Map<LocalKey, Future<bool> Function()> guards;
  final JobPostingsRepository? repository;
  final WorkplacePicker pickWorkplace;
  final String? jobId;
  final bool dialog;

  @override
  State<_JobFormRouteBody> createState() => _JobFormRouteBodyState();
}

class _JobFormRouteBodyState extends State<_JobFormRouteBody> {
  final _formKey = GlobalKey<JobFormPageState>();

  Future<bool> _confirmExit() async =>
      await _formKey.currentState?.confirmExit() ?? true;

  @override
  void initState() {
    super.initState();
    widget.guards[widget.routeKey] = _confirmExit;
  }

  @override
  void dispose() {
    if (widget.guards[widget.routeKey] == _confirmExit) {
      widget.guards.remove(widget.routeKey);
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final form = JobFormPage(
      key: _formKey,
      repository: widget.repository,
      pickWorkplace: widget.pickWorkplace,
      jobId: widget.jobId,
      dialog: widget.dialog,
    );
    if (!widget.dialog) return form;
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.escape): () {
          // The form's PopScope owns busy and unsaved-change handling.
          Navigator.of(context).maybePop();
        },
      },
      child: Focus(autofocus: true, child: form),
    );
  }
}
