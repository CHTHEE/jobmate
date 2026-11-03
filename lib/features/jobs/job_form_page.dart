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
import '../../shared/widgets/loading_overlay.dart';
import 'job_postings_repository.dart';
import 'job_preview.dart';
import 'job_display.dart';
import 'job_validation.dart';
import '../company/company_logo.dart';
import 'job_ai_formatter.dart';

class JobFormPage extends StatefulWidget {
  const JobFormPage({super.key, this.jobId, this.repository});
  final String? jobId;
  final JobPostingsRepository? repository;
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
  String? _savedSnapshot;
  Future<bool>? _exitConfirmation;
  String get _snapshot => jsonEncode({
    for (final entry in fields.entries) entry.key: entry.value.text,
    ...selected,
    'salary_visible': salaryVisible,
    'ai_assisted': aiAssisted,
  });

  Future<bool> confirmExit() async {
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
        savedJob = job;
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

  String? validate(String key, String value) =>
      jobFieldError(key, validationValues(), publishing: publishing);

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
      final saved = await repo.save(
        {...values(), 'status': publishing ? 'published' : 'draft'},
        jobId: jobId,
        expectedStatus: status,
      );
      if (!mounted) return;
      setState(() {
        jobId = saved['job_id'].toString();
        status = saved['status'] as String;
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

  Widget _buildWorkspace() => AppWorkspace(
    title: jobId == null ? 'Create Job' : 'Job details',
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
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                PageHeading(
                  title: jobId == null
                      ? 'Create a job'
                      : status == 'closed'
                      ? 'Job details'
                      : 'Edit your posting',
                  description: status == 'closed'
                      ? 'This posting is closed. Its details remain available for reference.'
                      : 'Turn your hiring needs into a clear, thoughtful opportunity. Your work is saved only when you choose Save Draft or Publish.',
                ),
                if (error != null) ...[
                  Text(error!, style: const TextStyle(color: Colors.red)),
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
                    // Revalidate on controller, dropdown and widget updates
                    // after submission, including dependent salary fields.
                    autovalidateMode: validationActivated
                        ? AutovalidateMode.always
                        : AutovalidateMode.disabled,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        requiredLabel('Verified hiring company'),
                        const Text(
                          'Fields marked * are required before publishing. Drafts may be incomplete.',
                        ),
                        CompanyIdentity(
                          name: access!.company!['company_name'] as String,
                          logo: access!.logo,
                        ),
                        const Text(
                          'Your verified hiring company is selected automatically from your membership and cannot be changed here.',
                        ),
                        const SizedBox(height: 16),

                        for (final section
                            in <(String, IconData, List<String>, List<String>)>[
                              (
                                'Basic job information',
                                Icons.work_outline,
                                ['title', 'department'],
                                ['employment_type'],
                              ),
                              (
                                'Compensation',
                                Icons.payments_outlined,
                                ['salary_min', 'salary_max'],
                                ['salary_period'],
                              ),
                              (
                                'Schedule & location',
                                Icons.location_on_outlined,
                                [
                                  'location',
                                  'vacancies',
                                  'application_deadline',
                                ],
                                ['work_arrangement'],
                              ),
                              (
                                'Description & AI formatting',
                                Icons.auto_awesome_outlined,
                                [
                                  'original_description',
                                  'role_overview',
                                  'responsibilities',
                                ],
                                [],
                              ),
                              (
                                'Requirements & benefits',
                                Icons.fact_check_outlined,
                                ['requirements', 'benefits'],
                                [],
                              ),
                            ]) ...[
                          const SizedBox(height: 20),
                          WorkspaceCard(
                            title: section.$1,
                            leading: Icon(
                              section.$2,
                              size: 18,
                              color: AuthStyle.teal,
                            ),
                            child: LayoutBuilder(
                              builder: (context, constraints) {
                                final width = constraints.maxWidth >= 540
                                    ? (constraints.maxWidth - 16) / 2
                                    : constraints.maxWidth;
                                return Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.stretch,
                                  children: [
                                    Wrap(
                                      spacing: 16,
                                      runSpacing: 16,
                                      children: [
                                        for (final entry
                                            in fields.entries.where(
                                              (e) => section.$3.contains(e.key),
                                            )) ...[
                                          SizedBox(
                                            width:
                                                [
                                                  'original_description',
                                                  'role_overview',
                                                  'responsibilities',
                                                  'requirements',
                                                  'benefits',
                                                ].contains(entry.key)
                                                ? constraints.maxWidth
                                                : width,
                                            child: TextFormField(
                                              key: fieldKeys.putIfAbsent(
                                                entry.key,
                                                () =>
                                                    GlobalKey<
                                                      FormFieldState<String>
                                                    >(),
                                              ),
                                              controller: entry.value,
                                              enabled:
                                                  !busy && status != 'closed',
                                              minLines:
                                                  [
                                                    'original_description',
                                                    'role_overview',
                                                    'responsibilities',
                                                    'requirements',
                                                    'benefits',
                                                  ].contains(entry.key)
                                                  ? 3
                                                  : 1,
                                              maxLines:
                                                  [
                                                    'original_description',
                                                    'role_overview',
                                                    'responsibilities',
                                                    'requirements',
                                                    'benefits',
                                                  ].contains(entry.key)
                                                  ? 8
                                                  : 1,
                                              keyboardType:
                                                  [
                                                    'original_description',
                                                    'role_overview',
                                                    'responsibilities',
                                                    'requirements',
                                                    'benefits',
                                                  ].contains(entry.key)
                                                  ? TextInputType.multiline
                                                  : entry.key.startsWith(
                                                          'salary_',
                                                        ) ||
                                                        entry.key == 'vacancies'
                                                  ? const TextInputType.numberWithOptions(
                                                      decimal: true,
                                                    )
                                                  : TextInputType.text,
                                              textInputAction:
                                                  [
                                                    'original_description',
                                                    'role_overview',
                                                    'responsibilities',
                                                    'requirements',
                                                    'benefits',
                                                  ].contains(entry.key)
                                                  ? TextInputAction.newline
                                                  : null,
                                              decoration: InputDecoration(
                                                label: requiredLabel(
                                                  jobLabel(entry.key),
                                                ),
                                                hintText:
                                                    jobExamples[entry.key],
                                                helperMaxLines: 5,
                                                suffixIcon:
                                                    entry.key ==
                                                        'application_deadline'
                                                    ? IconButton(
                                                        tooltip: 'Choose application deadline',
                                                        onPressed:
                                                            busy ||
                                                                status ==
                                                                    'closed'
                                                            ? null
                                                            : pickDeadline,
                                                        icon: const Icon(
                                                          Icons
                                                              .calendar_month_outlined,
                                                        ),
                                                      )
                                                    : null,
                                                helperText:
                                                    [
                                                      'responsibilities',
                                                      'requirements',
                                                      'benefits',
                                                    ].contains(entry.key)
                                                    ? 'Press Enter to start a new bullet point. You can write full sentences or short phrases on each line.'
                                                    : entry.key ==
                                                          'application_deadline'
                                                    ? 'YYYY-MM-DD. Choose a future date before publishing.'
                                                    : entry.key ==
                                                          'original_description'
                                                    ? 'Describe duties, requirements, working arrangements and benefits in normal sentences.'
                                                    : entry.key ==
                                                          'role_overview'
                                                    ? 'You can write multiple sentences or paragraphs. Press Enter to start a new line.'
                                                    : entry.key == 'location'
                                                    ? 'Enter the workplace for on-site/hybrid jobs, or the work region for remote jobs.'
                                                    : null,
                                              ),
                                              validator: (v) =>
                                                  validate(entry.key, v ?? ''),
                                            ),
                                          ),

                                          if (entry.key ==
                                              'original_description')
                                            SizedBox(
                                              width: constraints.maxWidth,
                                              child: Column(
                                                crossAxisAlignment:
                                                    CrossAxisAlignment.start,
                                                children: [
                                                  const Text(
                                                    'Format with AI generates Role Overview, Responsibilities, Requirements and Benefits. Your Original Description stays unchanged. Review and edit the generated text before publishing.',
                                                  ),
                                                  const ExpansionTile(
                                                    tilePadding:
                                                        EdgeInsets.zero,
                                                    title: Text(
                                                      'View example description',
                                                    ),
                                                    children: [
                                                      Padding(
                                                        padding:
                                                            EdgeInsets.only(
                                                              bottom: 16,
                                                            ),
                                                        child: Text(
                                                          'We are looking for part-time café crew at our café in Shah Alam. You will take orders, serve drinks and light meals, handle payments and keep the counter and tables clean. You should communicate politely with customers and work well in a team. No café experience is needed; training is provided. This is an on-site role with weekend shifts, around 16 hours per week. Staff receive a meal during each shift and a staff discount.',
                                                        ),
                                                      ),
                                                    ],
                                                  ),
                                                  const SizedBox(height: 8),
                                                  OutlinedButton(
                                                    onPressed:
                                                        busy ||
                                                            status == 'closed'
                                                        ? null
                                                        : formatWithAi,
                                                    child: Text(
                                                      aiFormatting
                                                          ? 'Formatting…'
                                                          : 'Format with AI ✨',
                                                    ),
                                                  ),
                                                  if (aiFormatting)
                                                    const Padding(
                                                      padding: EdgeInsets.only(
                                                        top: 8,
                                                      ),
                                                      child:
                                                          LinearProgressIndicator(),
                                                    ),
                                                  if (aiError != null)
                                                    Text(
                                                      aiError!,
                                                      style: TextStyle(
                                                        color: Theme.of(context)
                                                            .colorScheme
                                                            .error,
                                                      ),
                                                    ),
                                                ],
                                              ),
                                            ),
                                        ],
                                        for (final entry
                                            in options.entries.where(
                                              (e) => section.$4.contains(e.key),
                                            ))
                                          SizedBox(
                                            width: width,
                                            child:
                                                DropdownButtonFormField<String>(
                                                  key: fieldKeys.putIfAbsent(
                                                    entry.key,
                                                    () =>
                                                        GlobalKey<
                                                          FormFieldState<String>
                                                        >(),
                                                  ),
                                                  validator: (v) => validate(
                                                    entry.key,
                                                    v ?? '',
                                                  ),
                                                  initialValue:
                                                      selected[entry.key],
                                                  decoration: InputDecoration(
                                                    label: requiredLabel(
                                                      jobLabel(entry.key),
                                                    ),
                                                    helperMaxLines: 3,
                                                    helperText:
                                                        entry.key ==
                                                            'work_arrangement'
                                                        ? 'On-site: at the workplace. Hybrid: workplace and remote. Remote: off-site.'
                                                        : entry.key ==
                                                              'employment_type'
                                                        ? 'Choose the contract or working schedule for this role.'
                                                        : 'How often the salary amount is paid.',
                                                  ),
                                                  items:
                                                      {
                                                            ...entry.value,
                                                            selected[entry
                                                                .key]!,
                                                          }
                                                          .map(
                                                            (v) =>
                                                                DropdownMenuItem(
                                                                  value: v,
                                                                  child: Text(
                                                                    jobLabel(v),
                                                                  ),
                                                                ),
                                                          )
                                                          .toList(),
                                                  onChanged:
                                                      busy || status == 'closed'
                                                      ? null
                                                      : (v) => setState(
                                                          () =>
                                                              selected[entry
                                                                      .key] =
                                                                  v!,
                                                        ),
                                                ),
                                          ),
                                      ],
                                    ),
                                    if (section.$1 == 'Compensation')
                                      SwitchListTile(
                                        contentPadding: EdgeInsets.zero,
                                        title: const Text(
                                          'Show salary on posting',
                                        ),
                                        subtitle: const Text(
                                          'Turn off to hide salary amounts from job seekers.',
                                        ),
                                        value: salaryVisible,
                                        onChanged: busy || status == 'closed'
                                            ? null
                                            : (v) => setState(
                                                () => salaryVisible = v,
                                              ),
                                      ),
                                  ],
                                );
                              },
                            ),
                          ),
                        ],
                        const SizedBox(height: 20),
                        Wrap(
                          spacing: 12,
                          runSpacing: 12,
                          children: [
                            if (status == 'published')
                              FilledButton(
                                onPressed: busy ? null : () => save(true),
                                child: const Text('Save Changes'),
                              ),
                            if (status == 'draft') ...[
                              OutlinedButton(
                                onPressed: busy ? null : () => save(false),
                                child: const Text('Save Draft'),
                              ),
                              FilledButton(
                                onPressed: busy ? null : () => save(true),
                                child: const Text('Publish'),
                              ),
                            ],
                            OutlinedButton(
                              onPressed: busy
                                  ? null
                                  : () => showDialog<void>(
                                      context: context,
                                      builder: (_) => JobPreview(
                                        logo: access!.logo,
                                        job: {...?savedJob, ...values()},
                                        company:
                                            access!.company!['company_name']
                                                as String,
                                      ),
                                    ),
                              child: const Text('Preview'),
                            ),
                            TextButton(
                              onPressed: busy ? null : _backToPostings,
                              child: const Text('Back to Job Postings'),
                            ),
                          ],
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
