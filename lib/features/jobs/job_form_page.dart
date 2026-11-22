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
  });
  final String? jobId;
  final JobPostingsRepository? repository;
  final WorkplacePicker pickWorkplace;
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
    'employment_type': [
      'full_time',
      'part_time',
      'contract',
      'internship',
      'temporary',
    ],
    'work_arrangement': ['on_site', 'hybrid', 'remote'],
    'salary_period': ['hourly', 'daily', 'monthly', 'yearly'],
  };
  final selected = {
    'employment_type': 'full_time',
    'work_arrangement': 'on_site',
    'salary_period': 'monthly',
  };
  JobAccess? access;
  String? error;
  String? jobId;
  bool loading = true, busy = false, publishing = false, salaryVisible = true;
  bool validationActivated = false;
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
    if (!mounted || _remote || address != _address || result == null) return;
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
    load();
  }

  @override
  void dispose() {
    for (final c in fields.values) {
      c.dispose();
    }
    super.dispose();
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
          selected[key] = job[key] as String? ?? selected[key]!;
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
    'salary_visible': salaryVisible,
    'ai_assisted': aiAssisted,
  };
  Future<void> save(bool publish) async {
    if (busy || status == 'closed') return;
    final updatingPublished = status == 'published';
    setState(() {
      publishing = publish || updatingPublished;
      validationActivated = true;
    });
    if (!form.currentState!.validate()) {
      for (final key in [...fields.keys, ...options.keys]) {
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
      );
      if (!mounted) return;
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
        context.pop(status);
      } else {
        context.pushReplacement('${AppRoutes.jobPostings}?status=$status');
      }
    } catch (e) {
      if (mounted) setState(() => error = jobError(e));
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
      if (!mounted) return;
      FocusManager.instance.primaryFocus?.unfocus();
      setState(() => aiFormatting = true);
      final generated = await repo
          .formatDescription(description)
          .timeout(const Duration(seconds: 60));
      if (!mounted) return;
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
      child: _buildWorkspace(),
    ),
  );

  Widget _textInput(String key) {
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
              onPressed: busy || status == 'closed' ? null : formatWithAi,
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
          onChanged: key == 'location'
              ? (_) => setState(() {
                  if (_address != _confirmedAddress) _confirmedAddress = null;
                })
              : null,
          enabled: !busy && status != 'closed',
          minLines: multiline ? 3 : 1,
          maxLines: multiline ? 8 : 1,
          keyboardType: multiline
              ? TextInputType.multiline
              : key.startsWith('salary_') || key == 'vacancies'
              ? const TextInputType.numberWithOptions(decimal: true)
              : TextInputType.text,
          textInputAction: multiline ? TextInputAction.newline : null,
          decoration: InputDecoration(
            hintText: jobExamples[key],
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
      onPressed: enabled && _address.isNotEmpty ? _chooseWorkplace : null,
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

  Widget _selection(String key) => JobLabeledField(
    label: requiredLabel(jobLabel(key)),
    child: key == 'employment_type'
        ? FormField<String>(
            key: fieldKeys.putIfAbsent(
              key,
              () => GlobalKey<FormFieldState<String>>(),
            ),
            initialValue: selected[key],
            validator: (value) => validate(key, value ?? ''),
            builder: (state) => Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final value in {...options[key]!, selected[key]!})
                      ChoiceChip(
                        label: Text(jobLabel(value)),
                        selected: selected[key] == value,
                        onSelected: busy || status == 'closed'
                            ? null
                            : (_) {
                                state.didChange(value);
                                setState(() => selected[key] = value);
                              },
                      ),
                  ],
                ),
                if (state.errorText != null)
                  Text(
                    state.errorText!,
                    style: const TextStyle(color: JobMateTheme.error),
                  ),
              ],
            ),
          )
        : Semantics(
            label: '${jobLabel(key)}, required before publishing',
            child: DropdownButtonFormField<String>(
              key: fieldKeys.putIfAbsent(
                key,
                () => GlobalKey<FormFieldState<String>>(),
              ),
              initialValue: selected[key],
              isExpanded: true,
              validator: (value) => validate(key, value ?? ''),
              decoration: InputDecoration(
                helperMaxLines: 4,
                errorMaxLines: 4,
                helperText: key == 'work_arrangement'
                    ? 'On-site: at the workplace. Hybrid: workplace and remote. Remote: off-site.'
                    : 'How often the salary amount is paid.',
              ),
              items: [
                for (final value in {...options[key]!, selected[key]!})
                  DropdownMenuItem(value: value, child: Text(jobLabel(value))),
              ],
              onChanged: busy || status == 'closed'
                  ? null
                  : (value) => setState(() => selected[key] = value!),
            ),
          ),
  );

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
    child: loading
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
                if (error != null) ...[
                  Text(
                    error!,
                    style: const TextStyle(color: JobMateTheme.error),
                  ),
                  TextButton(
                    onPressed: busy ? null : load,
                    child: const Text('Reload'),
                  ),
                ],
                if (access != null && !access!.allowed)
                  WorkspaceCard(
                    title: 'Job creation unavailable',
                    child: Column(
                      children: [
                        Text(access!.message!),
                        TextButton(
                          onPressed: () => context.push(AppRoutes.company),
                          child: const Text('Company profile'),
                        ),
                        const FilledButton(
                          onPressed: null,
                          child: Text('Create Job'),
                        ),
                      ],
                    ),
                  ),
                if (access?.allowed == true)
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
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  if (access!.logo == null) ...[
                                    const CircleAvatar(
                                      child: Icon(Icons.business_outlined),
                                    ),
                                    const SizedBox(width: 12),
                                  ],
                                  Expanded(
                                    child: CompanyIdentity(
                                      name:
                                          access!.company!['company_name']
                                              as String,
                                      logo: access!.logo,
                                    ),
                                  ),
                                ],
                              ),
                              if (access!.company!['verification_status'] ==
                                  'verified')
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
                                          style: TextStyle(
                                            color: JobMateTheme.darkTeal,
                                          ),
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
                          ),
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
                              _textInput('title'),
                              const SizedBox(height: 16),
                              _textInput('department'),
                              const SizedBox(height: 16),
                              _selection('employment_type'),
                            ],
                          ),
                        ),
                        JobFormSection(
                          title: 'Compensation',
                          icon: Icons.payments_outlined,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              ResponsiveGrid(
                                minItemWidth: 200,
                                maxColumns: 3,
                                children: [
                                  _textInput('salary_min'),
                                  _textInput('salary_max'),
                                  _selection('salary_period'),
                                ],
                              ),
                              const SizedBox(height: 16),
                              _textInput('vacancies'),
                              SwitchListTile(
                                contentPadding: EdgeInsets.zero,
                                title: const Text('Show salary on posting'),
                                subtitle: const Text(
                                  'Turn off to hide salary amounts from job seekers.',
                                ),
                                value: salaryVisible,
                                onChanged: busy || status == 'closed'
                                    ? null
                                    : (value) =>
                                          setState(() => salaryVisible = value),
                              ),
                              ListenableBuilder(
                                listenable: Listenable.merge([
                                  fields['salary_min']!,
                                  fields['salary_max']!,
                                ]),
                                builder: (context, _) => Container(
                                  key: const ValueKey('salary-display-preview'),
                                  padding: const EdgeInsets.all(12),
                                  width: double.infinity,
                                  decoration: BoxDecoration(
                                    color: JobMateTheme.teal50,
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: Text(
                                    salaryVisible
                                        ? 'Salary preview: ${marketplaceSalary(BrowseJob(values(), company: ''))}'
                                        : 'Salary preview: Hidden from job seekers',
                                    style: const TextStyle(
                                      color: JobMateTheme.darkTeal,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ),
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
                                  _textInput('application_deadline'),
                                  _selection('work_arrangement'),
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
                                  style: const TextStyle(
                                    color: JobMateTheme.error,
                                  ),
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
                              LayoutBuilder(
                                builder: (context, box) {
                                  final draft = status == 'draft'
                                      ? OutlinedButton(
                                          onPressed: busy
                                              ? null
                                              : () => save(false),
                                          child: const Text('Save Draft'),
                                        )
                                      : null;
                                  final preview = TextButton.icon(
                                    onPressed: busy
                                        ? null
                                        : () => showDialog<void>(
                                            context: context,
                                            builder: (_) => JobPreview(
                                              logo: access!.logo,
                                              job: {
                                                ...?savedJob,
                                                ...values(),
                                                'latitude': _pin?.latitude,
                                                'longitude': _pin?.longitude,
                                              },
                                              company:
                                                  access!.company!['company_name']
                                                      as String,
                                            ),
                                          ),
                                    icon: const Icon(
                                      Icons.visibility_outlined,
                                      size: 18,
                                    ),
                                    label: const Text('Preview'),
                                  );
                                  final primary = status == 'closed'
                                      ? null
                                      : FilledButton(
                                          onPressed: busy
                                              ? null
                                              : () => save(true),
                                          child: Text(
                                            status == 'published'
                                                ? 'Save Changes'
                                                : 'Publish Job',
                                          ),
                                        );
                                  if (box.maxWidth <
                                      560 *
                                          MediaQuery.textScalerOf(context)
                                              .scale(14) /
                                          14) {
                                    return Wrap(
                                      spacing: 12,
                                      runSpacing: 10,
                                      children: [?draft, preview, ?primary],
                                    );
                                  }
                                  return Row(
                                    children: [
                                      ?draft,
                                      const SizedBox(width: 12),
                                      preview,
                                      const Spacer(),
                                      ?primary,
                                    ],
                                  );
                                },
                              ),
                            ],
                          ),
                        ),
                        if (busy && (aiFormatting || !aiConfirmationPending))
                          const LinearProgressIndicator(),
                      ],
                    ),
                  ),
              ],
            ),
          ),
  );
}
