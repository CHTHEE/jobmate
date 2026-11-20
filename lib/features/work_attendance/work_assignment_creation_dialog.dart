import 'package:flutter/material.dart';

import '../../shared/theme/jobmate_theme.dart';
import '../../shared/widgets/mobile_back_action.dart';
import '../jobs/workplace_coordinates.dart';
import '../jobs/workplace_map_picker.dart';
import 'engagement_closure_controls.dart';
import 'work_assignment_creation_repository.dart';
import 'work_shift_ui.dart';

/// Caller owns the repository. This dialog never creates on opening or retrying
/// reads; only the final, explicit confirmation dispatches a creation request.
class WorkAssignmentCreationDialog extends StatefulWidget {
  const WorkAssignmentCreationDialog({
    super.key,
    required this.repository,
    required this.companyId,
    required this.closureGateway,
    this.applicationId,
    this.pickWorkplace = showWorkplacePicker,
  });
  final WorkAssignmentCreationRepository repository;
  final String companyId;
  final EngagementClosureGateway closureGateway;
  final WorkplacePicker pickWorkplace;

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
  String _workplaceDefault = '';
  String _draftAddress = '';
  WorkplaceCoordinates? _workplacePin, _defaultPin;
  WorkplaceCoordinates? _previousWorkplacePin;
  int _workplaceRevision = 0;
  bool _pickingWorkplace = false;
  late final String? _actor = widget.repository.source.userId;
  WorkAssignmentCandidate? _candidate;
  String? _job;
  bool _confirm = false, _busy = false, _leaving = false, _closing = false;
  bool _reconciling = false;
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
      _setCandidate(null);
      _workplaceDefault = '';
      _draftAddress = '';
      _workplacePin = _defaultPin = null;
      _previousWorkplacePin = null;
      _workplaceRevision++;
      _job = null;
      _confirm = false;
      _result = null;
      for (final c in [_startDate, _startTime, _endTime, _location]) {
        c.clear();
      }
    } else if (!_confirm &&
        !widget.repository.state.loading &&
        widget.repository.state.errorKind == null) {
      final rows = widget.repository.state.candidates;
      if (widget.applicationId != null) {
        final matches = rows.where(
          (c) => c.applicationId == widget.applicationId,
        );
        _setCandidate(matches.length == 1 ? matches.single : null);
        _job = _candidate?.jobId;
      } else {
        if (!rows.any((c) => c.jobId == _job)) _job = null;
        final selection = rows.where(
          (c) =>
              c.applicationId == _candidate?.applicationId && c.jobId == _job,
        );
        _setCandidate(selection.length == 1 ? selection.single : null);
      }
    }
    _ensureEngagementStatus(_candidate?.applicationId);
    setState(() {});
  }

  void _setCandidate(WorkAssignmentCandidate? candidate) {
    // A refresh can replace the candidate object for the same application.
    // Keep the current shift draft until the selected application changes.
    if (_candidate?.applicationId != candidate?.applicationId ||
        _candidate?.jobId != candidate?.jobId) {
      _workplaceDefault = candidate?.workplaceLocation ?? '';
      _location.text = _workplaceDefault;
      _draftAddress = _workplaceDefault;
      _workplacePin = _defaultPin = candidate?.workplacePin;
      _previousWorkplacePin = null;
      _workplaceRevision++;
    }
    _candidate = candidate;
  }

  Future<void> _chooseWorkplacePin() async {
    final actor = widget.repository.source.userId;
    final address = _location.text.trim();
    if (actor == null ||
        actor != _actor ||
        _candidate == null ||
        address.isEmpty ||
        _pickingWorkplace ||
        _busy ||
        _confirm) {
      return;
    }
    final revision = _workplaceRevision;
    setState(() => _pickingWorkplace = true);
    try {
      final result = await widget.pickWorkplace(
        context,
        _workplacePin,
        address,
        false,
      );
      if (!mounted ||
          result == null ||
          _confirm ||
          _busy ||
          widget.repository.source.userId != actor ||
          revision != _workplaceRevision ||
          address != _location.text.trim()) {
        return;
      }
      final point = result.coordinates;
      final pin = workplaceCoordinates(point.latitude, point.longitude);
      if (pin == null) return;
      final placeAddress = result.placeAddress?.trim();
      setState(() {
        if (placeAddress != null &&
            placeAddress.isNotEmpty &&
            placeAddress.runes.length <= 500) {
          _location.text = placeAddress;
          _draftAddress = placeAddress;
        }
        _workplacePin = pin;
        _previousWorkplacePin = null;
        _workplaceRevision++;
      });
    } finally {
      if (mounted) setState(() => _pickingWorkplace = false);
    }
  }

  String get _pinStatus {
    final pin = _workplacePin;
    return pin == null
        ? 'No map pin selected'
        : 'Draft pin: ${_coordinateLabel(pin)}';
  }

  String _coordinateLabel(WorkplaceCoordinates pin) =>
      '${pin.latitude.toStringAsFixed(6)}, ${pin.longitude.toStringAsFixed(6)}';

  bool get _requestLocked {
    final candidate = _candidate;
    if (candidate == null) return false;
    final status = widget.repository.statusFor(candidate);
    return status == WorkAssignmentCreateStatus.uncertain ||
        status == WorkAssignmentCreateStatus.submitting;
  }

  bool get _canResolvePreviousPin =>
      _candidate != null &&
      widget.repository.source.userId == _actor &&
      !_busy &&
      !_confirm &&
      !_closing &&
      !_leaving &&
      !_pickingWorkplace &&
      !_requestLocked &&
      !widget.repository.state.loading &&
      widget.repository.state.error == null &&
      _engagementReady;

  bool get _canKeepPreviousPin =>
      _canResolvePreviousPin &&
      _draftAddress.isNotEmpty &&
      _location.text.runes.length <= 500;

  void _resolvePreviousPin(int revision, {required bool keep}) {
    if (revision != _workplaceRevision ||
        _previousWorkplacePin == null ||
        !_canResolvePreviousPin ||
        (keep && !_canKeepPreviousPin)) {
      return;
    }
    setState(() {
      _workplacePin = keep ? _previousWorkplacePin : null;
      _previousWorkplacePin = null;
      _workplaceRevision++;
    });
  }

  Widget _previousPinConfirmation(WorkplaceCoordinates pin) {
    final revision = _workplaceRevision;
    return Card(
      margin: const EdgeInsets.only(top: 8),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Verify the previous pin',
              style: Theme.of(context).textTheme.titleSmall,
            ),
            const SizedBox(height: 4),
            Text(
              'Edited workplace: ${_draftAddress.isEmpty ? 'Empty' : _draftAddress}',
            ),
            Text('Previous pin: ${_coordinateLabel(pin)}'),
            const Text(
              'Keep the previous pin only if you verify that the edited workplace refers to the same physical location.',
            ),
            Wrap(
              spacing: 8,
              children: [
                OutlinedButton(
                  onPressed: _canKeepPreviousPin
                      ? () => _resolvePreviousPin(revision, keep: true)
                      : null,
                  child: const Text('Keep existing pin'),
                ),
                TextButton(
                  onPressed: _canResolvePreviousPin
                      ? () => _resolvePreviousPin(revision, keep: false)
                      : null,
                  child: const Text('Clear pin'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
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
        [_startDate, _startTime, _endTime].any((c) => c.text.isNotEmpty) ||
        _location.text != _workplaceDefault ||
        _workplacePin != _defaultPin;
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
        child: TimePickerTheme(
          data: Theme.of(context).timePickerTheme.copyWith(
            padding: MediaQuery.sizeOf(context).width < 360
                ? const EdgeInsets.symmetric(horizontal: 4, vertical: 16)
                : null,
          ),
          child: child!,
        ),
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

  Future<void> _submit({
    bool reconcile = false,
    bool useLegacyTextOnly = false,
  }) async {
    if (_busy ||
        (!reconcile && _result?.scheduleConflict == true) ||
        _candidate == null ||
        widget.repository.source.userId != _actor) {
      return;
    }
    final candidate = _candidate!;
    final revision = _workplaceRevision;
    setState(() {
      _busy = true;
      _reconciling = reconcile;
    });
    if (!reconcile) {
      // Paint the disabled save button before validation and server preflight.
      await WidgetsBinding.instance.endOfFrame;
      if (!mounted) return;
      if (widget.repository.source.userId != _actor ||
          revision != _workplaceRevision) {
        setState(() => _busy = false);
        _changed();
        return;
      }
    }
    final start = _start, end = _end;
    final location = _location.text.trim();
    final pin = _workplacePin;
    if (!reconcile) {
      try {
        final latest = await widget.closureGateway.status(
          candidate.applicationId,
        );
        if (!mounted) return;
        if (widget.repository.source.userId != _actor ||
            revision != _workplaceRevision) {
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
            start: start!,
            end: end!,
            location: location,
            workplaceLatitude: pin?.latitude,
            workplaceLongitude: pin?.longitude,
            useLegacyTextOnly: useLegacyTextOnly,
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
    final locked = _requestLocked;
    final saving = _busy && !_reconciling && _confirm && !accountChanged;
    final previousPin = _previousWorkplacePin;
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
          floatingLabelBehavior: FloatingLabelBehavior.always,
          border: const OutlineInputBorder(),
          errorMaxLines: 3,
          prefixIcon: controller == _location
              ? const Icon(Icons.location_on_outlined)
              : null,
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
        onChanged: (value) => setState(() {
          _result = null;
          if (controller == _location && value.trim() != _draftAddress) {
            _draftAddress = value.trim();
            _previousWorkplacePin = _workplacePin ?? _previousWorkplacePin;
            _workplacePin = null;
            _workplaceRevision++;
          }
        }),
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
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(scoped ? 'Add shift' : 'Create Assignment'),
                ),
                IconButton(
                  tooltip: 'Close assignment dialog',
                  onPressed: _busy ? null : _close,
                  icon: const Icon(Icons.close),
                ),
              ],
            ),
            Text(
              'Malaysia time · MYT · UTC+8',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 12),
            const Divider(height: 1),
          ],
        ),
        content: SizedBox(
          width: 760,
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.sizeOf(context).height * .70,
            ),
            child: SingleChildScrollView(
              child: accountChanged
                  ? const Text(
                      'Account changed. Close this dialog and sign in again.',
                    )
                  : Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        if (_busy && !saving)
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
                            'Creation is blocked for this schedule. Choose Back to change the dates or times, then review again, or close this dialog.',
                          ),
                        if (locked && !_confirm)
                          const Text(
                            'An earlier creation is unresolved. Check its existing request before scheduling another shift for this application. This check does not create a shift.',
                          ),
                        if (_confirm && _candidate != null) ...[
                          Icon(
                            Icons.calendar_month_outlined,
                            size: 36,
                            color: Theme.of(context).colorScheme.primary,
                          ),
                          const SizedBox(height: 12),
                          Text(
                            'Review shift before saving',
                            textAlign: TextAlign.center,
                            style: Theme.of(context).textTheme.titleLarge,
                          ),
                          const SizedBox(height: 6),
                          const Text(
                            'Confirm the Malaysia date, time and worker assignment below.',
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: 20),
                          ShiftReviewTable(
                            rows: [
                              ('Company', _candidate!.companyName),
                              ('Worker', _candidate!.applicantName),
                              ('Hired job', _candidate!.jobTitle),
                              ('Date', shiftDateLabel(_start!, full: true)),
                              (
                                'Scheduled time',
                                shiftTimeRange(_start!, _end!),
                              ),
                              (
                                'Scheduled duration',
                                '${_end!.difference(_start!).inHours}h ${_end!.difference(_start!).inMinutes.remainder(60)}m',
                              ),
                              ('Workplace', _location.text.trim()),
                              ('Map pin', _pinStatus),
                            ],
                          ),
                          if (_workplacePin != null)
                            const Text(
                              'The workplace and map pin will be saved for this shift.',
                            ),
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
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'No eligible jobs available',
                                style: Theme.of(context).textTheme.titleSmall,
                              ),
                              const SizedBox(height: 4),
                              const Text(
                                'New shifts require a Part-Time or Temporary job with an eligible hired worker. '
                                'Hired workers can receive additional non-overlapping shifts.',
                              ),
                            ],
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
                                if (scoped && _candidate != null) ...[
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
                                  // The floating label paints above the first field.
                                  const SizedBox(height: 12),
                                  DropdownButtonFormField<String>(
                                    initialValue: _job,
                                    isExpanded: true,
                                    decoration: const InputDecoration(
                                      labelText: 'Company job',
                                      floatingLabelBehavior:
                                          FloatingLabelBehavior.always,
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
                                            _setCandidate(null);
                                            _result = null;
                                          }),
                                    validator: (v) =>
                                        v == null ? 'Select a job.' : null,
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    'Only Part-Time and Temporary jobs with eligible hired workers are available.',
                                    style: Theme.of(context).textTheme.bodySmall
                                        ?.copyWith(color: JobMateTheme.body),
                                  ),
                                  const SizedBox(height: 12),
                                  DropdownButtonFormField<String>(
                                    key: ValueKey(_job),
                                    initialValue: _candidate?.applicationId,
                                    isExpanded: true,
                                    decoration: const InputDecoration(
                                      labelText: 'Hired application',
                                      floatingLabelBehavior:
                                          FloatingLabelBehavior.always,
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
                                              _setCandidate(
                                                state.candidates.singleWhere(
                                                  (c) =>
                                                      c.applicationId == value,
                                                ),
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
                                LayoutBuilder(
                                  builder: (context, constraints) {
                                    final start = input(
                                      _startTime,
                                      'Start time (MYT)',
                                      startTime,
                                    );
                                    final end = input(
                                      _endTime,
                                      'End time (MYT)',
                                      endTime,
                                    );
                                    return constraints.maxWidth >= 540
                                        ? Row(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                              Expanded(child: start),
                                              const SizedBox(width: 12),
                                              Expanded(child: end),
                                            ],
                                          )
                                        : Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.stretch,
                                            children: [start, end],
                                          );
                                  },
                                ),
                                input(
                                  _location,
                                  'Workplace location',
                                  (v) => v == null || v.trim().isEmpty
                                      ? 'Enter a workplace location.'
                                      : v.runes.length > 500
                                      ? 'Use no more than 500 characters.'
                                      : null,
                                ),
                                Text(_pinStatus),
                                if (previousPin != null)
                                  _previousPinConfirmation(previousPin),
                                if (_workplacePin != null)
                                  const Text(
                                    'Check that the pin matches the workplace address before creating the shift.',
                                  ),
                                Wrap(
                                  spacing: 8,
                                  children: [
                                    OutlinedButton.icon(
                                      onPressed:
                                          _busy ||
                                              _pickingWorkplace ||
                                              _candidate == null ||
                                              _draftAddress.isEmpty
                                          ? null
                                          : _chooseWorkplacePin,
                                      icon: const Icon(Icons.map_outlined),
                                      label: Text(
                                        _workplacePin == null
                                            ? 'Choose pin'
                                            : 'Change pin',
                                      ),
                                    ),
                                    if (_workplacePin != null)
                                      TextButton(
                                        onPressed: _busy || _pickingWorkplace
                                            ? null
                                            : () => setState(
                                                () => _workplacePin = null,
                                              ),
                                        child: const Text('Clear pin'),
                                      ),
                                  ],
                                ),
                                if (_start != null &&
                                    _end != null &&
                                    _end!.isAfter(_start!))
                                  Text(
                                    'Scheduled duration: ${_end!.difference(_start!).inHours}h ${_end!.difference(_start!).inMinutes.remainder(60)}m',
                                    style: Theme.of(context)
                                        .textTheme
                                        .bodySmall,
                                  ),
                                const SizedBox(height: 12),
                                const _BeforeSchedulingNotice(),
                              ],
                            ),
                          ),
                      ],
                    ),
            ),
          ),
        ),
        actions: [
          _AssignmentFooter(
            children: [
              if (!_confirm || (locked && !saving) || accountChanged)
                OutlinedButton(
                  onPressed: _busy ? null : () => _close(),
                  child: const Text('Cancel'),
                ),
              if (!accountChanged && _confirm && (!locked || saving))
                OutlinedButton(
                  onPressed: _busy
                      ? null
                      : () {
                          _confirm = false;
                          _result = null;
                          _changed();
                        },
                  child: const Text('Back'),
                ),
              if (!accountChanged && locked && !saving)
                OutlinedButton(
                  onPressed: _busy ? null : () => _submit(reconcile: true),
                  child: const Text('Check current assignment'),
                ),
              if (saving ||
                  (!accountChanged &&
                      !locked &&
                      !_engagementClosed &&
                      _engagementError == null &&
                      !_engagementLoading &&
                      state.error == null &&
                      !state.loading &&
                      !unavailable &&
                      !(_confirm && _result?.scheduleConflict == true) &&
                      (_confirm || state.candidates.isNotEmpty))) ...[
                if (_confirm && _result?.legacyTextOnlyAvailable == true)
                  OutlinedButton(
                    onPressed: _busy
                        ? null
                        : () => _submit(useLegacyTextOnly: true),
                    child: const Text('Save text only in compatibility mode'),
                  ),
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
                          final scheduleError = widget.repository
                              .validateSchedule(_start!, _end!);
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
                  child: _confirm
                      ? _SaveAssignmentLabel(saving: saving)
                      : const Text('Review Shift'),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}

class _SaveAssignmentLabel extends StatelessWidget {
  const _SaveAssignmentLabel({required this.saving});

  final bool saving;

  @override
  Widget build(BuildContext context) => Semantics(
    liveRegion: saving,
    child: Stack(
      alignment: Alignment.center,
      children: [
        Visibility(
          visible: !saving,
          maintainSize: true,
          maintainAnimation: true,
          maintainState: true,
          child: const Text('Confirm & Save', textAlign: TextAlign.center),
        ),
        Visibility(
          visible: saving,
          maintainSize: true,
          maintainAnimation: true,
          maintainState: true,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox.square(
                dimension: 16,
                child: saving
                    ? CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Theme.of(context).colorScheme.primary,
                      )
                    : null,
              ),
              const SizedBox(width: 8),
              const Flexible(
                child: Text(
                  'Saving assignment...',
                  textAlign: TextAlign.center,
                ),
              ),
            ],
          ),
        ),
      ],
    ),
  );
}

class _AssignmentFooter extends StatelessWidget {
  const _AssignmentFooter({required this.children});
  final List<Widget> children;
  @override
  Widget build(BuildContext context) => SizedBox(
    width: 760,
    child: MediaQuery.sizeOf(context).width < 600
        ? Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (var i = 0; i < children.length; i++) ...[
                if (i > 0) const SizedBox(height: 8),
                children[i],
              ],
            ],
          )
        : Row(
            children: [
              for (var i = 0; i < children.length; i++) ...[
                if (i > 0) const SizedBox(width: 12),
                Expanded(child: children[i]),
              ],
            ],
          ),
  );
}

class _BeforeSchedulingNotice extends StatelessWidget {
  const _BeforeSchedulingNotice();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // Theme-aware informational blue; validation still uses error colors.
    final amber = ColorScheme.fromSeed(
      seedColor: Colors.lightBlue,
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
