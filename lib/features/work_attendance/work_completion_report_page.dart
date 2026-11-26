import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../shared/widgets/app_workspace.dart';
import '../../shared/theme/jobmate_theme.dart';
import '../../shared/widgets/mobile_back_action.dart';
import '../applications/module2_widgets.dart';
import 'work_completion_report_data.dart';
import 'work_completion_report_document.dart';
import 'work_completion_report_export.dart';
import 'work_completion_report_format.dart';
import 'work_completion_report_pdf.dart';
import 'work_completion_report_repository.dart';

class WorkCompletionReportPage extends StatefulWidget {
  const WorkCompletionReportPage({
    super.key,
    required this.assignmentId,
    required this.repository,
    required this.fallback,
    this.employer = false,
    this.pdfPlatform,
    this.renderPdf = renderWorkCompletionReportPdf,
  });

  final String assignmentId;
  final WorkCompletionReportRepository repository;
  final String fallback;
  final bool employer;
  final ReportPdfPlatform? pdfPlatform;
  final Future<Uint8List> Function(WorkCompletionReportData) renderPdf;

  @override
  State<WorkCompletionReportPage> createState() =>
      _WorkCompletionReportPageState();
}

class _WorkCompletionReportPageState extends State<WorkCompletionReportPage> {
  StreamSubscription<void>? _changes;
  WorkCompletionReportResult? _result;
  ReportReadScope? _reportScope;
  int _request = 0;
  ReportPdfTarget? _target;
  ReportPdfAction? _preparing;
  final _feedback = GlobalKey<ScaffoldMessengerState>();
  ReportPdfPlatform get _platform => widget.pdfPlatform ?? reportPdfPlatform;

  @override
  void initState() {
    super.initState();
    _subscribe();
    _load();
  }

  @override
  void didUpdateWidget(WorkCompletionReportPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.repository != widget.repository) _subscribe();
    if (oldWidget.repository != widget.repository ||
        oldWidget.assignmentId != widget.assignmentId ||
        oldWidget.employer != widget.employer) {
      _load();
    }
  }

  void _subscribe() {
    unawaited(_changes?.cancel());
    _changes = widget.repository.source.scopeChanges.listen(
      (_) => _invalidate(),
      onError: (Object _) => _invalidate(),
    );
  }

  void _invalidate() {
    if (!mounted) return;
    ++_request;
    _cancelExport();
    _feedback.currentState?.removeCurrentSnackBar();
    setState(() {
      _reportScope = null;
      _result = const WorkCompletionReportUnavailable(
        WorkCompletionReportFailure.unavailable,
      );
    });
  }

  Future<void> _load() async {
    _cancelExport();
    _feedback.currentState?.removeCurrentSnackBar();
    final request = ++_request;
    final assignmentId = widget.assignmentId;
    final repository = widget.repository;
    final scope = repository.source.scope;
    setState(() {
      _reportScope = scope;
      _result = null;
    });
    final result = await _read(repository, assignmentId);
    if (!mounted || request != _request) return;
    if (scope != repository.source.scope) {
      _invalidate();
      return;
    }
    setState(() => _result = result);
  }

  Future<WorkCompletionReportResult> _read(
    WorkCompletionReportRepository repository,
    String assignmentId,
  ) async {
    try {
      return await repository.load(assignmentId);
    } on Exception {
      return const WorkCompletionReportUnavailable(
        WorkCompletionReportFailure.retry,
      );
    }
  }

  void _cancelExport() {
    final target = _target;
    _target = null;
    _preparing = null;
    target?.cancel();
  }

  void _showExportError(String message) {
    _feedback.currentState
      ?..removeCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _export(ReportPdfAction action) async {
    final repository = widget.repository;
    final scope = repository.source.scope;
    if (_target != null ||
        _result is! WorkCompletionReportReady ||
        scope != _reportScope ||
        ModalRoute.of(context)?.isCurrent == false) {
      return;
    }
    // Reserve before the first await so browser popup policies see the gesture.
    ReportPdfTarget? target;
    try {
      target = _platform.reserve(action);
    } catch (_) {
      _showExportError('Unable to start PDF export. Please try again.');
      return;
    }
    if (target == null) {
      _showExportError(
        'The browser blocked the PDF tab. Allow popups or use Download PDF.',
      );
      return;
    }
    final request = ++_request;
    final assignmentId = widget.assignmentId;
    final employer = widget.employer;
    final route = ModalRoute.of(context);
    bool ownsRequest() => mounted && request == _request;
    bool isCurrent() =>
        ownsRequest() &&
        repository == widget.repository &&
        scope == repository.source.scope &&
        assignmentId == widget.assignmentId &&
        employer == widget.employer &&
        route?.isCurrent != false;
    setState(() {
      _target = target;
      _preparing = action;
    });
    _feedback.currentState?.removeCurrentSnackBar();
    try {
      final refreshed = await _read(repository, assignmentId);
      if (!isCurrent()) return;
      setState(() => _result = refreshed);
      if (refreshed is! WorkCompletionReportReady) return;
      final bytes = await widget.renderPdf(refreshed.data);
      if (!isCurrent()) return;
      await target.deliver(
        bytes,
        WorkReportFormat(refreshed.data).filename,
        isCurrent,
      );
    } on WorkReportPdfFontException {
      if (isCurrent()) {
        _showExportError(
          'The PDF font cannot display some characters in this report. You can still read the report here.',
        );
      }
    } catch (_) {
      if (isCurrent()) {
        _showExportError(
          'Unable to complete the PDF action. Please try again or choose another PDF action.',
        );
      }
    } finally {
      if (ownsRequest()) {
        if (scope != repository.source.scope) {
          _invalidate();
        } else {
          setState(_cancelExport);
        }
      }
    }
  }

  @override
  void dispose() {
    ++_request;
    _cancelExport();
    unawaited(_changes?.cancel());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final result = _reportScope == widget.repository.source.scope
        ? _result
        : const WorkCompletionReportUnavailable(
            WorkCompletionReportFailure.unavailable,
          );
    return PopScope(
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) _invalidate();
      },
      child: ScaffoldMessenger(
        key: _feedback,
        child: AppWorkspace(
          title: 'Work Completion Report',
          path: widget.fallback,
          role: widget.employer ? 'employer' : 'job_seeker',
          focused: true,
          leading: MobileBackAction(fallback: widget.fallback),
          child: ColoredBox(
            color: const Color(0xFFE2E8F0),
            child: LayoutBuilder(
              builder: (context, constraints) {
                final margin = constraints.maxWidth >= 840 ? 32.0 : 12.0;
                return SingleChildScrollView(
                  key: const PageStorageKey('work-report-preview-scroll'),
                  padding: EdgeInsets.fromLTRB(margin, 12, margin, 32),
                  child: Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 960),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          _toolbar(
                            context,
                            result is WorkCompletionReportReady,
                          ),
                          const SizedBox(height: 12),
                          if (result is WorkCompletionReportReady)
                            WorkCompletionReportDocument(data: result.data)
                          else
                            Card(
                              color: result == null ? Colors.white : null,
                              key: result == null
                                  ? const ValueKey('work-report-loading-panel')
                                  : null,
                              margin: EdgeInsets.zero,
                              child: Padding(
                                padding: const EdgeInsets.all(20),
                                child: Semantics(
                                  liveRegion: true,
                                  child: result == null
                                      ? _loadingPanel(context)
                                      : _failure(
                                          (result as WorkCompletionReportUnavailable)
                                              .reason,
                                        ),
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ),
      ),
    );
  }

  Widget _loadingPanel(BuildContext context) => ConstrainedBox(
    constraints: BoxConstraints(
      minHeight: MediaQuery.sizeOf(context).width >= 600 ? 188 : 160,
    ),
    child: Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const CircularProgressIndicator(
            color: JobMateTheme.darkTeal,
            semanticsLabel: 'Loading work report',
          ),
          const SizedBox(height: 16),
          Text(
            'Loading report...',
            style: Theme.of(context).textTheme.titleMedium
                ?.copyWith(color: JobMateTheme.heading),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 4),
          const Text(
            'Retrieving attendance and work verification records.',
            style: TextStyle(color: JobMateTheme.body),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    ),
  );

  Widget _toolbar(BuildContext context, bool ready) => LayoutBuilder(
    builder: (context, constraints) {
      final navigation = Wrap(
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: 8,
        children: [
          TextButton.icon(
            onPressed: () {
              _invalidate();
              returnToPage(context, widget.fallback);
            },
            icon: const Icon(LucideIcons.arrowLeft, size: 16),
            label: const Text('Back'),
          ),
          const Text(
            'Report preview',
            style: TextStyle(color: Color(0xFF475569)),
          ),
        ],
      );
      if (!ready) return navigation;
      final actions = Wrap(
        spacing: 8,
        runSpacing: 6,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          TextButton.icon(
            onPressed: _target == null ? _load : null,
            icon: const Icon(LucideIcons.refreshCw, size: 16),
            label: const Text('Refresh'),
          ),
          for (final action in _platform.actions) _exportButton(action),
        ],
      );
      final scale = MediaQuery.textScalerOf(context).scale(14) / 14;
      return constraints.maxWidth >= 625 * scale
          ? Row(
              children: [
                Expanded(flex: 2, child: navigation),
                const SizedBox(width: 12),
                Flexible(
                  flex: 5,
                  child: Align(
                    alignment: AlignmentDirectional.centerEnd,
                    child: actions,
                  ),
                ),
              ],
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [navigation, actions],
            );
    },
  );

  Widget _exportButton(ReportPdfAction action) {
    final onPressed = _target == null ? () => _export(action) : null;
    final active = _preparing == action;
    final filled =
        action == ReportPdfAction.download || action == ReportPdfAction.share;
    final color = filled ? Colors.white : JobMateTheme.darkTeal;
    final icon = active
        ? SizedBox.square(
            dimension: 16,
            child: CircularProgressIndicator(strokeWidth: 2, color: color),
          )
        : Icon(switch (action) {
            ReportPdfAction.open => LucideIcons.externalLink,
            ReportPdfAction.download => LucideIcons.download,
            ReportPdfAction.share => LucideIcons.share2,
            ReportPdfAction.print => LucideIcons.printer,
          }, size: 16);
    const preparing = 'Preparing PDF...';
    final label = IndexedStack(
      alignment: Alignment.center,
      index: active ? 1 : 0,
      children: [
        Text(action.label),
        Semantics(
          liveRegion: true,
          label: '${action.label}: $preparing',
          excludeSemantics: true,
          child: const Text(preparing),
        ),
      ],
    );
    return filled
        ? FilledButton.icon(
            onPressed: onPressed,
            icon: icon,
            label: label,
            style: active
                ? FilledButton.styleFrom(
                    disabledBackgroundColor: JobMateTheme.darkTeal,
                    disabledForegroundColor: color,
                  )
                : null,
          )
        : OutlinedButton.icon(
            onPressed: onPressed,
            icon: icon,
            label: label,
            style: active
                ? OutlinedButton.styleFrom(
                    disabledForegroundColor: color,
                    side: const BorderSide(color: JobMateTheme.darkTeal),
                  )
                : null,
          );
  }

  Widget _failure(WorkCompletionReportFailure reason) {
    final (title, message) = switch (reason) {
      WorkCompletionReportFailure.ineligible => (
        'Report not available yet',
        'This work assignment must be completed and verified before a report can be generated.',
      ),
      WorkCompletionReportFailure.unavailable => (
        'Report unavailable',
        'You do not have access to this report, or the record is no longer available.',
      ),
      WorkCompletionReportFailure.incomplete => (
        'Report unavailable for this record',
        'The recorded assignment information could not be confirmed. Please try again later.',
      ),
      WorkCompletionReportFailure.retry => (
        'Unable to load report',
        'Check your connection and try again.',
      ),
    };
    return ModuleState(
      title: title,
      message: message,
      action: _load,
      actionLabel: 'Retry',
    );
  }
}
