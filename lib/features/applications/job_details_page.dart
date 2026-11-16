import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:go_router/go_router.dart';

import '../../shared/navigation/app_routes.dart';
import '../../shared/widgets/app_workspace.dart';
import '../jobs/job_display.dart';
import 'module2_repository.dart';
import 'module2_widgets.dart';
import 'job_details_presentation.dart';
import 'job_marketplace_format.dart';
import 'published_company_logo.dart';
import 'job_application_form.dart';
import 'my_applications_repository.dart';
import '../company/company_profile_sections.dart';

class JobFacts extends StatelessWidget {
  const JobFacts(this.job, {super.key});
  final BrowseJob job;
  @override
  Widget build(BuildContext context) => Wrap(
    spacing: 16,
    runSpacing: 8,
    children: [
      for (final key in ['location', 'employment_type', 'work_arrangement'])
        Chip(label: Text(jobLabel(job.text(key)))),
      Text('Vacancies: ${job.text('vacancies')}'),
      Text('Deadline: ${jobDate(job.fields['application_deadline'])}'),
      if (job.fields['salary_visible'] == true &&
          job.fields['salary_min'] != null &&
          job.fields['salary_max'] != null)
        Text('Salary: ${jobSalary(job.fields)}')
      else
        const Text('Not disclosed'),
    ],
  );
}

class JobDetailsPage extends StatefulWidget {
  const JobDetailsPage({super.key, required this.jobId, this.repository});
  final String jobId;
  final Module2Repository? repository;
  @override
  State<JobDetailsPage> createState() => _JobDetailsPageState();
}

class _JobDetailsPageState extends State<JobDetailsPage>
    with WidgetsBindingObserver {
  late final repo = (widget.repository ?? Module2Repository.session).browse;
  late final applications = MyApplicationsRepository(
    (widget.repository ?? Module2Repository.session).myApplications.source,
  );
  Listenable? _routerChanges;
  bool _wasCurrent = true, _applying = false;
  String? _submittedId, _submittedActor;

  Future<void> _reload() async {
    await Future.wait([repo.load(), applications.load()]);
  }

  void _routeChanged() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final current = ModalRoute.of(context)?.isCurrent ?? true;
      if (current && !_wasCurrent) applications.load();
      _wasCurrent = current;
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final changes = GoRouter.maybeOf(context)?.routerDelegate;
    if (!identical(changes, _routerChanges)) {
      _routerChanges?.removeListener(_routeChanged);
      _routerChanges = changes;
      _routerChanges?.addListener(_routeChanged);
      _wasCurrent = ModalRoute.of(context)?.isCurrent ?? true;
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) applications.load();
  }

  Future<void> apply(BrowseJob job) async {
    if (_applying ||
        applications.loading ||
        !applications.loaded ||
        applications.error != null ||
        applications.search().any((a) => a.jobId == job.id) ||
        (_submittedId != null &&
            _submittedActor == applications.source.userId)) {
      return;
    }
    setState(() => _applying = true);
    final module = widget.repository ?? Module2Repository.session;
    final actor = repo.source.userId;
    final route = await moduleModal<String>(
      context,
      JobApplicationForm(
        job: job,
        repository: module,
        gateway: module.createApplicationGateway(),
        onSubmitted: (id) {
          if (!mounted ||
              widget.jobId != job.id ||
              actor != applications.source.userId) {
            return;
          }
          setState(() {
            _submittedId = id;
            _submittedActor = actor;
          });
          applications.load();
        },
      ),
    );
    if (!mounted) return;
    setState(() => _applying = false);
    await applications.load();
    if (!mounted || route == null || repo.source.userId != actor) return;
    await context.push<void>(route);
    if (!mounted) return;
    await applications.load();
    if (mounted &&
        route == AppRoutes.documentSubmission &&
        repo.source.userId == actor) {
      final current = repo.job(job.id);
      if (current != null) await apply(current);
    }
  }

  void refresh() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _reload();
    });
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    refresh();
  }

  @override
  void didUpdateWidget(covariant JobDetailsPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.jobId != widget.jobId) {
      _submittedId = null;
      refresh();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _routerChanges?.removeListener(_routeChanged);
    applications.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([repo, applications]),
      builder: (context, _) {
        final job = repo.job(widget.jobId);
        final existing = applications
            .search()
            .where((a) => a.jobId == widget.jobId)
            .firstOrNull;
        final submittedId = _submittedActor == applications.source.userId
            ? _submittedId
            : null;
        final applicationId = existing?.id ?? submittedId;
        final checking =
            applications.loading ||
            (!applications.loaded && applications.error == null);
        return AppWorkspace(
          title: 'Job Details',
          leading: kIsWeb
              ? null
              : BackButton(
                  onPressed: () => moduleBack(context, AppRoutes.browseJobs),
                ),
          path: AppRoutes.browseJobs,
          role: 'job_seeker',
          actions: [
            IconButton(
              tooltip: 'Refresh job',
              onPressed: repo.loading || applications.loading || _applying
                  ? null
                  : _reload,
              icon: const Icon(Icons.refresh),
            ),
          ],
          child: WorkspaceContent(
            maxWidth: 880,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton.icon(
                    onPressed: () => moduleBack(context, AppRoutes.browseJobs),
                    icon: const Icon(Icons.arrow_back),
                    label: const Text('Back to Browse Jobs'),
                  ),
                ),
                if (repo.loading || (!repo.loaded && repo.error == null))
                  const Center(child: CircularProgressIndicator())
                else if (repo.error != null)
                  ModuleState(
                    title: 'Unable to load job',
                    message: repo.error!,
                    action: repo.load,
                    actionLabel: 'Retry',
                  )
                else if (job == null)
                  const ModuleState(
                    title: 'Job unavailable',
                    message: 'This job is unavailable or no longer published.',
                  )
                else ...[
                  JobDetailCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            PublishedCompanyLogo(
                              job: job,
                              repository: repo,
                              size: 40,
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    job.title,
                                    style: Theme.of(context)
                                        .textTheme
                                        .headlineSmall
                                        ?.copyWith(fontWeight: FontWeight.w700),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(job.company),
                                ],
                              ),
                            ),
                            IconButton(
                              tooltip: repo.saved(job.id)
                                  ? 'Unsave Job (this session)'
                                  : 'Save Job (this session)',
                              isSelected: repo.saved(job.id),
                              onPressed: () => repo.toggleSave(job.id),
                              icon: const Icon(Icons.bookmark_border),
                              selectedIcon: const Icon(Icons.bookmark),
                            ),
                          ],
                        ),
                        const SizedBox(height: 18),
                        JobInformationGrid(job),
                        const SizedBox(height: 16),
                        if (job.unavailable() case final String reason)
                          Text(
                            reason,
                            style: TextStyle(
                              color: Theme.of(context).colorScheme.error,
                            ),
                          ),
                        const SizedBox(height: 12),
                        if (applicationId != null) ...[
                          JobApplicationBanner(existing?.status),
                          const SizedBox(height: 10),
                          Align(
                            alignment: Alignment.centerLeft,
                            child: FilledButton(
                              onPressed: _applying
                                  ? null
                                  : () async {
                                      await context.push<void>(
                                        '${AppRoutes.applications}/$applicationId',
                                      );
                                      if (mounted) await applications.load();
                                    },
                              child: const Text('View Application'),
                            ),
                          ),
                        ] else if (applications.error != null) ...[
                          const Text(
                            'Unable to check your application status. Refresh before applying.',
                          ),
                          TextButton(
                            onPressed: applications.loading
                                ? null
                                : applications.load,
                            child: const Text('Retry application status'),
                          ),
                        ] else
                          Align(
                            alignment: Alignment.centerLeft,
                            child: FilledButton(
                              onPressed:
                                  checking ||
                                      _applying ||
                                      applications.source.userId == null ||
                                      job.unavailable() != null
                                  ? null
                                  : () => apply(job),
                              child: Text(
                                checking
                                    ? 'Checking application status…'
                                    : 'Apply Now',
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                  for (final entry in [
                    ('role_overview', 'Role Overview'),
                    ('original_description', 'Job Description'),
                    ('responsibilities', 'Responsibilities'),
                    ('requirements', 'Requirements'),
                    ('benefits', 'Benefits'),
                  ])
                    if (JobContent.hasContent(job.fields[entry.$1]))
                      Padding(
                        padding: const EdgeInsets.only(top: 14),
                        child: JobDetailCard(
                          title: entry.$2,
                          child: JobContent(job.fields[entry.$1]),
                        ),
                      ),
                  if (job.text('department').isNotEmpty ||
                      job.text('published_at').isNotEmpty) ...[
                    const SizedBox(height: 14),
                    JobDetailCard(
                      title: 'Additional information',
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (job.text('department').isNotEmpty)
                            Text('Department: ${job.text('department')}'),
                          if (job.text('published_at').isNotEmpty)
                            Text(
                              'Published: ${marketplaceDate(job.fields['published_at'])}',
                            ),
                        ],
                      ),
                    ),
                  ],
                  const SizedBox(height: 14),
                  JobDetailCard(
                    title: 'About the Company',
                    child: Row(
                      children: [
                        PublishedCompanyLogo(
                          job: job,
                          repository: repo,
                          size: 36,
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                job.company,
                                style: const TextStyle(
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              if (job.text('company_id').isNotEmpty)
                                PublicCompanyProfileButton(
                                  companyId: job.text('company_id'),
                                ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
        );
      },
    );
  }
}

class ApplyDemoForm extends StatefulWidget {
  const ApplyDemoForm({super.key, required this.job, required this.repository});
  final BrowseJob job;
  final Module2Repository repository;
  @override
  State<ApplyDemoForm> createState() => _ApplyDemoFormState();
}

class _ApplyDemoFormState extends State<ApplyDemoForm> {
  late final draftKey = 'cover:${widget.job.id}';
  late final note = TextEditingController(
    text: widget.repository.noteDraft(draftKey),
  );
  bool busy = false, success = false, leaving = false;
  String? error;
  @override
  void dispose() {
    note.dispose();
    super.dispose();
  }

  Future<void> close() async {
    if (busy) return;
    if (!success && note.text.trim().isNotEmpty) {
      final discard = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Discard cover note?'),
          content: const Text('This demo note has not been saved.'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Keep editing'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Discard'),
            ),
          ],
        ),
      );
      if (discard != true || !mounted) return;
    }
    setState(() => leaving = true);
    widget.repository.clearNoteDraft(draftKey);
    // Rebuild PopScope before asking Navigator to close the modal.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) Navigator.of(context).pop();
    });
  }

  Future<void> submit() async {
    if (busy || success) return;
    setState(() {
      busy = true;
      error = null;
    });
    try {
      await widget.repository.submit(widget.job.id, note.text);
      widget.repository.clearNoteDraft(draftKey);
      if (mounted) setState(() => success = true);
    } on StateError catch (e) {
      if (mounted) setState(() => error = e.message.toString());
    } catch (_) {
      if (mounted) {
        setState(
          () => error =
              'Could not update the demo. Your note is preserved; retry.',
        );
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: leaving || (!busy && (success || note.text.trim().isEmpty)),
    onPopInvokedWithResult: (didPop, result) {
      if (!didPop) close();
    },
    child: ModalBody(
      title: success
          ? 'Demo application recorded'
          : 'Apply to ${widget.job.title}',
      actions: [
        TextButton(
          onPressed: busy ? null : close,
          child: Text(success ? 'Done' : 'Cancel'),
        ),
        if (!success)
          FilledButton(
            onPressed: busy ? null : submit,
            child: Text(
              busy
                  ? 'Saving demo…'
                  : error == null
                  ? 'Submit demo application'
                  : 'Retry demo submission',
            ),
          ),
      ],
      children: [
        const DemoNotice(),
        Text(widget.job.company),
        const SizedBox(height: 16),
        if (success)
          const Text(
            'Saved only in this session’s demo. No application was sent and no resume was uploaded. You can find it in My Applications.',
          )
        else ...[
          const Text(
            'Demo candidate (you) • Profile details are not connected. Resume missing: no file will be shared. A resume is not required for this preview.',
          ),
          const SizedBox(height: 20),
          TextField(
            controller: note,
            enabled: !busy,
            maxLength: 1000,
            minLines: 4,
            maxLines: 8,
            onChanged: (value) {
              widget.repository.keepNoteDraft(draftKey, value);
              setState(() {});
            },
            decoration: const InputDecoration(
              labelText: 'Cover note (optional)',
              alignLabelWithHint: true,
            ),
          ),
          if (error != null)
            Semantics(
              liveRegion: true,
              child: Text(
                error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ),
          if (busy) const LinearProgressIndicator(),
        ],
      ],
    ),
  );
}
