import 'package:flutter/material.dart';

import '../../shared/widgets/mobile_back_action.dart';
import 'engagement_closure_controls.dart';
import 'work_assignment_creation_repository.dart';

/// Caller owns the repository. This dialog never creates on opening or retrying
/// reads; only the final, explicit confirmation dispatches a creation request.
class WorkAssignmentCreationDialog extends StatefulWidget {
  const WorkAssignmentCreationDialog({
    super.key,
    required this.repository,
    required this.companyId,
    required this.closureGateway,
    this.applicationId,
  });
  final WorkAssignmentCreationRepository repository;
  final String companyId;
  final EngagementClosureGateway closureGateway;

  /// Optional group context. Resolve only against freshly authorized candidates.
  final String? applicationId;

  @override
  State<WorkAssignmentCreationDialog> createState() =>
      _WorkAssignmentCreationDialogState();
}

class _WorkAssignmentCreationDialogState
    extends State<WorkAssignmentCreationDialog> {
  final _form = GlobalKey<FormState>();
  final _startDate = TextEditingController(),
      _startTime = TextEditingController();
  final _endTime = TextEditingController();
  TimeOfDay? _selectedStart, _selectedEnd;
  bool _validationRequested = false;
  final _location = TextEditingController();
  late final String? _actor = widget.repository.source.userId;
  WorkAssignmentCandidate? _candidate;
  String? _job;
  bool _confirm = false, _busy = false, _leaving = false, _closing = false;
  WorkAssignmentCreateResult? _result;
  Map<String, dynamic>? _engagementStatus;
  String? _engagementError;
  String? _engagementApplicationId;
  bool _engagementLoading = false;
  int _engagementRequest = 0;

  @override
  void initState() {
    super.initState();
    widget.repository.addListener(_changed);
    widget.repository.load(companyId: widget.companyId);
    if (widget.applicationId != null) {
      _loadEngagementStatus(widget.applicationId!);
    }
  }

  void _changed() {
    if (!mounted) return;
    if (widget.repository.source.userId != _actor) {
      _selectedStart = null;
      _selectedEnd = null;
      _validationRequested = false;
      _candidate = null;
      _job = null;
      _confirm = false;
      _result = null;
      for (final c in [_startDate, _startTime, _endTime, _location]) {
        c.clear();
      }
    } else if (!_confirm && !widget.repository.state.loading) {
      final rows = widget.repository.state.candidates;
      if (widget.applicationId != null) {
        final matches = rows.where(
          (c) => c.applicationId == widget.applicationId,
        );
        _candidate = matches.length == 1 ? matches.single : null;
        _job = _candidate?.jobId;
      } else {
        if (!rows.any((c) => c.jobId == _job)) _job = null;
        final selection = rows.where(
          (c) =>
              c.applicationId == _candidate?.applicationId && c.jobId == _job,
        );
        _candidate = selection.length == 1 ? selection.single : null;
      }
    }
    _ensureEngagementStatus(_candidate?.applicationId);
    setState(() {});
  }

  void _ensureEngagementStatus(String? applicationId) {
    if (_engagementApplicationId == applicationId) return;
    _engagementApplicationId = applicationId;
    if (applicationId == null) {
      _engagementStatus = null;
      _engagementError = null;
      _engagementLoading = false;
      ++_engagementRequest;
      return;
    }
    _loadEngagementStatus(applicationId);
  }

  Future<void> _loadEngagementStatus(String applicationId) async {
    final request = ++_engagementRequest;
    _engagementApplicationId = applicationId;
    if (mounted) {
      setState(() {
        _engagementStatus = null;
        _engagementError = null;
        _engagementLoading = true;
      });
    } else {
      _engagementStatus = null;
      _engagementError = null;
      _engagementLoading = true;
    }
    try {
      final status = await widget.closureGateway.status(applicationId);
      if (!mounted || request != _engagementRequest) return;
      setState(() {
        _engagementStatus = status;
        _engagementLoading = false;
      });
    } catch (_) {
      if (!mounted || request != _engagementRequest) return;
      setState(() {
        _engagementError = 'Unable to check engagement status. Retry before scheduling a shift.';
        _engagementLoading = false;
      });
    }
  }

  bool get _engagementClosed =>
      _engagementStatus?['closure_status'] == 'closed';

  bool get _engagementReady =>
      _candidate != null &&
      !_engagementLoading &&
      _engagementError == null &&
      _engagementStatus != null &&
      !_engagementClosed;

  @override
  void dispose() {
    widget.repository.removeListener(_changed);
    for (final c in [_startDate, _startTime, _endTime, _location]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _close([String? assignmentId]) async {
    if (_closing || _busy) return;
    _closing = true;
    final dirty =
        (_candidate != null && widget.applicationId == null) ||
        [
          _startDate,
          _startTime,
          _endTime,
          _location,
        ].any((c) => c.text.isNotEmpty);
    final leave =
        assignmentId != null || await confirmDiscardChanges(context, dirty);
    _closing = false;
    if (!mounted || !leave) return;
    setState(() => _leaving = true);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) Navigator.of(context).pop(assignmentId);
    });
  }

  String _clock(TimeOfDay? time) => time == null
      ? ''
      : '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}';

  String _friendly(TimeOfDay time) =>
      '${time.hourOfPeriod == 0 ? 12 : time.hourOfPeriod}:${time.minute.toString().padLeft(2, '0')} ${time.period == DayPeriod.am ? 'AM' : 'PM'}';

  DateTime? get _start =>
      workAssignmentMalaysiaUtc(_startDate.text, _clock(_selectedStart));
  DateTime? get _end =>
      workAssignmentMalaysiaUtc(_startDate.text, _clock(_selectedEnd));

  Future<void> _pickTime(bool start) async {
    if (_busy) return;
    final malaysia = DateTime.now().toUtc().add(const Duration(hours: 8));
    final chosen = await showTimePicker(
      context: context,
      initialTime:
          (start ? _selectedStart : _selectedEnd) ??
          TimeOfDay(hour: malaysia.hour, minute: malaysia.minute),
      initialEntryMode: TimePickerEntryMode.dial,
      builder: (context, child) => MediaQuery(
        // Material's fixed-size clock/input surfaces otherwise clip their
        // actions at large text scales on narrow screens. The outer form
        // retains the user's full text scaling and scrolls independently.
        data: MediaQuery.of(context).copyWith(
          alwaysUse24HourFormat: false,
          textScaler: MediaQuery.textScalerOf(context)
              .clamp(maxScaleFactor: 1.3),
        ),
        child: child!,
      ),
    );
    if (!mounted ||
        _busy ||
        widget.repository.source.userId != _actor ||
        chosen == null) {
      return;
    }
    setState(() {
      if (start) {
        _selectedStart = chosen;
        _startTime.text = _friendly(chosen);
      } else {
        _selectedEnd = chosen;
        _endTime.text = _friendly(chosen);
      }
      _result = null;
    });
  }

  Future<void> _pickDate(TextEditingController controller) async {
    if (_busy) return;
    final malaysia = DateTime.now().toUtc().add(const Duration(hours: 8));
    String two(int n) => n.toString().padLeft(2, '0');
    String? value;
    final existing = workAssignmentMalaysiaUtc(
      controller.text,
      '00:00',
    )?.add(const Duration(hours: 8));
    final chosen = await showDatePicker(
      context: context,
      initialDate:
          existing ?? DateTime(malaysia.year, malaysia.month, malaysia.day),
      firstDate: DateTime(1),
      lastDate: DateTime(9999, 12, 31),
    );
    if (chosen != null) {
      value =
          '${chosen.year.toString().padLeft(4, '0')}-${two(chosen.month)}-${two(chosen.day)}';
    }
    if (mounted &&
        !_busy &&
        widget.repository.source.userId == _actor &&
        value != null) {
      setState(() {
        controller.text = value!;
        _result = null;
      });
    }
  }

  Future<void> _submit({bool reconcile = false}) async {
    if (_busy ||
        (!reconcile && _result?.scheduleConflict == true) ||
        _candidate == null ||
        widget.repository.source.userId != _actor) {
      return;
    }
    final candidate = _candidate!;
    setState(() => _busy = true);
    if (!reconcile) {
      try {
        final latest = await widget.closureGateway.status(
          candidate.applicationId,
        );
        if (!mounted) return;
        if (widget.repository.source.userId != _actor) {
          setState(() => _busy = false);
          _changed();
          return;
        }
        setState(() {
          _engagementStatus = latest;
          _engagementApplicationId = _candidate!.applicationId;
          _engagementLoading = false;
          _engagementError = null;
        });
        if (_engagementClosed) {
          setState(() {
            _confirm = false;
            _busy = false;
            _result = const WorkAssignmentCreateResult(
              WorkAssignmentCreateStatus.rejected,
              'This job engagement has been closed. New shifts cannot be scheduled.',
              engagementClosed: true,
            );
          });
          return;
        }
      } catch (_) {
        if (!mounted) return;
        setState(() {
          _busy = false;
          _engagementLoading = false;
          _engagementError = 'Unable to check engagement status. Retry before scheduling a shift.';
        });
        return;
      }
    }
    final result = reconcile
        ? await widget.repository.reconcile(candidate)
        : await widget.repository.create(
            candidate: candidate,
            start: _start!,
            end: _end!,
            location: _location.text,
          );
    if (!mounted) return;
    setState(() {
      _busy = false;
      _result = result;
      if (result.retryableContention) _confirm = false;
    });
    if (result.retryableContention) {
      _changed();
      if (_candidate != null) {
        await _loadEngagementStatus(_candidate!.applicationId);
        if (!mounted) return;
      }
    }
    if (result.engagementClosed && _candidate != null) {
      await _loadEngagementStatus(_candidate!.applicationId);
      if (!mounted) return;
    }
    if (widget.repository.source.userId != _actor) {
      _changed();
      return;
    }
    if (result.status == WorkAssignmentCreateStatus.success) {
      await _close(result.assignmentId);
    }
  }

  @override
  Widget build(BuildContext context) {
    final repository = widget.repository;
    final state = repository.state;
    final accountChanged = repository.source.userId != _actor;
    final scoped = widget.applicationId != null;
    final unavailable = scoped && _candidate == null;
    final locked =
        _candidate != null &&
        [
          WorkAssignmentCreateStatus.uncertain,
          WorkAssignmentCreateStatus.submitting,
        ].contains(repository.statusFor(_candidate!));
    final jobs = {for (final c in state.candidates) c.jobId: c.jobTitle};
    Widget input(
      TextEditingController controller,
      String label,
      String? Function(String?) validate,
    ) => Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: TextFormField(
        controller: controller,
        enabled: !_busy,
        readOnly: controller == _startTime || controller == _endTime,
        onTap: controller == _startTime || controller == _endTime
            ? () => _pickTime(controller == _startTime)
            : null,
        keyboardType: controller == _location
            ? TextInputType.streetAddress
            : TextInputType.datetime,
        textInputAction: TextInputAction.next,
        decoration: InputDecoration(
          labelText: label,
          border: const OutlineInputBorder(),
          errorMaxLines: 3,
          suffixIcon: controller == _startDate
              ? IconButton(
                  tooltip: 'Choose $label',
                  onPressed: _busy ? null : () => _pickDate(controller),
                  icon: const Icon(Icons.calendar_today),
                )
              : controller == _startTime || controller == _endTime
              ? IconButton(
                  tooltip: 'Choose $label',
                  onPressed: _busy
                      ? null
                      : () => _pickTime(controller == _startTime),
                  icon: const Icon(Icons.access_time),
                )
              : null,
        ),
        validator: validate,
        onChanged: (_) => setState(() => _result = null),
      ),
    );
    String? date(String? value) =>
        workAssignmentMalaysiaUtc(value ?? '', '00:00') == null
        ? 'Use a valid date: YYYY-MM-DD.'
        : null;
    String? startTime(String? _) {
      if (_selectedStart == null) return 'Choose a start time.';
      final start = _start;
      if (start != null &&
          repository.validateSchedule(
                start,
                start.add(const Duration(seconds: 1)),
              ) ==
              'Shift start must be in the future.') {
        return 'This start time has already passed. Choose a later time or date.';
      }
      return null;
    }

    String? endTime(String? _) {
      if (_selectedEnd == null) return 'Choose an end time.';
      if (_start != null && _end != null && !_end!.isAfter(_start!)) {
        return 'End time must be later than start time.';
      }
      return null;
    }

    return PopScope(
      canPop: _leaving,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _close();
      },
      child: AlertDialog(
        title: Text(
          _confirm
              ? 'Confirm new assignment'
              : scoped
              ? 'Add shift'
              : 'Create Assignment',
        ),
        content: SizedBox(
          width: 520,
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.sizeOf(context).height * .60,
            ),
            child: SingleChildScrollView(
              child: accountChanged
                  ? const Text(
                      'Account changed. Close this dialog and sign in again.',
                    )
                  : Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        if (_busy)
                          const LinearProgressIndicator(
                            semanticsLabel: 'Creating or checking assignment',
                          ),
                        if (_candidate != null && _engagementLoading)
                          const LinearProgressIndicator(
                            semanticsLabel: 'Checking engagement status',
                          ),
                        if (_candidate != null && _engagementError != null) ...[
                          Text(_engagementError!),
                          TextButton(
                            onPressed: _busy
                                ? null
                                : () => _loadEngagementStatus(
                                    _candidate!.applicationId,
                                  ),
                            child: const Text('Retry engagement status'),
                          ),
                        ],
                        if (_candidate != null && _engagementClosed)
                          const Text(
                            'This job engagement has been closed. New shifts cannot be scheduled.',
                          ),
                        if (_result != null)
                          Semantics(
                            liveRegion: true,
                            child: Text(_result!.message),
                          ),
                        if (_result?.scheduleConflict == true)
                          const Text(
                            'Creation is blocked for this schedule. Choose Edit to change the dates or times, then review again, or Close.',
                          ),
                        if (locked && !_confirm)
                          const Text(
                            'An earlier creation is unresolved. Check its existing request before scheduling another shift for this application. This check does not create a shift.',
                          ),
                        if (_confirm && _candidate != null) ...[
                          Text('Company: ${_candidate!.companyName}'),
                          Text('Job: ${_candidate!.jobTitle}'),
                          Text('Worker: ${_candidate!.applicantName}'),
                          Text(
                            'Start (MYT): ${_startDate.text} ${_startTime.text}',
                          ),
                          Text(
                            'End (MYT): ${_startDate.text} ${_endTime.text}',
                          ),
                          Text('Workplace: ${_location.text.trim()}'),
                          const SizedBox(height: 12),
                          const Text(
                            'Confirming creates a real assignment. Existing assignments are not edited. If the result is uncertain, check assignments before taking any further action.',
                          ),
                        ] else if (state.loading)
                          const Center(child: CircularProgressIndicator())
                        else if (state.error != null) ...[
                          Text(state.error!),
                          TextButton(
                            onPressed: () =>
                                repository.load(companyId: widget.companyId),
                            child: const Text('Retry loading applications'),
                          ),
                        ] else if (unavailable)
                          const Text(
                            'This hired application is no longer available for scheduling. Close and refresh the assignments.',
                          )
                        else if (state.candidates.isEmpty)
                          const Text(
                            'No eligible hired applications. Hired workers can receive additional non-overlapping shifts.',
                          )
                        else
                          Form(
                            key: _form,
                            autovalidateMode: _validationRequested
                                ? AutovalidateMode.always
                                : AutovalidateMode.disabled,
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                const _BeforeSchedulingNotice(),
                                const SizedBox(height: 16),
                                if (_candidate != null) ...[
                                  Text(
                                    'Job: ${_candidate!.jobTitle}',
                                    style: Theme.of(context)
                                        .textTheme
                                        .titleSmall,
                                  ),
                                  Text('Company: ${_candidate!.companyName}'),
                                  Text('Worker: ${_candidate!.applicantName}'),
                                  const SizedBox(height: 16),
                                ],
                                if (!scoped) ...[
                                  DropdownButtonFormField<String>(
                                    initialValue: _job,
                                    isExpanded: true,
                                    decoration: const InputDecoration(
                                      labelText: 'Company job',
                                    ),
                                    items: jobs.entries
                                        .map(
                                          (j) => DropdownMenuItem(
                                            value: j.key,
                                            child: Text(
                                              j.value,
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                          ),
                                        )
                                        .toList(),
                                    onChanged: _busy
                                        ? null
                                        : (value) => setState(() {
                                            _job = value;
                                            _candidate = null;
                                            _result = null;
                                          }),
                                    validator: (v) =>
                                        v == null ? 'Select a job.' : null,
                                  ),
                                  const SizedBox(height: 12),
                                  DropdownButtonFormField<String>(
                                    key: ValueKey(_job),
                                    initialValue: _candidate?.applicationId,
                                    isExpanded: true,
                                    decoration: const InputDecoration(
                                      labelText: 'Hired application',
                                    ),
                                    items: state.candidates
                                        .where((c) => c.jobId == _job)
                                        .map(
                                          (c) => DropdownMenuItem(
                                            value: c.applicationId,
                                            child: Text(
                                              c.applicantName,
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                          ),
                                        )
                                        .toList(),
                                    onChanged: _busy
                                        ? null
                                        : (value) {
                                            setState(() {
                                              _candidate = state.candidates
                                                  .singleWhere(
                                                    (c) =>
                                                        c.applicationId ==
                                                        value,
                                                  );
                                              _result = null;
                                            });
                                            _ensureEngagementStatus(
                                              _candidate?.applicationId,
                                            );
                                          },
                                    validator: (v) => _candidate == null
                                        ? 'Select a hired application.'
                                        : null,
                                  ),
                                ],
                                const SizedBox(height: 16),

                                input(_startDate, 'Shift date (MYT)', date),
                                input(
                                  _startTime,
                                  'Start time (MYT)',
                                  startTime,
                                ),
                                input(_endTime, 'End time (MYT)', endTime),
                                input(
                                  _location,
                                  'Workplace location',
                                  (v) => v == null || v.trim().isEmpty
                                      ? 'Enter a workplace location.'
                                      : v.runes.length > 500
                                      ? 'Use no more than 500 characters.'
                                      : null,
                                ),
                              ],
                            ),
                          ),
                      ],
                    ),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: _busy ? null : () => _close(),
            child: const Text('Close'),
          ),
          if (!accountChanged && _confirm && !locked)
            TextButton(
              onPressed: _busy
                  ? null
                  : () {
                      _confirm = false;
                      _result = null;
                      _changed();
                    },
              child: const Text('Edit'),
            ),
          if (!accountChanged && locked)
            OutlinedButton(
              onPressed: _busy ? null : () => _submit(reconcile: true),
              child: const Text('Check current assignment'),
            ),
          if (!accountChanged &&
              !locked &&
              !_engagementClosed &&
              _engagementError == null &&
              !_engagementLoading &&
              state.error == null &&
              !state.loading &&
              !unavailable &&
              !(_confirm && _result?.scheduleConflict == true) &&
              (_confirm || state.candidates.isNotEmpty))
            FilledButton(
              onPressed: _busy
                  ? null
                  : () {
                      if (_confirm) {
                        _submit();
                        return;
                      }
                      setState(() => _validationRequested = true);
                      if (!_form.currentState!.validate()) return;
                      if (!_engagementReady) return;
                      if (_start == null || _end == null) return;
                      final scheduleError = widget.repository.validateSchedule(
                        _start!,
                        _end!,
                      );
                      if (scheduleError != null) {
                        setState(
                          () => _result = WorkAssignmentCreateResult(
                            WorkAssignmentCreateStatus.rejected,
                            scheduleError,
                          ),
                        );
                        return;
                      }
                      setState(() => _confirm = true);
                    },
              child: Text(_confirm ? 'Confirm creation' : 'Review assignment'),
            ),
        ],
      ),
    );
  }
}

class _BeforeSchedulingNotice extends StatelessWidget {
  const _BeforeSchedulingNotice();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // Use Material amber tones matched to theme brightness, not fixed light colors.
    final amber = ColorScheme.fromSeed(
      seedColor: Colors.amber,
      brightness: theme.brightness,
    );
    return Semantics(
      container: true,
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: amber.primaryContainer,
          border: Border.all(color: amber.primary.withValues(alpha: 0.35)),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ExcludeSemantics(
              child: Icon(Icons.info_outline, color: amber.onPrimaryContainer),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: DefaultTextStyle(
                style: theme.textTheme.bodySmall!.copyWith(
                  color: amber.onPrimaryContainer,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Before you schedule',
                      style: theme.textTheme.titleSmall!.copyWith(
                        color: amber.onPrimaryContainer,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 4),
                    const Text(
                      'The shift must start in the future and finish on the same calendar day (Malaysia time).',
                    ),
                    const SizedBox(height: 4),
                    const Text(
                      'For overnight work, create a separate shift for the next day.',
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
