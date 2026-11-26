import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../shared/navigation/app_routes.dart';
import '../../shared/widgets/app_workspace.dart';
import '../../shared/widgets/design_primitives.dart';
import '../../shared/widgets/auth_style.dart';
import '../../shared/theme/jobmate_theme.dart';
import '../../shared/widgets/responsive_layout.dart';
import '../applications/job_marketplace_format.dart';
import '../applications/module2_repository.dart' show BrowseJob;
import 'job_form_widgets.dart';
import 'job_form_result.dart';
import '../../shared/widgets/loading_overlay.dart';
import 'job_postings_repository.dart';
import 'job_preview.dart';
import 'job_display.dart';
import 'job_validation.dart';
import '../company/company_logo.dart';
import 'job_ai_formatter.dart';
import 'workplace_coordinates.dart';
import 'workplace_map_picker.dart';

class JobFormPage extends StatefulWidget {
  const JobFormPage({
    super.key,
    this.jobId,
    this.repository,
    this.pickWorkplace = showWorkplacePicker,
    this.dialog = false,
  });
  final String? jobId;
  final JobPostingsRepository? repository;
  final WorkplacePicker pickWorkplace;
  final bool dialog;
  @override
  State<JobFormPage> createState() => JobFormPageState();
}

class JobFormPageState extends State<JobFormPage> {
  late final repo =
      widget.repository ?? JobPostingsRepository(Supabase.instance.client);
  final form = GlobalKey<FormState>();
  final fieldKeys = <String, GlobalKey<FormFieldState<String>>>{};
  final fields = {
    for (final key in [
      'title',
      'department',
      'location',
      'salary_min',
      'salary_max',
      'vacancies',
      'application_deadline',
      'original_description',
      'role_overview',
      'responsibilities',
      'requirements',
      'benefits',
    ])
      key: TextEditingController(),
  };
  static const options = {
    'employment_type': jobEmploymentTypes,
    'work_arrangement': ['on_site', 'hybrid', 'remote'],
  };
  final selected = {
    'employment_type': 'full_time',
    'work_arrangement': 'on_site',
    'salary_period': jobCompensationPolicy['full_time']!.defaultPeriod,
  };
  JobAccess? access;
  bool get _creating => widget.jobId == null;
  late final String? _createActor;
  StreamSubscription<AuthState>? _authChanges;
  bool _accountChanged = false;
  bool get _sameCreateActor =>
      !_accountChanged && repo.client.auth.currentUser?.id == _createActor;
  bool get _accessReady =>
      !loading && access?.allowed == true && (!_creating || _sameCreateActor);
  String? _createAccessError;
  String? _verifiedCompanyId;
  String? error;
  String? jobId;
  bool loading = true, busy = false, publishing = false, salaryVisible = true;
  bool validationActivated = false;
  bool _salaryChangePending = false;
  static const _salaryAmounts = ['salary_min', 'salary_max'];
  static const _compensationFields = [
    'employment_type',
    'salary_period',
    ..._salaryAmounts,
  ];

  String get _employmentType => selected['employment_type']!;
  String get _salaryPeriod => selected['salary_period']!;
  bool get _legacyPublishedTerms {
    final original = savedJob;
    return status == 'published' &&
        original != null &&
        jobSalaryPeriodError(
              '${original['employment_type'] ?? ''}',
              '${original['salary_period'] ?? ''}',
            ) !=
            null;
  }

  bool get _savedTermsUnchanged {
    final original = savedJob;
    if (original == null) return false;
    return _compensationFields.every((key) {
      final value = fields[key]?.text.trim() ?? selected[key];
      return value == '${original[key] ?? ''}'.trim();
    });
  }

  bool aiFormatting = false, aiAssisted = false;
  bool aiConfirmationPending = false;
  String? aiError;
  String status = 'draft';
  Map<String, dynamic>? savedJob;
  WorkplaceCoordinates? _confirmedPin;
  String? _confirmedAddress;
  bool _pinCleared = false;
  String get _address => fields['location']!.text.trim();
  bool get _remote => selected['work_arrangement'] == 'remote';
  WorkplaceCoordinates? get _pin =>
      !_remote && _address.isNotEmpty && _address == _confirmedAddress
      ? _confirmedPin
      : null;

  void _setCanonicalJob(Map<String, dynamic> job) {
    savedJob = job;
    _pinCleared = false;
    _confirmedAddress = _address;
    _confirmedPin = _remote
        ? null
        : workplaceCoordinates(job['latitude'], job['longitude']);
  }

  final _autoSearchedAddresses = <String>{};

  Future<void> _chooseWorkplace() async {
    if (!_accessReady || busy) return;
    final address = _address;
    final previous = _pin;
    final result = await widget.pickWorkplace(
      context,
      previous ??
          _confirmedPin ??
          workplaceCoordinates(savedJob?['latitude'], savedJob?['longitude']),
      address,
      previous == null &&
          address.isNotEmpty &&
          _autoSearchedAddresses.add(address),
    );
    if (!mounted ||
        !_accessReady ||
        _remote ||
        address != _address ||
        result == null) {
      return;
    }
    final point = result.coordinates;
    final pin = workplaceCoordinates(point.latitude, point.longitude);
    if (pin == null) return;
    setState(() {
      _confirmedPin = pin;
      _confirmedAddress = address;
      _pinCleared = false;
    });
    if (validationActivated) fieldKeys['location']?.currentState?.validate();
  }

  String? _savedSnapshot;
  Future<bool>? _exitConfirmation;
  String get _snapshot => jsonEncode({
    for (final entry in fields.entries) entry.key: entry.value.text,
    ...selected,
    'salary_visible': salaryVisible,
    'ai_assisted': aiAssisted,
    'latitude': _pin?.latitude,
    'longitude': _pin?.longitude,
    'pin_cleared': _pinCleared,
  });

  Future<bool> confirmExit() async {
    // A completed sign-out must leave protected routes. Keep dirty-form
    // confirmation for ordinary navigation while the account is signed in.
    if (!repo.signedIn) return true;
    if (busy) return false;
    if (_savedSnapshot == null || _snapshot == _savedSnapshot) return true;
    if (_exitConfirmation != null) return _exitConfirmation!;
    final confirmation = showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Discard unsaved changes?'),
        content: const Text(
          'Your changes have not been saved. Leave this job form?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Keep editing'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Discard changes'),
          ),
        ],
      ),
    ).then((result) => result == true);
    _exitConfirmation = confirmation;
    try {
      final leave = await confirmation;
      if (leave && mounted) _savedSnapshot = _snapshot;
      return leave;
    } finally {
      _exitConfirmation = null;
    }
  }

  Future<void> _backToPostings() async {
    if (!await confirmExit() || !mounted) return;
    if (GoRouterState.of(context).extra == 'job-list' && context.canPop()) {
      context.pop();
    } else {
      context.go('${AppRoutes.jobPostings}?status=$status');
    }
  }

  Future<void> _navigate(String destination) async {
    final baseline = _savedSnapshot;
    if (!await confirmExit() || !mounted) return;
    if (destination == AppRoutes.home) {
      context.go(destination);
    } else {
      await context.push<void>(destination);
      // A pushed workspace page leaves this form in the route stack.
      if (mounted) _savedSnapshot = baseline;
    }
  }

  @override
  void initState() {
    super.initState();
    jobId = widget.jobId;
    if (_creating) {
      fields['vacancies']!.text = '1';
      _savedSnapshot = _snapshot;
      _createActor = repo.client.auth.currentUser?.id;
      _authChanges = repo.client.auth.onAuthStateChange.listen((_) {
        if (!mounted || _accountChanged || _sameCreateActor) return;
        setState(() {
          _accountChanged = true;
          access = null;
          loading = false;
        });
      });
      _loadCreateAccess();
    } else {
      load();
    }
  }

  @override
  void dispose() {
    unawaited(_authChanges?.cancel());
    for (final c in fields.values) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _retryCreateAccess() async {
    if (loading ||
        busy ||
        !_sameCreateActor ||
        (_createAccessError == null && error == null)) {
      return;
    }
    setState(() {
      loading = true;
      access = null;
      error = null;
      _createAccessError = null;
    });
    await _loadCreateAccess();
  }

  Future<void> _loadCreateAccess() async {
    final JobAccess result;
    try {
      result = await repo.loadAccess(includeLogo: false);
    } catch (failure) {
      if (!mounted || !_sameCreateActor) return;
      setState(() {
        loading = false;
        if (failure is AuthException) {
          access = const JobAccess(null, 'Sign in to manage job postings.');
        } else if (failure is PostgrestException && failure.code == '42501') {
          access = JobAccess(null, jobError(failure));
        } else {
          _createAccessError = jobError(failure);
        }
      });
      return;
    }
    if (!mounted || !_sameCreateActor) return;
    final companyId = result.company?['company_id']?.toString();
    if (result.allowed &&
        (companyId == null ||
            (_verifiedCompanyId != null && companyId != _verifiedCompanyId))) {
      setState(() {
        access = const JobAccess(null, 'Company changed. Reopen the job form.');
        loading = false;
      });
      return;
    }
    setState(() {
      access = result;
      loading = false;
      if (result.allowed) _verifiedCompanyId = companyId;
    });
    if (!result.allowed || result.logo != null) return;
    try {
      final logo = await repo.loadAccessLogo(result);
      if (logo == null ||
          !mounted ||
          !_sameCreateActor ||
          !identical(access, result)) {
        return;
      }
      setState(() => access = JobAccess(result.company, null, logo: logo));
    } catch (_) {
      // Keep the existing avatar when an optional logo cannot be loaded.
    }
  }

  Future<void> load() async {
    setState(() {
      loading = true;
      error = null;
    });
    try {
      final result = await repo.loadAccess();
      Map<String, dynamic>? job;
      if (result.allowed && jobId != null) {
        job = (await repo.list(result.company!['company_id'].toString()))
            .where((j) => j['job_id'].toString() == jobId)
            .firstOrNull;
        if (job == null) {
          throw StateError(
            'Job unavailable or you do not have permission to view it.',
          );
        }
      }
      if (!mounted) return;
      access = result;
      if (job != null) {
        aiAssisted = job['ai_assisted'] == true;
        status = job['status'] as String;
        for (final entry in fields.entries) {
          final value = job[entry.key];
          entry.value.text = value is List
              ? value.join('\n')
              : '${value ?? ''}';
        }
        for (final key in selected.keys) {
          selected[key] =
              job[key] as String? ??
              (key == 'salary_period' ? '' : selected[key]!);
        }
        salaryVisible = job['salary_visible'] as bool? ?? true;
        _setCanonicalJob(job);
      } else {
        fields['vacancies']!.text = '1';
      }
    } catch (e) {
      error = jobError(e);
    }
    if (mounted) {
      _savedSnapshot = _snapshot;
      setState(() => loading = false);
    }
  }

  Map<String, dynamic> validationValues() => {
    for (final entry in fields.entries)
      entry.key: jobBulletFields.contains(entry.key)
          ? jobLines(entry.value.text)
          : entry.value.text,
    ...selected,
    'salary_visible': salaryVisible,
  };

  String? validate(String key, String value) {
    if (key == 'salary_period') {
      if (_legacyPublishedTerms && !_savedTermsUnchanged) {
        return 'The saved compensation terms for this published job must remain unchanged.';
      }
      final compatibility = jobSalaryPeriodError(
        _employmentType,
        _salaryPeriod,
      );
      if (compatibility != null &&
          !(_savedTermsUnchanged && (!publishing || _legacyPublishedTerms))) {
        return compatibility;
      }
    }
    final error = jobFieldError(
      key,
      validationValues(),
      publishing: publishing,
    );
    if (error != null ||
        key != 'location' ||
        !publishing ||
        _remote ||
        _pin != null) {
      return error;
    }
    if (status != 'published') return workplaceRequiredForPublication;
    if (_address != (savedJob?['location'] as String? ?? '').trim() ||
        savedJob?['work_arrangement'] == 'remote' ||
        _confirmedPin != null) {
      return confirmWorkplaceMessage;
    }
    return null;
  }

  Widget requiredLabel(String label) => Text.rich(
    TextSpan(
      children: [
        TextSpan(text: label),
        const TextSpan(
          text: ' *',
          style: TextStyle(color: Colors.red),
        ),
      ],
    ),
  );
  Map<String, dynamic> values() => {
    for (final entry in fields.entries)
      entry.key:
          ['responsibilities', 'requirements', 'benefits'].contains(entry.key)
          ? jobLines(entry.value.text)
          : entry.key.startsWith('salary_')
          ? double.tryParse(entry.value.text.trim())
          : entry.key == 'vacancies'
          ? int.tryParse(entry.value.text.trim())
          : entry.value.text.trim().isEmpty
          ? null
          : entry.value.text.trim(),
    ...selected,
    if (_salaryPeriod.isEmpty) 'salary_period': null,
    'salary_visible': salaryVisible,
    'ai_assisted': aiAssisted,
  };
  Future<void> save(bool publish) async {
    if (busy || _salaryChangePending || status == 'closed' || !_accessReady) {
      return;
    }
    final updatingPublished = status == 'published';
    setState(() {
      publishing = publish || updatingPublished;
      validationActivated = true;
    });
    if (!form.currentState!.validate()) {
      for (final key in [...fields.keys, ...options.keys, 'salary_period']) {
        final state = fieldKeys[key]?.currentState;
        if (state?.hasError == true) {
          final target = fieldKeys[key]!.currentContext;
          if (target != null) {
            await Scrollable.ensureVisible(
              target,
              duration: const Duration(milliseconds: 250),
              alignment: .15,
            );
          }
          break;
        }
      }
      return;
    }
    setState(() {
      busy = true;
      error = null;
    });
    try {
      final pin = _pin;
      final storedPin = workplaceCoordinates(
        savedJob?['latitude'],
        savedJob?['longitude'],
      );
      final clearStoredCoordinates =
          pin == null &&
          (savedJob?['latitude'] != null || savedJob?['longitude'] != null);
      final pinConfirmedForNewAddress =
          pin != null && _address != savedJob?['location'];
      final existingJobId = jobId;
      final saved = await repo.save(
        {
          ...values(),
          if (pin != storedPin ||
              clearStoredCoordinates ||
              pinConfirmedForNewAddress ||
              _pinCleared) ...{
            'latitude': pin?.latitude,
            'longitude': pin?.longitude,
          },
          'status': publishing ? 'published' : 'draft',
        },
        jobId: jobId,
        expectedStatus: status,
        expectedCompanyId: _creating
            ? access!.company!['company_id'].toString()
            : null,
      );
      if (!mounted || (_creating && !_sameCreateActor)) return;
      setState(() {
        jobId = saved['job_id'].toString();
        status = saved['status'] as String;
        fields['location']!.text = (saved['location'] as String?) ?? '';
        selected['work_arrangement'] =
            saved['work_arrangement'] as String? ??
            selected['work_arrangement']!;
        _setCanonicalJob(saved);
        _savedSnapshot = _snapshot;
        busy = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            updatingPublished
                ? 'Job updated successfully'
                : publish
                ? 'Job published successfully'
                : 'Job saved as draft',
          ),
        ),
      );
      if (GoRouterState.of(context).extra == 'job-list' && context.canPop()) {
        context.pop(
          JobFormResult(
            existingJobId == null
                ? JobFormChange.created
                : JobFormChange.updated,
            saved,
          ),
        );
      } else {
        context.pushReplacement('${AppRoutes.jobPostings}?status=$status');
      }
    } catch (e) {
      if (mounted) setState(() => error = jobError(e));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> _closeJob() async {
    final currentJobId = jobId;
    final companyId = access?.company?['company_id']?.toString();
    if (busy ||
        status != 'published' ||
        currentJobId == null ||
        companyId == null) {
      return;
    }
    final changed = _savedSnapshot != null && _snapshot != _savedSnapshot;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Close this job?'),
        content: Text(
          changed
              ? 'Closed jobs cannot be edited or reopened. Your unsaved form changes will not be saved.'
              : 'Closed jobs cannot be edited or reopened.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Keep Job Open'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
            ),
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Close Job'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() {
      busy = true;
      error = null;
    });
    try {
      await repo.close(currentJobId);
      final closed = (await repo.list(companyId))
          .where((row) => row['job_id'].toString() == currentJobId)
          .firstOrNull;
      if (closed == null || closed['status'] != 'closed') {
        throw StateError(
          'The job was closed, but its latest status could not be loaded. Refresh Job Postings before continuing.',
        );
      }
      if (!mounted) return;
      _savedSnapshot = _snapshot;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Job closed successfully')));
      if (GoRouterState.of(context).extra == 'job-list' && context.canPop()) {
        context.pop(JobFormResult(JobFormChange.closed, closed));
      } else {
        context.go('${AppRoutes.jobPostings}?status=closed');
      }
    } catch (failure) {
      if (mounted) setState(() => error = jobError(failure));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> formatWithAi() async {
    if (busy || status == 'closed') return;
    if (!repo.signedIn) {
      setState(() => aiError = 'Sign in to use AI formatting.');
      return;
    }
    final description = fields['original_description']!.text.trim();
    if (description.length < 30) {
      setState(
        () => aiError = 'Enter at least 30 characters in Original Description to use AI formatting.',
      );
      return;
    }
    setState(() {
      busy = true;
      aiError = null;
      aiConfirmationPending = true;
    });
    try {
      const targets = [
        'role_overview',
        'responsibilities',
        'requirements',
        'benefits',
      ];
      if (targets.any((key) => fields[key]!.text.trim().isNotEmpty)) {
        final confirmed = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Replace existing content?'),
            content: const Text(
              'AI formatting will replace Role Overview, Responsibilities, Requirements and Benefits. Your Original Description will be kept.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('Replace with AI'),
              ),
            ],
          ),
        );
        if (confirmed != true || !mounted) return;
      }
      if (!mounted || !_accessReady) return;
      FocusManager.instance.primaryFocus?.unfocus();
      setState(() => aiFormatting = true);
      final generated = await repo
          .formatDescription(description)
          .timeout(const Duration(seconds: 60));
      if (!mounted || !_accessReady) return;
      for (final key in targets) {
        fields[key]!.text = generated[key]!;
      }
      setState(() => aiAssisted = true);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Job description formatted! Please review the generated content.',
          ),
        ),
      );
    } catch (error) {
      if (!mounted) return;
      final message = error is TimeoutException
          ? 'AI formatting took too long. Your text has been preserved. Please try again.'
          : jobFormattingError(error);
      setState(() => aiError = message);
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(message)));
    } finally {
      if (mounted) {
        setState(() {
          busy = false;
          aiFormatting = false;
          aiConfirmationPending = false;
        });
      }
    }
  }

  Future<void> pickDeadline() async {
    final now = DateUtils.dateOnly(DateTime.now()).add(const Duration(days: 1));
    final current = DateTime.tryParse(fields['application_deadline']!.text);
    final last = DateTime(now.year + 20, 12, 31);
    final picked = await showDatePicker(
      context: context,
      initialDate:
          current != null && !current.isBefore(now) && !current.isAfter(last)
          ? current
          : now,
      firstDate: now,
      lastDate: last,
    );
    if (picked != null && mounted) {
      fields['application_deadline']!.text = jobDate(picked);
    }
  }

  @override
  Widget build(BuildContext context) => Theme(
    data: AuthStyle.theme(context),
    child: LoadingOverlay(
      isLoading: aiFormatting,
      message: 'Formatting your job description...',
      description: 'AI is organizing your content into Role Overview, Responsibilities, Requirements and Benefits.',
      note: 'This may take a few moments.',
      child: widget.dialog
          ? Theme(
              data: JobMateTheme.apply(Theme.of(context)),
              child: _buildDialog(),
            )
          : _buildWorkspace(),
    ),
  );

  bool _hasSalaryError(Map<String, dynamic> amounts) => _salaryAmounts.any(
    (key) => jobFieldError(key, amounts, publishing: false) != null,
  );

  Widget _textInput(String key, {String? liveError}) {
    final multiline = [
      'original_description',
      'role_overview',
      ...jobBulletFields,
    ].contains(key);
    final label = switch (key) {
      'location' => _remote ? 'Work Region' : 'Workplace Address',
      'salary_min' || 'salary_max' => '${jobLabel(key)} (RM)',
      _ => jobLabel(key),
    };
    return JobLabeledField(
      label: requiredLabel(label),
      action: key == 'original_description'
          ? OutlinedButton.icon(
              onPressed: busy || status == 'closed' || !_accessReady
                  ? null
                  : () {
                      if (_accessReady) formatWithAi();
                    },
              icon: const Icon(Icons.auto_awesome_outlined, size: 17),
              label: Text(aiFormatting ? 'Formatting…' : 'Format with AI ✨'),
            )
          : null,
      child: Semantics(
        label: '$label, required before publishing',
        child: TextFormField(
          key: fieldKeys.putIfAbsent(
            key,
            () => GlobalKey<FormFieldState<String>>(),
          ),
          controller: fields[key],
          forceErrorText: liveError,
          onChanged: key == 'location'
              ? (_) => setState(() {
                  if (_address != _confirmedAddress) _confirmedAddress = null;
                })
              : null,
          enabled:
              !busy &&
              status != 'closed' &&
              !(_legacyPublishedTerms && _salaryAmounts.contains(key)),
          minLines: multiline ? 3 : 1,
          maxLines: multiline ? 8 : 1,
          keyboardType: multiline
              ? TextInputType.multiline
              : key.startsWith('salary_') || key == 'vacancies'
              ? const TextInputType.numberWithOptions(decimal: true)
              : TextInputType.text,
          textInputAction: multiline ? TextInputAction.newline : null,
          decoration: InputDecoration(
            hintText: _salaryAmounts.contains(key)
                ? jobSalaryHint(_employmentType, _salaryPeriod, key)
                : jobExamples[key],
            helperMaxLines: 5,
            errorMaxLines: 4,
            suffixIcon: key == 'application_deadline'
                ? IconButton(
                    tooltip: 'Choose application deadline',
                    onPressed: busy || status == 'closed' ? null : pickDeadline,
                    icon: const Icon(Icons.calendar_month_outlined),
                  )
                : null,
            helperText: jobBulletFields.contains(key)
                ? 'Press Enter to start a new bullet point. You can write full sentences or short phrases on each line.'
                : key == 'application_deadline'
                ? 'YYYY-MM-DD. Choose a future date before publishing.'
                : key == 'original_description'
                ? 'Describe duties, requirements, working arrangements and benefits in normal sentences.'
                : key == 'role_overview'
                ? 'You can write multiple sentences or paragraphs. Press Enter to start a new line.'
                : key == 'location'
                ? (_remote
                      ? 'Enter the region where employees can work remotely.'
                      : 'Enter where employees will report for work.')
                : null,
          ),
          validator: (value) => validate(key, value ?? ''),
        ),
      ),
    );
  }

  Widget _workplaceMapField() {
    final pin = _pin;
    final enabled = !busy && status != 'closed';
    final mapButton = OutlinedButton.icon(
      onPressed: enabled && _accessReady && _address.isNotEmpty
          ? _chooseWorkplace
          : null,
      icon: const Icon(Icons.map_outlined),
      label: Text(pin == null ? 'Choose on map' : 'Change pin'),
    );
    if (_confirmedPin == null) {
      return OverflowBar(
        alignment: MainAxisAlignment.spaceBetween,
        overflowAlignment: OverflowBarAlignment.start,
        spacing: 8,
        overflowSpacing: 4,
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.location_on_outlined,
                size: 18,
                color: JobMateTheme.body,
              ),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  'No location selected',
                  style: Theme.of(context).textTheme.bodySmall
                      ?.copyWith(color: JobMateTheme.body),
                ),
              ),
            ],
          ),
          mapButton,
        ],
      );
    }
    return JobLabeledField(
      label: const Text('Workplace Map Location'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (pin != null)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.white,
                border: Border.all(color: JobMateTheme.divider),
                borderRadius: BorderRadius.circular(JobMateTheme.controlRadius),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(
                    Icons.check_circle_outline,
                    color: JobMateTheme.darkTeal,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Workplace location confirmed',
                          style: TextStyle(
                            color: JobMateTheme.heading,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        if (_address.isNotEmpty) ...[
                          const SizedBox(height: 4),
                          Text(_address),
                        ],
                        const SizedBox(height: 4),
                        Text(
                          '${pin.latitude.toStringAsFixed(6)}, ${pin.longitude.toStringAsFixed(6)}',
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(color: JobMateTheme.body),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            )
          else
            Text(
              _address.isEmpty
                  ? 'Enter the workplace address to choose a pin.'
                  : 'Address changed. Confirm the workplace pin again.',
            ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            children: [
              mapButton,
              if (_confirmedPin != null)
                TextButton(
                  onPressed: enabled
                      ? () => setState(() {
                          _confirmedPin = null;
                          _confirmedAddress = null;
                          _pinCleared = true;
                        })
                      : null,
                  child: const Text('Clear pin'),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _changeCompensation(String key, String value) async {
    if (value == selected[key] ||
        _salaryChangePending ||
        busy ||
        status == 'closed' ||
        _legacyPublishedTerms) {
      return;
    }
    final type = key == 'employment_type' ? value : _employmentType;
    final policy = jobCompensationPolicy[type];
    if (policy == null) return;
    final oldPeriod = _salaryPeriod;
    final period = key == 'salary_period'
        ? value
        : policy.periods.contains(oldPeriod)
        ? oldPeriod
        : policy.defaultPeriod;
    if (!policy.periods.contains(period)) return;
    final unitChanged = period != oldPeriod;
    final hasAmounts = _salaryAmounts.any(
      (amount) => fields[amount]!.text.trim().isNotEmpty,
    );
    if (unitChanged && hasAmounts) {
      _salaryChangePending = true;
      // The dropdown updates its internal value before invoking onChanged.
      // Keep displaying the original choice until the employer confirms.
      fieldKeys[key]?.currentState?.reset();
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('Change salary period?'),
          content: Text(
            'Changing from ${oldPeriod.isEmpty ? 'an unspecified period' : jobLabel(oldPeriod)} to ${jobLabel(period)} will reset your entered salary amounts. Enter the new amounts using the selected salary period.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('Change & reset salary'),
            ),
          ],
        ),
      );
      _salaryChangePending = false;
      if (!mounted ||
          confirmed != true ||
          busy ||
          (_creating && !_sameCreateActor)) {
        return;
      }
    }
    setState(() {
      selected['employment_type'] = type;
      selected['salary_period'] = period;
      if (unitChanged) {
        for (final amount in _salaryAmounts) {
          fields[amount]!.clear();
        }
      }
    });
  }

  String get _salaryPeriodHelp {
    final guidance = jobSalaryPeriodHelp(_employmentType);
    if (jobSalaryPeriodError(_employmentType, _salaryPeriod) == null) {
      return guidance;
    }
    if (_legacyPublishedTerms) {
      return 'This published job uses a legacy salary period. Its saved employment and salary terms are kept as entered.';
    }
    return 'This saved salary period is incompatible with the current posting policy. $guidance';
  }

  Widget _selection(String key) {
    final isPeriod = key == 'salary_period';
    final isCompensation = isPeriod || key == 'employment_type';
    final allowed = isPeriod
        ? jobCompensationPolicy[_employmentType]?.periods ?? const <String>[]
        : options[key]!;
    final current = selected[key]!;
    final enabled =
        !busy &&
        status != 'closed' &&
        !(isCompensation && _legacyPublishedTerms) &&
        (!isPeriod || allowed.length > 1 || !allowed.contains(current));
    return JobLabeledField(
      label: requiredLabel(jobLabel(key)),
      child: Semantics(
        label: '${jobLabel(key)}, required before publishing',
        child: DropdownButtonFormField<String>(
          key: fieldKeys.putIfAbsent(
            key,
            () => GlobalKey<FormFieldState<String>>(),
          ),
          initialValue: current.isEmpty ? null : current,
          isExpanded: true,
          validator: (value) => validate(key, value ?? ''),
          decoration: InputDecoration(
            helperMaxLines: 4,
            errorMaxLines: 4,
            helperText: switch (key) {
              'work_arrangement' => 'On-site: at the workplace. Hybrid: workplace and remote. Remote: off-site.',
              'salary_period' => _salaryPeriodHelp,
              _ => null,
            },
          ),
          items: [
            for (final value in allowed)
              DropdownMenuItem(value: value, child: Text(jobLabel(value))),
            if (current.isNotEmpty && !allowed.contains(current))
              DropdownMenuItem(
                value: current,
                enabled: false,
                child: Text(jobLabel(current)),
              ),
          ],
          onChanged: !enabled
              ? null
              : (value) {
                  if (value == null) return;
                  if (isCompensation) {
                    unawaited(_changeCompensation(key, value));
                  } else {
                    setState(() => selected[key] = value);
                  }
                },
        ),
      ),
    );
  }

  String get _formTitle => jobId == null
      ? 'Create Job Posting'
      : status == 'closed'
      ? 'Job details'
      : 'Edit Job Posting';

  Widget _buildDialog() {
    final compact = ResponsiveLayout.isCompact(context);
    final pane = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 8, 8),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  _formTitle,
                  style: Theme.of(context).textTheme.titleLarge,
                ),
              ),
              IconButton(
                tooltip: 'Close job form',
                onPressed: busy ? null : _backToPostings,
                icon: const Icon(Icons.close),
              ),
            ],
          ),
        ),
        const Divider(height: 1),
        Expanded(
          child: loading && !_creating
              ? const Center(child: CircularProgressIndicator())
              : SingleChildScrollView(
                  padding: EdgeInsets.all(compact ? 16 : 20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: _formContent(),
                  ),
                ),
        ),
        if (_showActions) ...[
          const Divider(height: 1),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: _buildActions(),
          ),
        ],
      ],
    );
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && !busy) _backToPostings();
      },
      child: compact
          ? Dialog.fullscreen(child: SafeArea(child: pane))
          : Dialog(
              insetPadding: const EdgeInsets.symmetric(
                horizontal: 24,
                vertical: 20,
              ),
              constraints: const BoxConstraints(maxWidth: 1000, maxHeight: 900),
              clipBehavior: Clip.antiAlias,
              child: pane,
            ),
    );
  }

  bool get _showCreateDraft =>
      _creating && _sameCreateActor && (loading || _createAccessError != null);

  bool get _showActions => _accessReady || _showCreateDraft;

  Widget _buildActions() => LayoutBuilder(
    builder: (context, box) {
      final protected = !busy && _accessReady;
      final close = status == 'published'
          ? TextButton.icon(
              onPressed: protected ? _closeJob : null,
              style: TextButton.styleFrom(
                foregroundColor: Theme.of(context).colorScheme.error,
              ),
              icon: const Icon(Icons.close, size: 18),
              label: const Text('Close Job'),
            )
          : null;
      final draft = status == 'draft'
          ? OutlinedButton(
              onPressed: protected ? () => save(false) : null,
              child: const Text('Save Draft'),
            )
          : null;
      final preview = TextButton.icon(
        onPressed: !protected
            ? null
            : () {
                if (!_accessReady || busy) return;
                final previewAccess = access!;
                final invalidSalary = _hasSalaryError(validationValues());
                showDialog<void>(
                  context: context,
                  builder: (_) => JobPreview(
                    logo: previewAccess.logo,
                    job: {
                      ...?savedJob,
                      ...values(),
                      if (invalidSalary) ...{
                        'salary_min': null,
                        'salary_max': null,
                      },
                      'latitude': _pin?.latitude,
                      'longitude': _pin?.longitude,
                    },
                    company: previewAccess.company!['company_name'] as String,
                  ),
                );
              },
        icon: const Icon(Icons.visibility_outlined, size: 18),
        label: Text(status == 'closed' ? 'Preview' : 'Preview unsaved changes'),
      );
      final cancel = OutlinedButton(
        onPressed: busy ? null : _backToPostings,
        child: Text(status == 'closed' ? 'Back' : 'Cancel'),
      );
      final primary = status == 'closed'
          ? null
          : FilledButton(
              onPressed: protected ? () => save(true) : null,
              child: Text(
                status == 'published' ? 'Save Changes' : 'Publish Job',
              ),
            );
      if (box.maxWidth <
          900 * MediaQuery.textScalerOf(context).scale(14) / 14) {
        return Wrap(
          spacing: 12,
          runSpacing: 10,
          children: [?close, ?draft, preview, cancel, ?primary],
        );
      }
      return Row(
        children: [
          ?close,
          if (close != null) const SizedBox(width: 12),
          ?draft,
          const SizedBox(width: 12),
          const Spacer(),
          preview,
          const SizedBox(width: 12),
          cancel,
          const SizedBox(width: 12),
          ?primary,
        ],
      );
    },
  );

  Widget _hiringCompanyContent() {
    if (_showCreateDraft) {
      final accessError = _createAccessError;
      if (accessError != null) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              accessError,
              style: const TextStyle(color: JobMateTheme.error),
            ),
            TextButton(
              onPressed: _retryCreateAccess,
              child: const Text('Retry'),
            ),
          ],
        );
      }
      return Row(
        children: [
          const SizedBox.square(
            dimension: 16,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
          const SizedBox(width: 8),
          Flexible(
            child: Semantics(
              liveRegion: true,
              child: Text(
                'Verifying company...',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
          ),
        ],
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            if (access!.logo == null) ...[
              const CircleAvatar(child: Icon(Icons.business_outlined)),
              const SizedBox(width: 12),
            ],
            Expanded(
              child: CompanyIdentity(
                name: access!.company!['company_name'] as String,
                logo: access!.logo,
              ),
            ),
          ],
        ),
        if (access!.company!['verification_status'] == 'verified')
          const Padding(
            padding: EdgeInsets.only(top: 8),
            child: Row(
              children: [
                Icon(
                  Icons.verified_outlined,
                  size: 17,
                  color: JobMateTheme.darkTeal,
                ),
                SizedBox(width: 6),
                Flexible(
                  child: Text(
                    'Verified company',
                    style: TextStyle(color: JobMateTheme.darkTeal),
                  ),
                ),
              ],
            ),
          ),
        const SizedBox(height: 8),
        const Text(
          'Your hiring company is selected automatically from your membership and cannot be changed here.',
          style: TextStyle(color: JobMateTheme.body),
        ),
      ],
    );
  }

  List<Widget> _formContent() => [
    if (error != null) ...[
      Text(error!, style: const TextStyle(color: JobMateTheme.error)),
      TextButton(
        onPressed: busy ? null : (_creating ? _retryCreateAccess : load),
        child: const Text('Reload'),
      ),
    ],
    if ((_creating && !_sameCreateActor) ||
        (access != null && !access!.allowed))
      WorkspaceCard(
        title: 'Job creation unavailable',
        child: Column(
          children: [
            Text(
              _creating && !_sameCreateActor
                  ? 'Your account changed. Reopen the job form.'
                  : access!.message!,
            ),
            TextButton(
              onPressed: () => context.push(AppRoutes.company),
              child: const Text('Company profile'),
            ),
            const FilledButton(onPressed: null, child: Text('Create Job')),
          ],
        ),
      ),
    if (_showActions)
      Form(
        key: form,
        autovalidateMode: validationActivated
            ? AutovalidateMode.always
            : AutovalidateMode.disabled,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            JobFormSection(
              title: 'Hiring company',
              icon: Icons.business_outlined,
              compact: widget.dialog,
              child: _hiringCompanyContent(),
            ),
            const Padding(
              padding: EdgeInsets.only(bottom: 12),
              child: Text(
                'Fields marked * are required before publishing. Drafts may be incomplete.',
              ),
            ),
            JobFormSection(
              title: 'Basic Information',
              icon: Icons.work_outline,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  ResponsiveGrid(
                    minItemWidth: 225,
                    maxColumns: 2,
                    children: [
                      _textInput('title'),
                      _textInput('department'),
                      _selection('employment_type'),
                      _selection('work_arrangement'),
                    ],
                  ),
                ],
              ),
            ),
            JobFormSection(
              title: 'Compensation',
              icon: Icons.payments_outlined,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  ListenableBuilder(
                    listenable: Listenable.merge([
                      fields['salary_min']!,
                      fields['salary_max']!,
                    ]),
                    builder: (context, _) => ResponsiveGrid(
                      minItemWidth: 200,
                      maxColumns: 3,
                      children: [
                        _textInput('salary_min'),
                        _textInput(
                          'salary_max',
                          liveError: jobSalaryRangeError({
                            for (final key in _salaryAmounts)
                              key: fields[key]!.text,
                          }),
                        ),
                        _selection('salary_period'),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Show salary on posting'),
                    subtitle: const Text(
                      'Turn off to hide salary amounts from job seekers.',
                    ),
                    value: salaryVisible,
                    onChanged: busy || status == 'closed'
                        ? null
                        : (value) => setState(() => salaryVisible = value),
                  ),
                  ListenableBuilder(
                    listenable: Listenable.merge([
                      fields['salary_min']!,
                      fields['salary_max']!,
                    ]),
                    builder: (context, _) {
                      final amounts = {
                        for (final key in _salaryAmounts)
                          key: fields[key]!.text,
                      };
                      final invalid = _hasSalaryError(amounts);
                      final incomplete = amounts.values.any(
                        (amount) => amount.trim().isEmpty,
                      );
                      final message = invalid
                          ? 'Please enter a valid salary range.'
                          : !salaryVisible
                          ? salaryNotDisclosed
                          : incomplete
                          ? 'Enter both salary amounts.'
                          : marketplaceSalary(BrowseJob(values(), company: ''));
                      final color = invalid
                          ? JobMateTheme.error
                          : incomplete && salaryVisible
                          ? JobMateTheme.body
                          : JobMateTheme.darkTeal;
                      return Container(
                        key: const ValueKey('salary-display-preview'),
                        padding: const EdgeInsets.all(12),
                        width: double.infinity,
                        decoration: BoxDecoration(
                          color: invalid
                              ? JobMateTheme.error.withValues(alpha: .08)
                              : incomplete && salaryVisible
                              ? JobMateTheme.background
                              : JobMateTheme.teal50,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          'Salary preview: $message',
                          style: TextStyle(
                            color: color,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      );
                    },
                  ),
                ],
              ),
            ),
            JobFormSection(
              title: 'Schedule & Location',
              icon: Icons.location_on_outlined,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  ResponsiveGrid(
                    minItemWidth: 260,
                    maxColumns: 2,
                    children: [
                      _textInput('vacancies'),
                      _textInput('application_deadline'),
                    ],
                  ),
                  const SizedBox(height: 16),
                  _textInput('location'),
                  if (!_remote)
                    ValueListenableBuilder<TextEditingValue>(
                      valueListenable: fields['location']!,
                      builder: (_, _, _) => _workplaceMapField(),
                    ),
                ],
              ),
            ),
            JobFormSection(
              title: 'Job Description & AI Formatting',
              icon: Icons.auto_awesome_outlined,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text(
                    'AI formats your description into structured job details. Your original description stays unchanged.',
                  ),
                  const SizedBox(height: 12),
                  _textInput('original_description'),
                  const ExpansionTile(
                    tilePadding: EdgeInsets.zero,
                    title: Text('View example description'),
                    children: [
                      Padding(
                        padding: EdgeInsets.only(bottom: 16),
                        child: Text(
                          'We are looking for part-time café crew at our café in Shah Alam. You will take orders, serve drinks and light meals, handle payments and keep the counter and tables clean. You should communicate politely with customers and work well in a team. No café experience is needed; training is provided. This is an on-site role with weekend shifts, around 16 hours per week. Staff receive a meal during each shift and a staff discount.',
                        ),
                      ),
                    ],
                  ),
                  if (aiFormatting) const LinearProgressIndicator(),
                  if (aiError != null)
                    Text(
                      aiError!,
                      style: const TextStyle(color: JobMateTheme.error),
                    ),
                  const SizedBox(height: 16),
                  const Text(
                    'Structured details',
                    style: TextStyle(fontWeight: FontWeight.w600),
                  ),
                  const Text(
                    'Review and edit these details before publishing.',
                    style: TextStyle(color: JobMateTheme.body),
                  ),
                  const SizedBox(height: 12),
                  _textInput('role_overview'),
                  const SizedBox(height: 16),
                  _textInput('responsibilities'),
                ],
              ),
            ),
            JobFormSection(
              title: 'Requirements & Benefits',
              icon: Icons.fact_check_outlined,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _textInput('requirements'),
                  const SizedBox(height: 16),
                  _textInput('benefits'),
                ],
              ),
            ),
            if (busy && (aiFormatting || !aiConfirmationPending))
              const LinearProgressIndicator(),
          ],
        ),
      ),
  ];

  Widget _buildWorkspace() => AppWorkspace(
    title: jobId == null
        ? 'Create Job Posting'
        : status == 'closed'
        ? 'Job details'
        : 'Edit Job Posting',
    path: AppRoutes.createJob,
    role: 'employer',
    navigationLocked: busy,
    onNavigate: _navigate,
    leading: kIsWeb
        ? null
        : BackButton(onPressed: busy ? null : _backToPostings),
    child: loading && !_creating
        ? const Center(child: CircularProgressIndicator())
        : WorkspaceContent(
            maxWidth: 880,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton.icon(
                    onPressed: busy ? null : _backToPostings,
                    icon: const Icon(Icons.arrow_back, size: 18),
                    label: const Text('Back to Job Postings'),
                  ),
                ),
                PageHeading(
                  title: jobId == null
                      ? 'Create Job Posting'
                      : status == 'closed'
                      ? 'Job details'
                      : 'Edit Job Posting',
                  description: status == 'closed'
                      ? 'This posting is closed. Its details remain available for reference.'
                      : status == 'published'
                      ? 'Review your posting and use Save Changes to update it.'
                      : 'Build your posting, save a draft or publish when ready.',
                ),
                ..._formContent(),
                if (_showActions)
                  JobFormSection(
                    title: status == 'published'
                        ? 'Update your posting'
                        : status == 'closed'
                        ? 'Review posting'
                        : 'Ready to publish?',
                    icon: Icons.check_circle_outline,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(
                          status == 'published'
                              ? 'Preview your edits, then choose Save Changes.'
                              : status == 'closed'
                              ? 'Closed postings are read-only.'
                              : 'Save an incomplete draft or review all required fields before publishing.',
                        ),
                        const SizedBox(height: 12),
                        _buildActions(),
                      ],
                    ),
                  ),
              ],
            ),
          ),
  );
}
